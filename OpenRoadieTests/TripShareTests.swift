import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct TripShareTests {
    private func point(_ latitude: Double, _ longitude: Double) -> TripPoint {
        TripPoint(timestamp: .now, latitude: latitude, longitude: longitude, speed: 10, altitude: nil)
    }

    @Test func projectionFitsInsideTheCanvas() {
        let route = [point(37.40, -122.15), point(37.45, -122.10), point(37.42, -122.05)]
        let size = CGSize(width: 300, height: 200)
        let projected = RoutePathCanvas.project(route, into: size)
        #expect(projected.count == 3)
        for p in projected {
            #expect(p.x >= 0 && p.x <= size.width)
            #expect(p.y >= 0 && p.y <= size.height)
        }
    }

    @Test func northIsUp() {
        // Second point is further north — it must land higher (smaller y).
        let route = [point(37.40, -122.10), point(37.45, -122.10)]
        let projected = RoutePathCanvas.project(route, into: CGSize(width: 100, height: 100))
        #expect(projected[1].y < projected[0].y)
    }

    @Test func aspectFitIsCentered() {
        // A wide east-west route in a square canvas centers vertically.
        let route = [point(37.40, -122.20), point(37.40, -122.00)]
        let projected = RoutePathCanvas.project(route, into: CGSize(width: 100, height: 100))
        #expect(abs(projected[0].y - 50) < 1)
        #expect(abs(projected[1].y - 50) < 1)
    }

    @Test func emptyAndSinglePointRoutesDoNotCrash() {
        #expect(RoutePathCanvas.project([], into: CGSize(width: 100, height: 100)).isEmpty)
        let one = RoutePathCanvas.project([point(37.4, -122.1)], into: CGSize(width: 100, height: 100))
        #expect(one.count == 1)
    }
}
