import CoreLocation
import Foundation

/// Reverse-geocoded place names — the nouns for stops and destinations.
///
/// CLGeocoder is an Apple network service with a strict informal rate limit,
/// so every resolved name is cached on disk keyed by a ~100 m grid cell:
/// each place is asked about once, ever. Requests are serialized with a
/// polite gap. Names are garnish — every path tolerates `nil`.
@MainActor
final class PlaceNamer {
    static let shared = PlaceNamer()

    private let geocoder = CLGeocoder()
    private var cache: [String: String]
    private var pending: [String: Task<String?, Never>] = [:]
    private var lastRequestAt = Date.distantPast
    private let cacheURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheURL = support.appendingPathComponent("placenames.json")
        cache = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: cacheURL))) ?? [:]
    }

    /// ~110 m cells: fine enough that a stop resolves to the right block,
    /// coarse enough that the same parking lot is one cache entry.
    nonisolated static func cacheKey(for coordinate: Coordinate) -> String {
        String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
    }

    /// Human name for a spot — "Draeger's Market · Menlo Park", or the
    /// street when no point of interest is there. Pure and unit-tested.
    nonisolated static func displayName(areaOfInterest: String?, name: String?, thoroughfare: String?, locality: String?) -> String? {
        // CLPlacemark's `name` is often a street address ("851 Oak Grove
        // Ave") — prefer a real point of interest, then the bare street.
        let base = areaOfInterest ?? {
            if let name, let thoroughfare, name.hasSuffix(thoroughfare), name != thoroughfare {
                return thoroughfare // strip the house number
            }
            return name ?? thoroughfare
        }()
        switch (base, locality) {
        case (nil, nil): return nil
        case (let base?, nil): return base
        case (nil, let locality?): return locality
        case (let base?, let locality?):
            return base == locality ? base : "\(base) · \(locality)"
        }
    }

    /// Instant, cache-only. For assembly paths that must never wait on
    /// the network — resolve misses in the background and re-ask.
    func cachedName(for coordinate: Coordinate) -> String? {
        guard let cached = cache[Self.cacheKey(for: coordinate)], !cached.isEmpty else { return nil }
        return cached
    }

    func name(for coordinate: Coordinate) async -> String? {
        let key = Self.cacheKey(for: coordinate)
        if let cached = cache[key] {
            return cached.isEmpty ? nil : cached
        }
        if let pending = pending[key] {
            return await pending.value
        }
        let task = Task<String?, Never> { [weak self] in
            await self?.resolve(coordinate: coordinate, key: key)
        }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        return result
    }

    private func resolve(coordinate: Coordinate, key: String) async -> String? {
        // Polite pacing: CLGeocoder throttles aggressive clients hard.
        let since = Date.now.timeIntervalSince(lastRequestAt)
        if since < 1.2 {
            try? await Task.sleep(for: .seconds(1.2 - since))
        }
        lastRequestAt = .now
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil // transient failure: not cached, retried another day
        }
        let name = Self.displayName(
            areaOfInterest: placemark.areasOfInterest?.first,
            name: placemark.name,
            thoroughfare: placemark.thoroughfare,
            locality: placemark.locality
        )
        cache[key] = name ?? "" // a confirmed nowhere is cached too
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL)
        }
        return name
    }
}
