import Foundation
import Testing
@testable import OpenRoadie

struct RoadMatcherTests {
    // A west–east street at latitude 37.0001 and a south–north street at
    // longitude -122.0001, crossing near the test point.
    private let eastWest = OverpassWay(
        tags: ["highway": "residential", "name": "Emerson St", "maxspeed": "25 mph"],
        geometry: [Coordinate(latitude: 37.0001, longitude: -122.001),
                   Coordinate(latitude: 37.0001, longitude: -121.999)]
    )
    private let southNorth = OverpassWay(
        tags: ["highway": "primary", "name": "El Camino Real", "ref": "CA 82", "maxspeed": "35 mph"],
        geometry: [Coordinate(latitude: 36.999, longitude: -122.0001),
                   Coordinate(latitude: 37.001, longitude: -122.0001)]
    )

    @Test func matchesNearestRoad() {
        // ~11 m north of the east–west street, ~90 m east of the other.
        let point = Coordinate(latitude: 37.0002, longitude: -122.0011)
        let road = RoadMatcher.road(at: point, from: [southNorth, eastWest])
        #expect(road?.name == "Emerson St")
        #expect(road?.speedLimit != nil)
    }

    @Test func offRoadMatchesNothing() {
        // ~550 m from everything.
        let point = Coordinate(latitude: 37.005, longitude: -122.005)
        #expect(RoadMatcher.road(at: point, from: [southNorth, eastWest]) == nil)
    }

    @Test func refFillsInWhenNameMissing() {
        var unnamed = southNorth
        unnamed.tags.removeValue(forKey: "name")
        let point = Coordinate(latitude: 37.0005, longitude: -122.0001)
        let road = RoadMatcher.road(at: point, from: [unnamed])
        #expect(road?.name == nil)
        #expect(road?.displayName == "CA 82")
    }

    @Test func parsesMaxspeedVariants() {
        // OSM bare numbers are km/h.
        #expect(RoadMatcher.speedLimit(fromMaxspeedTag: "50") == 50 / 3.6)
        // US-style mph.
        let mph25 = try! #require(RoadMatcher.speedLimit(fromMaxspeedTag: "25 mph"))
        #expect(abs(mph25 - 11.176) < 0.01)
        // Composite: first value wins.
        let composite = try! #require(RoadMatcher.speedLimit(fromMaxspeedTag: "40 mph; 30 mph"))
        #expect(abs(composite - 17.88) < 0.01)
        // Non-numeric conventions mean "no fixed limit".
        #expect(RoadMatcher.speedLimit(fromMaxspeedTag: "none") == nil)
        #expect(RoadMatcher.speedLimit(fromMaxspeedTag: "signals") == nil)
    }

    @Test func pointToSegmentDistanceIsSane() {
        // 0.0001° of latitude ≈ 11.13 m.
        let segment = (Coordinate(latitude: 37.0, longitude: -122.001),
                       Coordinate(latitude: 37.0, longitude: -121.999))
        let distance = RoadMatcher.distance(from: Coordinate(latitude: 37.0001, longitude: -122.0), toSegment: segment)
        #expect(abs(distance - 11.13) < 0.2)

        // Beyond the segment's end, distance is to the endpoint, not the line.
        let beyondEnd = RoadMatcher.distance(from: Coordinate(latitude: 37.0, longitude: -121.99), toSegment: segment)
        #expect(beyondEnd > 700)
    }

    @Test func parsesOverpassResponse() throws {
        let json = """
        {"elements":[
          {"type":"way","id":1,"tags":{"highway":"residential","name":"Kipling St","maxspeed":"25 mph"},
           "geometry":[{"lat":37.44,"lon":-122.14},{"lat":37.441,"lon":-122.141}]},
          {"type":"way","id":2,"geometry":[{"lat":37.0,"lon":-122.0}]},
          {"type":"node","id":3}
        ]}
        """
        let ways = try OverpassClient.parse(Data(json.utf8))
        // The single-point way and the node are dropped.
        #expect(ways.count == 1)
        #expect(ways[0].tags["name"] == "Kipling St")
        #expect(ways[0].geometry.count == 2)
    }
}

