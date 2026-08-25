import Foundation

/// The POI categories OpenRoadie knows how to find, each mapped to the
/// OpenStreetMap tags that define it.
enum PlaceCategory: String, CaseIterable, Identifiable, Sendable, Codable {
    case food
    case coffee
    case fuel
    case charger
    case supercharger
    case landmark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: "Food"
        case .coffee: "Coffee"
        case .fuel: "Gas"
        case .charger: "Chargers"
        case .supercharger: "Superchargers"
        case .landmark: "Landmarks"
        }
    }

    var systemImage: String {
        switch self {
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer.fill"
        case .fuel: "fuelpump.fill"
        case .charger: "bolt.car.fill"
        case .supercharger: "bolt.circle.fill"
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
        case .supercharger: #"["amenity"="charging_station"]["brand"~"Tesla",i]"#
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
        case .supercharger: 15_000
        }
    }

    var singular: String {
        switch self {
        case .food: "restaurant"
        case .coffee: "cafe"
        case .fuel: "gas station"
        case .charger: "charger"
        case .supercharger: "Supercharger"
        case .landmark: "landmark"
        }
    }

    // MARK: - User-chosen visibility (Nearby chips)
    // Ordering (built-ins interleaved with custom categories) lives in
    // `NearbyChip`; both share `orderDefaultsKey`.

    static let hiddenDefaultsKey = "hiddenPlaceCategories"
    static let orderDefaultsKey = "placeCategoryOrder"

    static func setHidden(_ category: PlaceCategory, _ hidden: Bool) {
        var set = Set(UserDefaults.standard.stringArray(forKey: hiddenDefaultsKey) ?? [])
        if hidden { set.insert(category.rawValue) } else { set.remove(category.rawValue) }
        UserDefaults.standard.set(Array(set).sorted(), forKey: hiddenDefaultsKey)
    }

    static func isHidden(_ category: PlaceCategory) -> Bool {
        (UserDefaults.standard.stringArray(forKey: hiddenDefaultsKey) ?? []).contains(category.rawValue)
    }
}

/// One point of interest near the drive.
struct Place: Identifiable, Equatable, Sendable, Codable {
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

/// Fetches nearby places with a per-category cache persisted to disk, so
/// tab-flipping, relaunching, and free-server rate limits don't produce
/// errors. Gas stations and chargers don't move: cache them accordingly.
@MainActor
final class PlaceService {
    struct CacheEntry: Codable {
        var center: Coordinate
        var fetchedAt: Date
        var places: [Place]
    }

    private static let cacheMaxDrift: Double = 500

    private let client = OverpassClient()
    private var cache: [String: CacheEntry] = [:]
    private var loaded = false

    /// How long a cached answer stays fresh. Static infrastructure barely
    /// changes; food churns a little faster.
    static func timeToLive(for category: PlaceCategory) -> TimeInterval {
        switch category {
        case .food, .coffee: 3 * 3600
        case .fuel, .charger, .supercharger, .landmark: 24 * 3600
        }
    }

    func places(near coordinate: Coordinate, category: PlaceCategory, forceRefresh: Bool = false) async throws -> [Place] {
        try await cached(
            key: category.rawValue,
            near: coordinate,
            timeToLive: Self.timeToLive(for: category),
            radius: category.searchRadius,
            forceRefresh: forceRefresh
        ) {
            try await self.client.places(near: $0, radius: category.searchRadius, category: category)
        }
    }

    /// Brand locations don't move: custom categories cache like infrastructure.
    func places(near coordinate: Coordinate, custom: CustomCategory, forceRefresh: Bool = false) async throws -> [Place] {
        try await cached(
            key: custom.key,
            near: coordinate,
            timeToLive: 24 * 3600,
            radius: custom.searchRadius,
            forceRefresh: forceRefresh
        ) {
            try await self.client.places(near: $0, radius: custom.searchRadius, matching: custom.overpassRegex)
        }
    }

    private func cached(
        key: String,
        near coordinate: Coordinate,
        timeToLive: TimeInterval,
        radius: Double,
        forceRefresh: Bool,
        fetch: (Coordinate) async throws -> [Place]
    ) async throws -> [Place] {
        loadIfNeeded()

        if !forceRefresh,
           let entry = cache[key],
           Date.now.timeIntervalSince(entry.fetchedAt) < timeToLive,
           TripTracker.distance(from: entry.center, to: coordinate) < Self.cacheMaxDrift {
            return entry.places
        }

        do {
            let places = try await fetch(coordinate)
            cache[key] = CacheEntry(center: coordinate, fetchedAt: .now, places: places)
            persist()
            return places
        } catch {
            // The free Overpass servers rate-limit. A stale answer beats an
            // error — serve it as long as the user is still inside its area.
            if let entry = cache[key],
               TripTracker.distance(from: entry.center, to: coordinate) < radius / 2 {
                return entry.places
            }
            throw error
        }
    }

    // MARK: - Disk persistence

    private static var cacheURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("openroadie-places.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else { return }
        cache = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: Self.cacheURL)
        }
    }
}
