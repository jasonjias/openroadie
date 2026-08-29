import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct PersonalExportTests {
    private func drive() -> Trip {
        let start = Date(timeIntervalSince1970: 1_724_500_000)
        let trip = Trip(startDate: start)
        trip.endDate = start.addingTimeInterval(600)
        trip.distance = 8046.72 // 5 mi
        trip.maxSpeed = 29
        trip.points = [
            TripPoint(timestamp: start, latitude: 37.4, longitude: -122.1, speed: 10, altitude: 30, speedLimit: 15.6),
            TripPoint(timestamp: start.addingTimeInterval(60), latitude: 37.41, longitude: -122.11, speed: 20, altitude: 32, speedLimit: 15.6),
        ]
        return trip
    }

    @Test func payloadCarriesEverythingAtFullFidelity() {
        let trip = drive()
        let events = [DriveEvent(kind: "hardBraking", peakG: 0.42, coordinate: Coordinate(latitude: 37.4, longitude: -122.1), speedMph: 41, timestamp: trip.startDate)]
        let notes = [DriveNote(text: "gas next time", coordinate: nil, timestamp: trip.startDate)]

        let payload = PersonalExport.payload(trips: [trip], events: events, notes: notes)
        #expect(payload.trips.count == 1)
        #expect(payload.trips[0].route.count == 2)
        // Full fidelity: exact coordinates, speeds, and limits survive.
        #expect(payload.trips[0].route[1].latitude == 37.41)
        #expect(payload.trips[0].route[0].speedLimitMps == 15.6)
        #expect(payload.events[0].peakG == 0.42)
        #expect(payload.notes[0].text == "gas next time")
    }

    @Test func jsonRoundTrips() throws {
        let data = try PersonalExport.json(trips: [drive()], events: [], notes: [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PersonalExport.Payload.self, from: data)
        #expect(decoded.format == "openroadie.personal.v1")
        #expect(decoded.trips.count == 1)
        #expect(decoded.trips[0].route.count == 2)
    }

    @Test func gpxHasATrackSegmentPerDrive() {
        let gpx = PersonalExport.gpx(trips: [drive()])
        #expect(gpx.hasPrefix("<?xml"))
        #expect(gpx.contains("<trkseg>"))
        #expect(gpx.contains("lat=\"37.41\""))
        #expect(gpx.contains("</gpx>"))
        // Two points recorded, two trkpt elements written.
        #expect(gpx.components(separatedBy: "<trkpt").count - 1 == 2)
    }

    @Test func emptyHistoryStillProducesValidFiles() throws {
        let data = try PersonalExport.json(trips: [], events: [], notes: [])
        #expect(!data.isEmpty)
        #expect(PersonalExport.gpx(trips: []).contains("</gpx>"))
    }
}
