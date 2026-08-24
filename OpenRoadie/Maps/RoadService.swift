import Foundation

/// Resolves "what road am I on" against OpenStreetMap while being a polite
/// Overpass citizen: roads are fetched for a ~600 m area at a time and
/// matching happens locally against that cache on every GPS fix, so network
/// queries only fire every few hundred meters of travel.
@MainActor
final class RoadService {
    /// UserDefaults key for the Settings toggle. Defaults to enabled.
    static let enabledKey = "roadAwarenessEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static let fetchRadius: Double = 600
    private static let refetchDistance: Double = 400
    private static let cacheMaxAge: TimeInterval = 300

    private let client = OverpassClient()
    private var cache: (center: Coordinate, fetchedAt: Date, ways: [OverpassWay])?
    private var fetchTask: Task<Void, Never>?

    /// Matches the coordinate against locally cached roads. Cheap; called on
    /// every accepted GPS fix.
    func currentRoad(at coordinate: Coordinate) -> RoadInfo? {
        guard let cache else { return nil }
        return RoadMatcher.road(at: coordinate, from: cache.ways)
    }

    /// Kicks off a background refetch when the cache is missing, stale, or
    /// the drive has moved too far from its center. Never blocks the caller.
    func refreshIfNeeded(around coordinate: Coordinate) {
        guard fetchTask == nil else { return }
        if let cache,
           Date.now.timeIntervalSince(cache.fetchedAt) < Self.cacheMaxAge,
           TripTracker.distance(from: cache.center, to: coordinate) < Self.refetchDistance {
            return
        }

        fetchTask = Task { [client] in
            defer { self.fetchTask = nil }
            do {
                let ways = try await client.roads(near: coordinate, radius: Self.fetchRadius)
                self.cache = (coordinate, .now, ways)
            } catch {
                // Offline or Overpass unavailable: keep any stale cache and
                // try again on a later fix. Road info is best-effort.
            }
        }
    }

    func cancel() {
        fetchTask?.cancel()
        fetchTask = nil
    }
}