struct RouteColoringTests {
    @Test func groupsConsecutiveSpeedsIntoRuns() {
        // 10 m/s (green band), then 25 m/s (orange band).
        let runs = RouteColoring.runs(forSpeeds: [10, 10, 10, 25, 25])
        #expect(runs.count == 2)
        #expect(runs[0].pointIndices == 0...3)
        #expect(runs[1].pointIndices == 3...4)
        #expect(runs[0].bandIndex != runs[1].bandIndex)
    }

    @Test func unknownSpeedInheritsCurrentBand() {
        let runs = RouteColoring.runs(forSpeeds: [10, nil, 10, nil])
        #expect(runs.count == 1)
        #expect(runs[0].pointIndices == 0...3)
    }

    @Test func runsCoverEveryPointWithOverlap() {
        let speeds: [Double?] = [3, 3, 10, 10, 25, 3]
        let runs = RouteColoring.runs(forSpeeds: speeds)
        #expect(runs.first?.pointIndices.lowerBound == 0)
        #expect(runs.last?.pointIndices.upperBound == speeds.count - 1)
        for index in 1..<runs.count {
            // Continuous path: each run starts where the previous ended.
            #expect(runs[index].pointIndices.lowerBound == runs[index - 1].pointIndices.upperBound)
        }
    }

    @Test func tooFewPointsProduceNoRuns() {
        #expect(RouteColoring.runs(forSpeeds: [10]).isEmpty)
        #expect(RouteColoring.runs(forSpeeds: []).isEmpty)
    }

    @Test func extremeSpeedsLandInTopBands() {
        // 80 mph ≈ 35.8 m/s and 110 mph ≈ 49.2 m/s must hit the two top bands.
        let dark = try! #require(RouteColoring.bandIndex(forSpeed: 35.8))
        let extreme = try! #require(RouteColoring.bandIndex(forSpeed: 49.2))
        #expect(dark == RouteColoring.bands.count - 2)
        #expect(extreme == RouteColoring.bands.count - 1)
    }

    @Test func legendListsOnlyVisitedBands() {
        // A city drive: slow and medium speeds only.
        let runs = RouteColoring.runs(forSpeeds: [3, 3, 10, 10, 3])
        #expect(RouteColoring.presentBands(in: runs) == [0, 1])
    }
}

@MainActor
struct UpcomingCurveTests {
    /// A straight north–south road through the origin point.
    private let straightNorth = OverpassWay(
        tags: ["highway": "residential"],
        geometry: [Coordinate(latitude: 36.998, longitude: -122.0),
                   Coordinate(latitude: 37.002, longitude: -122.0)]
    )

    /// Northbound, then a 90° turn to the east ~40 m ahead of the origin.
    private let rightTurn = OverpassWay(
        tags: ["highway": "residential"],
        geometry: [Coordinate(latitude: 36.999, longitude: -122.0),
                   Coordinate(latitude: 37.00036, longitude: -122.0),   // ~40 m north
                   Coordinate(latitude: 37.00036, longitude: -121.998)] // then east
    )

    private let origin = Coordinate(latitude: 37.0, longitude: -122.0)

    @Test func straightRoadIsAllZeros() {
        let curve = RoadMatcher.upcomingCurve(at: origin, courseDegrees: 0, along: straightNorth)
        #expect(curve.count == 20)
        #expect(curve.allSatisfy { abs($0) < 0.1 })
    }

    @Test func rightTurnBendsRightAhead() {
        let curve = RoadMatcher.upcomingCurve(at: origin, courseDegrees: 0, along: rightTurn)
        // Behind and near samples straight; far samples bend right (+).
        #expect(abs(curve[2]) < 0.1)              // z = 0, under the car
        #expect(curve[11] < 0.5)                  // 36 m ahead, still before the corner
        #expect(curve.last! > 20)                 // deep into the east leg
    }

    @Test func travelingSouthMirrorsTheTurn() {
        // Approaching the same corner from the north, heading south, the
        // way's node order opposes travel — the walk must flip, and the
        // east leg is now behind, so ahead stays straight.
        let north = Coordinate(latitude: 37.0007, longitude: -122.0)
        let curve = RoadMatcher.upcomingCurve(at: north, courseDegrees: 180, along: rightTurn)
        #expect(abs(curve[2]) < 0.1)
        #expect(curve[19] < 0.1) // ahead extends straight past the way's south end
    }
}

