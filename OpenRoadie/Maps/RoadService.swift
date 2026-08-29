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
    /// The way matched on the previous fix — carries a small advantage so
    /// matching doesn't flap between candidates at intersections.
    private var lastMatchedWayId: Int64?

    /// Matches the coordinate against locally cached roads, using heading
    /// so an overpass can't steal the match from the road beneath it.
    /// Cheap; called on every accepted GPS fix.
    func currentRoad(at coordinate: Coordinate, courseDegrees: Double? = nil, speedMps: Double? = nil) -> RoadInfo? {
        guard let match = currentMatch(at: coordinate, courseDegrees: courseDegrees, speedMps: speedMps) else {
            return nil
        }
        let tags = match.way.tags
        return RoadInfo(
            name: tags["name"],
            ref: tags["ref"],
            speedLimit: tags["maxspeed"].flatMap(RoadMatcher.speedLimit(fromMaxspeedTag:))
        )
    }

    /// The upcoming curve of the matched road in the vehicle's frame
    /// (lateral meters per 4 m of travel) — what bends the 3D scene's
    /// road. `nil` when off known roads or the course is unknown.
    func upcomingCurve(at coordinate: Coordinate, courseDegrees: Double?, speedMps: Double? = nil) -> [Double]? {
        guard let courseDegrees,
              let match = currentMatch(at: coordinate, courseDegrees: courseDegrees, speedMps: speedMps)
        else { return nil }
        return RoadMatcher.upcomingCurve(at: coordinate, courseDegrees: courseDegrees, along: match.way)
    }

    /// One match per fix, shared by the road info and the scene's curve —
    /// they must never disagree about which road you're on.
    private func currentMatch(at coordinate: Coordinate, courseDegrees: Double?, speedMps: Double?) -> RoadMatcher.Match? {
        guard let cache else { return nil }
        guard let match = RoadMatcher.bestMatch(
            at: coordinate,
            courseDegrees: courseDegrees,
            speedMps: speedMps,
            in: cache.ways,
            preferring: lastMatchedWayId
        ), match.distance <= RoadMatcher.maxMatchDistance else {
            lastMatchedWayId = nil
            return nil
        }
        lastMatchedWayId = match.way.id
        return match
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
