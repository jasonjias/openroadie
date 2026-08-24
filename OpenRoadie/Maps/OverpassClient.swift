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
    /// Public Overpass instances, tried in order — the free servers are
    /// load-limited, so a busy primary fails over to the next.
    var endpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.kumi.systems/api/interpreter")!,
    ]

    /// OSM etiquette: identify the app and where to reach its maintainers.
    static let userAgent = "OpenRoadie/0.1 (+https://github.com/jasonjias/openroadie)"

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

        return try Self.parse(await post(query))
    }

    /// Fetches points of interest of one category around a coordinate.
    /// Uses `out center` so area-mapped places (a way for a building) come
    /// back as a single representative point.
    func places(near coordinate: Coordinate, radius: Double, category: PlaceCategory) async throws -> [Place] {
        let around = "around:\(Int(radius)),\(coordinate.latitude),\(coordinate.longitude)"
        let query = """
        [out:json][timeout:8];
        (
          node(\(around))\(category.overpassFilter);
          way(\(around))\(category.overpassFilter);
        );
        out center tags;
        """

        return try Self.parsePlaces(await post(query), category: category)
    }

    /// POSTs a query, failing over across public instances when one is busy.
    private func post(_ query: String) async throws -> Data {
        var lastError: Error = URLError(.badServerResponse)
        for endpoint in endpoints {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query)".data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    lastError = URLError(.badServerResponse)
                    continue
                }
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
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

    /// Split out for testability against fixture JSON.
    static func parsePlaces(_ data: Data, category: PlaceCategory) throws -> [Place] {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.elements.compactMap { element in
            // Nodes carry lat/lon directly; ways carry a computed center.
            let latitude = element.lat ?? element.center?.lat
            let longitude = element.lon ?? element.center?.lon
            guard let latitude, let longitude else { return nil }
            let tags = element.tags ?? [:]
            return Place(
                id: "\(element.type)/\(element.id)",
                name: tags["name"],
                brand: tags["brand"],
                operatedBy: tags["operator"],
                category: category,
                coordinate: Coordinate(latitude: latitude, longitude: longitude)
            )
        }
    }

    private struct Response: Decodable {
        var elements: [Element]
        struct Element: Decodable {
            var type: String
            var id: Int64
            var lat: Double?
            var lon: Double?
            var center: Point?
            var tags: [String: String]?
            var geometry: [Point]?
            struct Point: Decodable {
                var lat: Double
                var lon: Double
            }
        }
    }
}
