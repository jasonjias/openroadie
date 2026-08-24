import Foundation
import SwiftData

/// A completed (or in-progress) drive, persisted locally with SwiftData.
/// Driving history never leaves the device.
@Model
final class Trip {
    var startDate: Date
    /// `nil` while the drive is still recording (or if the app died mid-drive;
    /// see `TripStore.closeDanglingTrips`).
    var endDate: Date?
    /// Meters, as accumulated by `TripTracker`.
    var distance: Double
    /// Meters per second.
    var maxSpeed: Double?

    @Relationship(deleteRule: .cascade, inverse: \TripPoint.trip)
    var points: [TripPoint]

    init(startDate: Date) {
        self.startDate = startDate
        self.endDate = nil
        self.distance = 0
        self.maxSpeed = nil
        self.points = []
    }

    var duration: TimeInterval? {
        guard let endDate else { return nil }
        return endDate.timeIntervalSince(startDate)
    }

    /// Meters per second, from stored distance and duration.
    var averageSpeed: Double? {
        guard let duration, duration > 0 else { return nil }
        return distance / duration
    }

    /// SwiftData relationships are unordered; the route is points by time.
    var route: [TripPoint] {
        points.sorted { $0.timestamp < $1.timestamp }
    }
}

/// One recorded position along a trip's route — appended whenever the
/// tracker's position meaningfully advances (roughly every 10 m or more).
@Model
final class TripPoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Meters per second; `nil` when GPS didn't know.
    var speed: Double?
    /// Meters above sea level; `nil` when GPS didn't know.
    var altitude: Double?
    var trip: Trip?

    init(timestamp: Date, latitude: Double, longitude: Double, speed: Double?, altitude: Double?) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.altitude = altitude
    }
}

/// All writes to trip history go through here. Reads in SwiftUI use `@Query`.
@MainActor
final class TripStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    static func persistent() throws -> TripStore {
        TripStore(container: try ModelContainer(for: Trip.self, TripPoint.self))
    }

    static func inMemory() throws -> TripStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return TripStore(container: try ModelContainer(for: Trip.self, TripPoint.self, configurations: config))
    }

    func beginTrip(at date: Date = .now) -> Trip {
        let trip = Trip(startDate: date)
        context.insert(trip)
        return trip
    }

    /// Records the context's current position as a route point.
    /// No-op if the context has no fix yet.
    func recordPoint(from drivingContext: DrivingContext, in trip: Trip) {
        guard let coordinate = drivingContext.coordinate,
              let timestamp = drivingContext.timestamp else { return }
        let point = TripPoint(
            timestamp: timestamp,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            speed: drivingContext.speed,
            altitude: drivingContext.altitude
        )
        point.trip = trip
        context.insert(point)
    }

    /// Finalizes a trip. Trips with fewer than two points carry no route worth
    /// keeping (a Start/Stop tap in a parking spot) and are discarded.
    func endTrip(_ trip: Trip, at date: Date, distance: Double, maxSpeed: Double?) {
        if trip.points.count < 2 {
            context.delete(trip)
            return
        }
        trip.endDate = date
        trip.distance = distance
        trip.maxSpeed = maxSpeed
        try? context.save()
    }

    /// Recovers from an app death mid-drive: any trip still open from a prior
    /// launch is closed at its last recorded point (with distance rebuilt from
    /// the route), or discarded if it never really went anywhere.
    func closeDanglingTrips() {
        let openTrips = (try? context.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.endDate == nil })
        )) ?? []

        for trip in openTrips {
            let route = trip.route
            guard route.count >= 2, let last = route.last else {
                context.delete(trip)
                continue
            }
            trip.endDate = last.timestamp
            trip.distance = zip(route, route.dropFirst()).reduce(0) { total, pair in
                total + TripTracker.distance(
                    from: Coordinate(latitude: pair.0.latitude, longitude: pair.0.longitude),
                    to: Coordinate(latitude: pair.1.latitude, longitude: pair.1.longitude)
                )
            }
            trip.maxSpeed = route.compactMap(\.speed).max()
        }
        try? context.save()
    }
}
