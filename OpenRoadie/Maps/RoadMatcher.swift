import Foundation
import simd

/// Pure geometry and tag-parsing logic for turning Overpass ways into
/// "the road I'm on right now". No networking, no state — fully unit-testable.
enum RoadMatcher {
    /// A GPS position farther than this from the nearest road is considered
    /// off-road (parking lot, driveway) and matches nothing.
    static let maxMatchDistance: Double = 30

    /// How far a perpendicular road is effectively pushed away. An overpass
    /// crossing the freeway at 90° passes within a couple of meters in 2D,
    /// so pure-distance matching hands you the bridge's 45 limit while
    /// you're doing 65 on the freeway beneath it (field-reported). Heading
    /// disagreement costs up to this many meters, which is more than the
    /// width of any road pair, so the road you're POINTED ALONG wins.
    static let headingPenaltyMeters: Double = 90

    /// Once matched, a way keeps a small advantage so fixes don't flap
    /// between parallel candidates at intersections.
    static let stickinessMeters: Double = 12

    /// GPS course is noise below walking pace; heading is only trusted
    /// above this (m/s ≈ 7 mph).
    static let minimumCourseSpeed: Double = 3

    struct Match {
        var way: OverpassWay
        var distance: Double
        var cost: Double
    }

    /// Finds the way nearest to a coordinate, with its distance in meters.
    static func nearestWay(to coordinate: Coordinate, in ways: [OverpassWay]) -> (way: OverpassWay, distance: Double)? {
        var best: (way: OverpassWay, distance: Double)?
        for way in ways {
            let distance = self.distance(from: coordinate, toPolyline: way.geometry)
            if let current = best, current.distance <= distance { continue }
            best = (way, distance)
        }
        return best
    }

    /// The best-matching way: lateral distance plus a heading-disagreement
    /// penalty, minus a small bonus for the previously matched way. This is
    /// what keeps overpasses, cross streets, and on-ramps from stealing the
    /// match from the road actually under the wheels.
    static func bestMatch(
        at coordinate: Coordinate,
        courseDegrees: Double? = nil,
        speedMps: Double? = nil,
        in ways: [OverpassWay],
        preferring previousWayId: Int64? = nil
    ) -> Match? {
        // Course is only meaningful while genuinely moving.
        let trustedCourse: Double? = {
            guard let courseDegrees, courseDegrees >= 0 else { return nil }
            guard let speedMps, speedMps >= minimumCourseSpeed else { return nil }
            return courseDegrees
        }()

        var best: Match?
        for way in ways {
            let distance = self.distance(from: coordinate, toPolyline: way.geometry)
            var cost = distance
            if let trustedCourse, let bearing = bearing(of: way, nearest: coordinate) {
                cost += headingPenaltyMeters * (headingDelta(courseDegrees: trustedCourse, bearing: bearing) / 90)
            }
            if let previousWayId, way.id == previousWayId, way.id != 0 {
                cost -= stickinessMeters
            }
            if let current = best, current.cost <= cost { continue }
            best = Match(way: way, distance: distance, cost: cost)
        }
        return best
    }

    /// The road the coordinate is on, or `nil` when off known roads.
    /// Passing course and speed enables heading-aware matching.
    static func road(
        at coordinate: Coordinate,
        courseDegrees: Double? = nil,
        speedMps: Double? = nil,
        from ways: [OverpassWay],
        preferring previousWayId: Int64? = nil
    ) -> RoadInfo? {
        guard let match = bestMatch(
            at: coordinate, courseDegrees: courseDegrees, speedMps: speedMps,
            in: ways, preferring: previousWayId
        ), match.distance <= maxMatchDistance else { return nil }
        let tags = match.way.tags
        return RoadInfo(
            name: tags["name"],
            ref: tags["ref"],
            speedLimit: tags["maxspeed"].flatMap(speedLimit(fromMaxspeedTag:))
        )
    }

