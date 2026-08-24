import SwiftUI

/// Turns a recorded route into contiguous same-color runs by speed, so the
/// trip map can draw an Activity-style speed-colored path with a handful of
/// polylines instead of one per point.
enum RouteColoring {
    /// Speed bands (m/s) and their colors, slow → fast. Boundaries at
    /// 15 / 30 / 45 / 60 / 75 / 100 mph; escalation follows weather-radar
    /// convention, with purple reserved for the genuinely dangerous 100+.
    static let bands: [(upperBound: Double, color: Color, label: String)] = [
        (6.7, .teal, "<15"),
        (13.4, .green, "15–30"),
        (20.1, .yellow, "30–45"),
        (26.8, .orange, "45–60"),
        (33.5, .red, "60–75"),
        (44.7, Color(red: 0.6, green: 0.05, blue: 0.1), "75–100"),
        (.infinity, .purple, "100+"),
    ]

    /// The bands a trip actually visited, in slow→fast order — so the legend
    /// only shows colors that appear on the map.
    static func presentBands(in runs: [Run]) -> [Int] {
        Set(runs.map(\.bandIndex)).sorted()
    }

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
