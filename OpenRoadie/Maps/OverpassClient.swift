import Foundation

/// One OpenStreetMap way (a road segment chain) as returned by Overpass.
struct OverpassWay: Equatable, Sendable {
    var tags: [String: String]
    var geometry: [Coordinate]
}

/// Minimal client for the public Overpass API — the free, open query service
/// over OpenStreetMap data. No API key required.
///
/// Privacy: a query necessarily sends the requested coordinate to the
/// Overpass server. `RoadService` throttles queries and the feature can be
/// turned off entirely in Settings.
struct OverpassClient: Sendable {
    var endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    /// Drivable-road highway classes; excludes footways, cycleways, etc.
    private static let drivableClasses = "motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link"

    /// Fetches all drivable roads within `radius` meters of a coordinate,
    /// with their geometry and tags (name, ref, maxspeed, ...).
    func roads(near coordinate: Coordinate, radius: Double) async throws -> [OverpassWay] {
        let query = """
        [out:json][timeout:8];
        way(around:\(Int(radius)),\(coordinate.latitude),\(coordinate.longitude))["highway"~"^(\(Self.drivableClasses))$"];
        out tags geom;
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query)".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try Self.parse(data)
    }

    /// Split out for testability against fixture JSON.
    static func parse(_ data: Data) throws -> [OverpassWay] {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.elements.compactMap { element in
            guard element.type == "way", let geometry = element.geometry, geometry.count >= 2 else { return nil }
            return OverpassWay(
                tags: element.tags ?? [:],
                geometry: geometry.map { Coordinate(latitude: $0.lat, longitude: $0.lon) }
            )
        }
    }

    private struct Response: Decodable {
        var elements: [Element]
        struct Element: Decodable {
            var type: String
            var tags: [String: String]?
            var geometry: [Point]?
            struct Point: Decodable {
                var lat: Double
                var lon: Double
            }
        }
    }
}
