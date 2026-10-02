import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct HazardServiceTests {
    private func service() -> HazardService {
        let s = HazardService()
        s.load(hazards: [
            .init(latitude: 37.7694, longitude: -122.4862, crashes: 3),
            .init(latitude: 37.8000, longitude: -122.5000, crashes: 2),
        ])
        s.startDrive()
        return s
    }

    @Test func nearbyHazardFiresOnce() {
        let s = service()
        let near = Coordinate(latitude: 37.76931, longitude: -122.48631) // ~15m away
        let hit = s.check(near)
        #expect(hit?.crashes == 3)
        // Same zone again this drive: silent.
        #expect(s.check(near) == nil)
    }

    @Test func farAwayIsSilent() {
        let s = service()
        #expect(s.check(Coordinate(latitude: 37.78, longitude: -122.50)) == nil)
    }

    @Test func newDriveReArmsZones() {
        let s = service()
        let near = Coordinate(latitude: 37.7694, longitude: -122.4862)
        #expect(s.check(near) != nil)
        s.startDrive()
        #expect(s.check(near) != nil)
    }

    @Test func bucketBoundaryStillFound() {
        // Hazard just across a 0.01° bucket edge from the query point.
        let s = HazardService()
        s.load(hazards: [.init(latitude: 37.76001, longitude: -122.50001, crashes: 2)])
        s.startDrive()
        #expect(s.check(Coordinate(latitude: 37.75999, longitude: -122.49999)) != nil)
    }
}
