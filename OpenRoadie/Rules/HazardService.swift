import Foundation

/// Dangerous-road warnings from public U.S. DOT data: the app bundles a
/// clustered extract of NHTSA FARS (every fatal crash, with coordinates),
/// built by Tools/build-hazards.py. Fully offline, nothing phoned home —
/// the whole dataset rides along in the bundle.
///
/// RoadSentinel charges $29.99 for this. The data was public all along.
@MainActor
final class HazardService {
    static let enabledKey = "crashDataWarningsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    struct Hazard: Equatable {
        let latitude: Double
        let longitude: Double
        let crashes: Int
    }

    /// Alert when within this many meters of a hazard cell.
    static let alertRadius: Double = 220

    /// Grid-bucketed hazards for O(1) neighborhood lookup.
    private var grid: [Int64: [Hazard]] = [:]
    private let bucket = 0.01 // degrees, ~1.1 km — lookup checks 3×3 buckets
    private var loaded = false
    /// Cells already alerted this drive — one warning per zone per drive.
    private var alerted: Set<Int64> = []

    func startDrive() {
        alerted = []
    }

    /// The closest un-alerted hazard within range, marking it alerted.
    func check(_ coordinate: Coordinate) -> Hazard? {
        loadIfNeeded()
        guard !grid.isEmpty else { return nil }

        var best: (hazard: Hazard, distance: Double, key: Int64)?
        let bx = Int(floor(coordinate.longitude / bucket))
        let by = Int(floor(coordinate.latitude / bucket))
        for dx in -1...1 {
            for dy in -1...1 {
                guard let hazards = grid[Self.key(x: bx + dx, y: by + dy)] else { continue }
                for hazard in hazards {
                    let distance = TripTracker.distance(
                        from: coordinate,
                        to: Coordinate(latitude: hazard.latitude, longitude: hazard.longitude)
                    )
                    let cellKey = Self.cellKey(hazard)
                    if distance <= Self.alertRadius, !alerted.contains(cellKey),
                       best == nil || distance < best!.distance {
                        best = (hazard, distance, cellKey)
                    }
                }
            }
        }
        if let best {
            alerted.insert(best.key)
            return best.hazard
        }
        return nil
    }

    // MARK: - Loading

    /// Test hook: inject hazards without a bundle.
    func load(hazards: [Hazard]) {
        loaded = true
        grid = [:]
        for hazard in hazards {
            let key = Self.key(
                x: Int(floor(hazard.longitude / bucket)),
                y: Int(floor(hazard.latitude / bucket))
            )
            grid[key, default: []].append(hazard)
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.main.url(forResource: "hazards", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = decoded["hazards"] as? [[Any]] else { return }
        load(hazards: rows.compactMap { row in
            guard row.count >= 3,
                  let lat = row[0] as? Double,
                  let lon = row[1] as? Double,
                  let count = row[2] as? Int else { return nil }
            return Hazard(latitude: lat, longitude: lon, crashes: count)
        })
    }

    private static func key(x: Int, y: Int) -> Int64 {
        (Int64(x) << 32) | Int64(UInt32(bitPattern: Int32(y)))
    }

    private static func cellKey(_ hazard: Hazard) -> Int64 {
        key(x: Int(hazard.longitude * 10_000), y: Int(hazard.latitude * 10_000))
    }
}
