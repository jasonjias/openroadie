import Foundation
import simd

/// Pure geometry and tag-parsing logic for turning Overpass ways into
/// "the road I'm on right now". No networking, no state — fully unit-testable.
enum RoadMatcher {
    /// A GPS position farther than this from the nearest road is considered
    /// off-road (parking lot, driveway) and matches nothing.
    static let maxMatchDistance: Double = 30

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

    /// The road the coordinate is on, or `nil` when off known roads.
    static func road(at coordinate: Coordinate, from ways: [OverpassWay]) -> RoadInfo? {
        guard let match = nearestWay(to: coordinate, in: ways),
              match.distance <= maxMatchDistance else { return nil }
        let tags = match.way.tags
        return RoadInfo(
            name: tags["name"],
            ref: tags["ref"],
            speedLimit: tags["maxspeed"].flatMap(speedLimit(fromMaxspeedTag:))
        )
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