    /// Compass bearing (degrees, 0 = north) of the way's segment nearest
    /// the coordinate — the direction the road runs there.
    static func bearing(of way: OverpassWay, nearest coordinate: Coordinate) -> Double? {
        guard way.geometry.count >= 2 else { return nil }
        var bestIndex = 0
        var bestDistance = Double.infinity
        for index in 0..<(way.geometry.count - 1) {
            let distance = self.distance(from: coordinate, toSegment: (way.geometry[index], way.geometry[index + 1]))
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        let a = way.geometry[bestIndex]
        let b = way.geometry[bestIndex + 1]
        let east = (b.longitude - a.longitude) * cos(a.latitude * .pi / 180)
        let north = b.latitude - a.latitude
        guard east != 0 || north != 0 else { return nil }
        return atan2(east, north) * 180 / .pi
    }

    /// Angle between travel and a road, folded to 0…90: a road is a line,
    /// not an arrow, so driving it "backwards" still agrees with it.
    static func headingDelta(courseDegrees: Double, bearing: Double) -> Double {
        var delta = abs(courseDegrees - bearing).truncatingRemainder(dividingBy: 180)
        if delta > 90 { delta = 180 - delta }
        return delta
    }

    /// Parses OSM `maxspeed` values into meters per second.
    ///
    /// OSM conventions: a bare number is km/h; "25 mph" and "10 knots" carry
    /// units; "none", "signals", "variable", etc. mean no fixed numeric limit.
    static func speedLimit(fromMaxspeedTag tag: String) -> Double? {
        // Composite values like "50; 30" — use the first component.
        let first = tag.split(separator: ";").first.map(String.init) ?? tag
        let value = first.lowercased().trimmingCharacters(in: .whitespaces)

        let number = value.split(separator: " ").first.flatMap { Double($0) }
        guard let number, number > 0 else { return nil }

        if value.contains("mph") { return number * 0.44704 }
        if value.contains("knots") { return number * 0.514444 }
        return number / 3.6 // km/h
    }

    /// Samples the road's centerline in the VEHICLE's frame: lateral
    /// offset in meters (+ = right of travel) at fixed arc-length steps,
    /// from `behindMeters` behind the car to `aheadMeters` ahead. This is
    /// what bends the 3D drive scene's road to match the real one.
    ///
    /// The way's node order is arbitrary — the walk direction is chosen
    /// by whichever best agrees with the GPS course. Past either end of
    /// the way the road continues straight along its final heading.
    static func upcomingCurve(
        at coordinate: Coordinate,
        courseDegrees: Double,
        along way: OverpassWay,
        stepMeters: Double = 4,
        behindMeters: Double = 8,
        aheadMeters: Double = 68
    ) -> [Double] {
        let sampleCount = Int(((behindMeters + aheadMeters) / stepMeters).rounded()) + 1
        let straight = [Double](repeating: 0, count: sampleCount)
        guard way.geometry.count >= 2 else { return straight }

        // Local flat-earth frame centered on the car: x = east, y = north.
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(coordinate.latitude * .pi / 180)
        var points = way.geometry.map { node in
            SIMD2(
                (node.longitude - coordinate.longitude) * metersPerDegreeLon,
                (node.latitude - coordinate.latitude) * metersPerDegreeLat
            )
        }

        // Vehicle frame axes from the GPS course (0° = north, clockwise).
        let theta = courseDegrees * .pi / 180
        let forward = SIMD2(sin(theta), cos(theta))
        let right = SIMD2(cos(theta), -sin(theta))

        // Nearest point on the polyline = the car's on-road anchor.
        var bestSegment = 0
        var bestT = 0.0
        var bestDistance = Double.infinity
        for index in 0..<(points.count - 1) {
            let a = points[index], b = points[index + 1]
            let d = b - a
            let lengthSquared = simd_length_squared(d)
            let t = lengthSquared > 0 ? max(0, min(1, -simd_dot(a, d) / lengthSquared)) : 0
            let p = a + t * d
            let distance = simd_length(p)
            if distance < bestDistance {
                bestDistance = distance
                bestSegment = index
                bestT = t
            }
        }

        // Walk with, not against, traffic: if the way's node order opposes
        // the course, flip it.
        let segmentDirection = points[bestSegment + 1] - points[bestSegment]
        if simd_dot(segmentDirection, forward) < 0 {
            points.reverse()
            bestSegment = points.count - 2 - bestSegment
            bestT = 1 - bestT
        }

        let anchor = points[bestSegment] + bestT * (points[bestSegment + 1] - points[bestSegment])

        // Positions along the way by signed arc length from the anchor.
        func position(atArcLength s: Double) -> SIMD2<Double> {
            if s >= 0 {
                var remaining = s
                var index = bestSegment
                var from = anchor
                while index < points.count - 1 {
                    let to = points[index + 1]
                    let length = simd_length(to - from)
                    if remaining <= length || length == 0 {
                        return length == 0 ? from : from + (remaining / length) * (to - from)
                    }
                    remaining -= length
                    from = to
                    index += 1
                }
                // Past the way's end: continue straight.
                let a = points[points.count - 2], b = points[points.count - 1]
                let d = b - a
                let length = simd_length(d)
                return length == 0 ? from : from + (remaining / length) * d
            } else {
                var remaining = -s
                var index = bestSegment
                var from = anchor
                while index >= 0 {
                    let to = points[index]
                    let length = simd_length(to - from)
                    if remaining <= length || length == 0 {
                        return length == 0 ? from : from + (remaining / length) * (to - from)
                    }
                    remaining -= length
                    from = to
                    index -= 1
                }
                let a = points[1], b = points[0]
                let d = b - a
                let length = simd_length(d)
                return length == 0 ? from : from + (remaining / length) * d
            }
        }

        return (0..<sampleCount).map { index in
            let s = -behindMeters + Double(index) * stepMeters
            return simd_dot(position(atArcLength: s) - anchor, right)
        }
    }

    /// Minimum distance in meters from a point to a polyline.
    static func distance(from point: Coordinate, toPolyline polyline: [Coordinate]) -> Double {
        guard polyline.count >= 2 else { return .infinity }
        var minimum = Double.infinity
        for index in 0..<(polyline.count - 1) {
            minimum = min(minimum, distance(from: point, toSegment: (polyline[index], polyline[index + 1])))
        }
        return minimum
    }

    /// Distance from a point to a segment using a local flat-earth projection —
    /// accurate to well under a meter at road-matching scales.
    static func distance(from point: Coordinate, toSegment segment: (Coordinate, Coordinate)) -> Double {
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(point.latitude * .pi / 180)

        let ax = (segment.0.longitude - point.longitude) * metersPerDegreeLon
        let ay = (segment.0.latitude - point.latitude) * metersPerDegreeLat
        let bx = (segment.1.longitude - point.longitude) * metersPerDegreeLon
        let by = (segment.1.latitude - point.latitude) * metersPerDegreeLat

        let dx = bx - ax
        let dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (ax * ax + ay * ay).squareRoot() }

        // Project the point onto the segment, clamped to its endpoints.
        let t = max(0, min(1, -(ax * dx + ay * dy) / lengthSquared))
        let px = ax + t * dx
        let py = ay + t * dy
        return (px * px + py * py).squareRoot()
    }
}
