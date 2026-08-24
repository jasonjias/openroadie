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
}
