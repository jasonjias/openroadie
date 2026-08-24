import SwiftUI

/// Turns a recorded route into contiguous same-color runs by speed, so the
/// trip map can draw an Activity-style speed-colored path with a handful of
/// polylines instead of one per point.
enum RouteColoring {
    /// Speed bands (m/s) and their colors, slow → fast.
    /// 15 / 30 / 45 / 60+ mph boundaries.
    static let bands: [(upperBound: Double, color: Color)] = [
        (6.7, .teal),
        (13.4, .green),
        (20.1, .yellow),
        (26.8, .orange),
        (.infinity, .red),
    ]

    static func bandIndex(forSpeed speed: Double?) -> Int? {
        guard let speed else { return nil }
        return bands.firstIndex { speed < $0.upperBound }
    }

    struct Run: Equatable {
        var bandIndex: Int
        /// Indices into the source route; each run overlaps its neighbor by
        /// one point so the drawn path is continuous.
        var pointIndices: ClosedRange<Int>
    }

    /// Groups consecutive route points into same-band runs. A point with
    /// unknown speed inherits the current band so the path never breaks.
    static func runs(forSpeeds speeds: [Double?]) -> [Run] {
        guard speeds.count >= 2 else { return [] }

        var runs: [Run] = []
        var currentBand = bandIndex(forSpeed: speeds[0]) ?? 1
        var runStart = 0

        for index in 1..<speeds.count {
            let band = bandIndex(forSpeed: speeds[index]) ?? currentBand
            if band != currentBand {
                runs.append(Run(bandIndex: currentBand, pointIndices: runStart...index))
                currentBand = band
                runStart = index
            }
        }
        if runStart < speeds.count - 1 {
            runs.append(Run(bandIndex: currentBand, pointIndices: runStart...(speeds.count - 1)))
        }
        return runs
    }
}
