import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct HazardServiceTests {
    private func service() -> HazardService {
        let s = HazardService()
        s.load(hazards: [
            .init(latitude: 37.4419, longitude: -122.1430, crashes: 3),
            .init(latitude: 37.5000, longitude: -122.2000, crashes: 2),
        ])
        s.startDrive()
        return s
    }

    @Test func nearbyHazardFiresOnce() {
        let s = service()
        let near = Coordinate(latitude: 37.4418, longitude: -122.1431) // ~15m away
        let hit = s.check(near)
        #expect(hit?.crashes == 3)
        // Same zone again this drive: silent.
        #expect(s.check(near) == nil)
    }

    @Test func farAwayIsSilent() {
        let s = service()
        #expect(s.check(Coordinate(latitude: 37.46, longitude: -122.16)) == nil)
    }

    @Test func newDriveReArmsZones() {
        let s = service()
        let near = Coordinate(latitude: 37.4419, longitude: -122.1430)
        #expect(s.check(near) != nil)
        s.startDrive()
        #expect(s.check(near) != nil)
    }

    @Test func bucketBoundaryStillFound() {
        // Hazard just across a 0.01° bucket edge from the query point.
        let s = HazardService()
        s.load(hazards: [.init(latitude: 37.44001, longitude: -122.15001, crashes: 2)])
        s.startDrive()
        #expect(s.check(Coordinate(latitude: 37.43999, longitude: -122.14999)) != nil)
    }
}
