import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct DriveNoteTests {
    private func makeStore() throws -> TripStore {
        try TripStore.inMemory()
    }

    @Test func savesAndRecallsNewestFirst() throws {
        let store = try makeStore()
        store.saveNote("old idea", at: nil, timestamp: Date(timeIntervalSinceReferenceDate: 0))
        store.saveNote("new idea", at: Coordinate(latitude: 37, longitude: -122),
                       timestamp: Date(timeIntervalSinceReferenceDate: 100))

        let recent = store.recentNotes(limit: 5)
        #expect(recent.map(\.text) == ["new idea", "old idea"])
        #expect(recent[0].coordinate == Coordinate(latitude: 37, longitude: -122))
        #expect(recent[1].coordinate == nil)
    }

    @Test func nearbyNotesFilterByDistance() throws {
        let store = try makeStore()
        let here = Coordinate(latitude: 37.0, longitude: -122.0)
        store.saveNote("close by", at: Coordinate(latitude: 37.001, longitude: -122.0))   // ~111 m
        store.saveNote("across town", at: Coordinate(latitude: 37.1, longitude: -122.0))  // ~11 km
        store.saveNote("no location", at: nil)

        let near = store.notes(near: here, radiusMeters: 1_000)
        #expect(near.map(\.text) == ["close by"])
    }

    @Test func describeNotesIncludesDistanceWhenAnchored() throws {
        let store = try makeStore()
        let origin = Coordinate(latitude: 37.0, longitude: -122.0)
        store.saveNote("cool mural here", at: Coordinate(latitude: 37.001, longitude: -122.0),
                       timestamp: Date(timeIntervalSinceReferenceDate: 0))

        let text = RoadieToolFormatting.describeNotes(store.recentNotes(limit: 5), origin: origin)
        #expect(text.contains("cool mural here"))
        #expect(text.contains("ft") || text.contains("mi"))
        #expect(text.contains("N")) // due north of origin
    }

    @Test func emptyNotesAreHonest() {
        #expect(RoadieToolFormatting.describeNotes([], origin: nil) == "No saved notes.")
    }
}
