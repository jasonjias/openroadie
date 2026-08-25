import Foundation
import MapKit

/// A free-text search hit — anything MKLocalSearch can find.
struct FoundPlace: Identifiable, Equatable {
    var id: String
    var name: String
    var address: String?
    var coordinate: Coordinate
}

/// Free-text place search ("pharmacy", "boba", "car wash") via Apple's
/// MKLocalSearch — the quality backstop for everything outside the fixed
/// OSM categories. Display data only; the query result never persists.
@MainActor
enum PlaceSearch {
    /// Session cache: same query near the same spot (~2 km grid) reuses the
    /// answer for a day — Chipotles don't move between searches.
    private struct CacheKey: Hashable {
        let query: String
        let cellLat: Int
        let cellLon: Int

        init(query: String, origin: Coordinate) {
            self.query = query.lowercased()
            cellLat = Int((origin.latitude / 0.02).rounded())
            cellLon = Int((origin.longitude / 0.02).rounded())
        }
    }

    private static var cache: [CacheKey: (fetchedAt: Date, places: [FoundPlace])] = [:]
    private static let timeToLive: TimeInterval = 24 * 3600

    static func search(_ query: String, near origin: Coordinate, radiusMeters: Double = 10_000) async throws -> [FoundPlace] {
        let key = CacheKey(query: query, origin: origin)
        if let hit = cache[key], Date.now.timeIntervalSince(hit.fetchedAt) < timeToLive {
            return hit.places
        }
        let places = try await fetch(query, near: origin, radiusMeters: radiusMeters)
        cache[key] = (.now, places)
        return places
    }

    private static func fetch(_ query: String, near origin: Coordinate, radiusMeters: Double) async throws -> [FoundPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude),
            latitudinalMeters: radiusMeters * 2,
            longitudinalMeters: radiusMeters * 2
        )
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            let coordinate = item.placemark.coordinate
            return FoundPlace(
                id: "\(item.name ?? "?")@\(coordinate.latitude),\(coordinate.longitude)",
                name: item.name ?? "Unnamed place",
                address: item.placemark.title,
                coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
        }
    }

    /// Nearest-first with straight-line distances, for display and the agent.
    static func sortedByDistance(_ places: [FoundPlace], from origin: Coordinate) -> [(place: FoundPlace, distance: Double)] {
        places
            .map { ($0, TripTracker.distance(from: origin, to: $0.coordinate)) }
            .sorted { $0.1 < $1.1 }
    }
}