/// The field-reported freeway bug: an overpass crossing above the freeway
/// passes within a couple of meters in 2D, so pure-distance matching served
/// the bridge's 45 limit while doing 65 on the freeway underneath — and the
/// coach scolded a driver going exactly the posted speed.
struct OverpassMatchingTests {
    /// US-101 running due north through the test point, 65 mph.
    private let freeway = OverpassWay(
        tags: ["highway": "motorway", "ref": "US 101", "maxspeed": "65 mph"],
        geometry: [Coordinate(latitude: 36.995, longitude: -122.0),
                   Coordinate(latitude: 37.005, longitude: -122.0)],
        id: 101
    )
    /// A surface street bridging over it east–west, 45 mph, crossing 3 m
    /// north of the driver — i.e. CLOSER than the freeway's centerline.
    private let overpass = OverpassWay(
        tags: ["highway": "secondary", "name": "Embarcadero Rd", "maxspeed": "45 mph"],
        geometry: [Coordinate(latitude: 37.000027, longitude: -122.002),
                   Coordinate(latitude: 37.000027, longitude: -121.998)],
        id: 202
    )
    /// Driver on the freeway, a few meters east of its centerline,
    /// northbound at 65 mph (29 m/s).
    private let onFreeway = Coordinate(latitude: 37.0, longitude: -121.99993)

    @Test func perpendicularOverpassLosesToTheRoadBeneathIt() {
        let ways = [freeway, overpass]
        // Pure distance picks the bridge — that's the bug.
        #expect(RoadMatcher.nearestWay(to: onFreeway, in: ways)?.way.id == overpass.id)

        // Heading-aware matching picks the freeway we're pointed along.
        let road = RoadMatcher.road(
            at: onFreeway, courseDegrees: 0, speedMps: 29, from: ways
        )
        #expect(road?.ref == "US 101")
        #expect(road.map { Int(($0.speedLimit ?? 0) * 2.236936 + 0.5) } == 65)
    }

    @Test func drivingTheBridgeStillMatchesTheBridge() {
        // Same spot, but now traveling east across the overpass.
        let road = RoadMatcher.road(
            at: onFreeway, courseDegrees: 90, speedMps: 20, from: [freeway, overpass]
        )
        #expect(road?.name == "Embarcadero Rd")
    }

    @Test func stationaryFixesFallBackToDistance() {
        // Course is noise when parked, so heading must not be trusted.
        let road = RoadMatcher.road(
            at: onFreeway, courseDegrees: 0, speedMps: 0, from: [freeway, overpass]
        )
        #expect(road?.name == "Embarcadero Rd") // nearest, as before
    }

    @Test func headingDeltaFoldsToNinety() {
        #expect(RoadMatcher.headingDelta(courseDegrees: 0, bearing: 0) == 0)
        #expect(RoadMatcher.headingDelta(courseDegrees: 0, bearing: 90) == 90)
        // Driving a road "backwards" still agrees with it.
        #expect(RoadMatcher.headingDelta(courseDegrees: 0, bearing: 180) == 0)
        #expect(RoadMatcher.headingDelta(courseDegrees: 350, bearing: 10) == 20)
    }

    @Test func stickinessKeepsTheMatchFromFlapping() {
        // Two parallel roads a hair apart: whichever was matched last wins.
        let a = OverpassWay(tags: ["highway": "residential", "name": "A"],
                            geometry: [Coordinate(latitude: 36.999, longitude: -122.0),
                                       Coordinate(latitude: 37.001, longitude: -122.0)], id: 1)
        let b = OverpassWay(tags: ["highway": "residential", "name": "B"],
                            geometry: [Coordinate(latitude: 36.999, longitude: -121.99995),
                                       Coordinate(latitude: 37.001, longitude: -121.99995)], id: 2)
        let point = Coordinate(latitude: 37.0, longitude: -121.999985)
        let sticky = RoadMatcher.road(at: point, courseDegrees: 0, speedMps: 20, from: [a, b], preferring: 1)
        #expect(sticky?.name == "A")
    }
}
