import Foundation

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
