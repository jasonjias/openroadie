import Foundation
import SwiftData
import Testing
@testable import OpenRoadie

private func drivingContext(
    lat: Double, lon: Double, speed: Double? = 15, altitude: Double? = 30, at seconds: TimeInterval
) -> DrivingContext {
    var context = DrivingContext()
    context.coordinate = Coordinate(latitude: lat, longitude: lon)
    context.timestamp = Date(timeIntervalSinceReferenceDate: seconds)
    context.speed = speed
    context.altitude = altitude
    return context
}

@MainActor
struct TripStoreTests {
    private func makeStore() throws -> TripStore {
        try TripStore.inMemory()
    }

    private func allTrips(_ store: TripStore) throws -> [Trip] {
        try store.container.mainContext.fetch(FetchDescriptor<Trip>())
    }

    @Test func endedTripPersistsRouteAndStats() throws {
        let store = try makeStore()
        let trip = store.beginTrip(at: Date(timeIntervalSinceReferenceDate: 0))

        store.recordPoint(from: drivingContext(lat: 37.0, lon: -122.0, at: 1), in: trip)
        store.recordPoint(from: drivingContext(lat: 37.001, lon: -122.0, at: 11), in: trip)
        store.recordPoint(from: drivingContext(lat: 37.002, lon: -122.0, at: 21), in: trip)
        store.endTrip(trip, at: Date(timeIntervalSinceReferenceDate: 30), distance: 222, maxSpeed: 20)

        let saved = try #require(try allTrips(store).first)
        #expect(saved.endDate == Date(timeIntervalSinceReferenceDate: 30))
        #expect(saved.distance == 222)
        #expect(saved.maxSpeed == 20)
        #expect(saved.duration == 30)
        #expect(saved.route.count == 3)
        // Route is ordered by time regardless of relationship storage order.
        #expect(saved.route.first?.latitude == 37.0)
        #expect(saved.route.last?.latitude == 37.002)
    }

    @Test func trivialTripIsDiscardedOnEnd() throws {
        let store = try makeStore()
        let trip = store.beginTrip(at: .init(timeIntervalSinceReferenceDate: 0))
        store.recordPoint(from: drivingContext(lat: 37.0, lon: -122.0, at: 1), in: trip)
        store.endTrip(trip, at: .init(timeIntervalSinceReferenceDate: 5), distance: 0, maxSpeed: nil)

        #expect(try allTrips(store).isEmpty)
    }

    @Test func recordPointIgnoresContextWithoutFix() throws {
        let store = try makeStore()
        let trip = store.beginTrip(at: .init(timeIntervalSinceReferenceDate: 0))
        store.recordPoint(from: DrivingContext(), in: trip)
        #expect(trip.points.isEmpty)
    }

    @Test func closeDanglingTripsFinalizesFromRoute() throws {
        let store = try makeStore()

        // A crashed drive: two points ~111 m apart, never ended.
        let crashed = store.beginTrip(at: .init(timeIntervalSinceReferenceDate: 0))
        store.recordPoint(from: drivingContext(lat: 37.0, lon: -122.0, speed: 10, at: 1), in: crashed)
        store.recordPoint(from: drivingContext(lat: 37.001, lon: -122.0, speed: 22, at: 11), in: crashed)

        // A crashed non-drive: one point only.
        let empty = store.beginTrip(at: .init(timeIntervalSinceReferenceDate: 100))
        store.recordPoint(from: drivingContext(lat: 37.0, lon: -122.0, at: 101), in: empty)

        store.closeDanglingTrips()

        let trips = try allTrips(store)
        let recovered = try #require(trips.first)
        #expect(trips.count == 1)
        #expect(recovered.endDate == Date(timeIntervalSinceReferenceDate: 11))
        #expect(recovered.distance > 100 && recovered.distance < 125)
        #expect(recovered.maxSpeed == 22)
    }

    @Test func deletingTripCascadesToPoints() throws {
        let store = try makeStore()
        let trip = store.beginTrip(at: .init(timeIntervalSinceReferenceDate: 0))
        store.recordPoint(from: drivingContext(lat: 37.0, lon: -122.0, at: 1), in: trip)
        store.recordPoint(from: drivingContext(lat: 37.001, lon: -122.0, at: 2), in: trip)
        try store.container.mainContext.save()

        store.container.mainContext.delete(trip)
        try store.container.mainContext.save()

        let points = try store.container.mainContext.fetch(FetchDescriptor<TripPoint>())
        #expect(points.isEmpty)
    }
}
