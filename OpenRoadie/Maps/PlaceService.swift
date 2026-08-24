import Foundation

/// The POI categories OpenRoadie knows how to find, each mapped to the
/// OpenStreetMap tags that define it.
enum PlaceCategory: String, CaseIterable, Identifiable, Sendable {
    case food
    case coffee
    case fuel
    case charger
    case landmark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: "Food"
        case .coffee: "Coffee"
        case .fuel: "Gas"
        case .charger: "Chargers"
        case .landmark: "Landmarks"
        }
    }

    var systemImage: String {
        switch self {
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer.fill"
        case .fuel: "fuelpump.fill"
        case .charger: "bolt.car.fill"
        case .landmark: "building.columns.fill"
        }
    }

    /// Overpass tag filter for this category.
    var overpassFilter: String {
        switch self {
        case .food: #"["amenity"~"^(restaurant|fast_food)$"]"#
        case .coffee: #"["amenity"="cafe"]"#
        case .fuel: #"["amenity"="fuel"]"#
        case .charger: #"["amenity"="charging_station"]"#
        case .landmark: #"["tourism"~"^(attraction|museum|viewpoint)$"]"#
        }
    }

    /// How far people realistically go for this category: you walk to coffee,
    /// you drive to a charger.
    var searchRadius: Double {
        switch self {
        case .food, .coffee: 3_000
        case .fuel, .landmark: 5_000
        case .charger: 8_000
        }
    }

    var singular: String {
        switch self {
        case .food: "restaurant"
        case .coffee: "cafe"
        case .fuel: "gas station"
        case .charger: "charger"
        case .landmark: "landmark"
        }
    }
}

/// One point of interest near the drive.
struct Place: Identifiable, Equatable, Sendable {
    /// OSM element id, e.g. "node/123456".
    var id: String
    var name: String?
    var brand: String?
    var operatedBy: String?
    /// Street address from OSM addr:* tags, when mapped.
    var address: String?
    var category: PlaceCategory
    var coordinate: Coordinate

    /// Best label available — many mapped places (charger boxes especially)
    /// carry only a brand or operator tag, not a name.
    var displayName: String {
        name ?? brand ?? operatedBy ?? "Unnamed \(category.singular)"
    }

    /// True when the place's name, brand, or operator mentions the keyword —
    /// how "tesla" finds a Supercharger whatever tag it lives in.
    func matches(keyword: String) -> Bool {
        [name, brand, operatedBy].compactMap { $0 }.contains {
            $0.localizedCaseInsensitiveContains(keyword)
        }
    }
}

/// Geometry helpers for presenting places relative to the driver.
enum PlaceGeometry {
    /// Initial bearing in degrees from true north, `from` → `to`.
    static func bearing(from: Coordinate, to: Coordinate) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Places sorted nearest-first with their straight-line distance (meters).
    static func sortedByDistance(_ places: [Place], from origin: Coordinate) -> [(place: Place, distance: Double)] {
        places
            .map { ($0, TripTracker.distance(from: origin, to: $0.coordinate)) }
            .sorted { $0.1 < $1.1 }
    }
}

/// Fetches nearby places with a small per-category cache, so flipping
/// between category tabs doesn't hammer the free Overpass API.
@MainActor
final class PlaceService {
    private static let cacheMaxAge: TimeInterval = 300
    private static let cacheMaxDrift: Double = 500

    private let client = OverpassClient()
    private var cache: [PlaceCategory: (center: Coordinate, fetchedAt: Date, places: [Place])] = [:]

    func places(near coordinate: Coordinate, category: PlaceCategory) async throws -> [Place] {
        if let cached = cache[category],
           Date.now.timeIntervalSince(cached.fetchedAt) < Self.cacheMaxAge,
           TripTracker.distance(from: cached.center, to: coordinate) < Self.cacheMaxDrift {
            return cached.places
        }
        let places = try await client.places(near: coordinate, radius: category.searchRadius, category: category)
        cache[category] = (coordinate, .now, places)
        return places
    }
}
