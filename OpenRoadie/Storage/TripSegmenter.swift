import Foundation

/// Splits a recorded route into legs at the long stops inside it.
///
/// This is where "was that one trip or two?" now gets decided. Recording no
/// longer has to answer it live: a drive keeps recording through a gas stop,
/// and the boundary is drawn afterwards, from the finished route. Being
/// wrong here costs nothing — change the threshold and the same stored
/// points re-split — where being wrong live used to cost the drive.
///
/// Pure and deterministic; no SwiftData, no clock of its own.
enum TripSegmenter {
    struct Config: Equatable {
        /// A gap between recorded points longer than this ends a leg.
        /// Route points are written only when the position advances, so a
        /// gap IS a stop.
        var splitAfterStopped: TimeInterval = 600
        /// A leg shorter than this went nowhere — a parking-lot shuffle,
        /// a re-park — and is not worth showing as its own leg.
        var minimumLegMeters: Double = 400
    }

    struct Leg: Equatable, Identifiable {
        /// Indices into the source route, inclusive.
        var range: ClosedRange<Int>
        var start: Date
        var end: Date
        var meters: Double
        /// How long the vehicle sat still before this leg began. `nil` for
        /// the first leg of the drive.
        var stoppedBefore: TimeInterval?

        var id: Int { range.lowerBound }
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// The drive's legs, in order. A drive that never stopped for long
    /// returns a single leg — callers show the breakdown only when there
    /// is more than one, so an ordinary commute gains no new UI.
    static func legs(_ samples: [RouteSample], config: Config = Config()) -> [Leg] {
        guard samples.count >= 2 else { return [] }

        // Cut points: the index that ends a leg, paired with the length of
        // the stop that follows it.
        var cuts: [(index: Int, stopped: TimeInterval)] = []
        for index in 0..<(samples.count - 1) {
            let gap = samples[index + 1].timestamp.timeIntervalSince(samples[index].timestamp)
            if gap > config.splitAfterStopped {
                cuts.append((index, gap))
            }
        }

        var legs: [Leg] = []
        var start = 0
        var stoppedBefore: TimeInterval?
        for cut in cuts + [(samples.count - 1, 0)] {
            let range = start...cut.index
            if range.count >= 2 {
                legs.append(Leg(
                    range: range,
                    start: samples[range.lowerBound].timestamp,
                    end: samples[range.upperBound].timestamp,
                    meters: distance(samples, over: range),
                    stoppedBefore: stoppedBefore
                ))
            }
            start = cut.index + 1
            stoppedBefore = cut.stopped
        }

        return merge(shortLegs: legs, config: config)
    }

    /// Folds a leg that went essentially nowhere into its neighbor rather
    /// than presenting a 200-foot "leg" beside a 20-mile one. The stop that
    /// preceded the dropped leg is carried forward, so the surviving legs
    /// still account for all the standing-still time.
    private static func merge(shortLegs legs: [Leg], config: Config) -> [Leg] {
        guard legs.count > 1 else { return legs }
        var kept: [Leg] = []
        var carried: TimeInterval?
        for leg in legs {
            guard leg.meters >= config.minimumLegMeters else {
                carried = (carried ?? 0) + (leg.stoppedBefore ?? 0) + leg.duration
                continue
            }
            var leg = leg
            if let carried {
                leg.stoppedBefore = (leg.stoppedBefore ?? 0) + carried
            }
            carried = nil
            kept.append(leg)
        }
        // The first surviving leg never reports a preceding stop.
        if !kept.isEmpty { kept[0].stoppedBefore = nil }
        return kept
    }

    private static func distance(_ samples: [RouteSample], over range: ClosedRange<Int>) -> Double {
        let slice = samples[range]
        return zip(slice, slice.dropFirst()).reduce(0) { total, pair in
            total + TripTracker.distance(from: pair.0.coordinate, to: pair.1.coordinate)
        }
    }
}
