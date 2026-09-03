import Foundation

/// One day, told as a sequence: drove somewhere, stayed a while, drove on.
///
/// Pure composition over the day's completed trips — the recall moment
/// ("I was here that day") assembled from data the app already keeps.
/// Presentation (place names, weather symbols) happens in the view; this
/// only decides the sequence and the arithmetic.
enum DayStory {
    struct Stop: Equatable {
        /// Index of the trip this stop follows.
        var afterTrip: Int
        var duration: TimeInterval
        /// Where the vehicle sat — the previous trip's last recorded point.
        var coordinate: Coordinate?
    }

    /// Stops between consecutive completed trips, in trip order. Trips are
    /// sorted internally; gaps of an hour or a minute both count — the
    /// story is what happened, not a judgment about it. Overlapping or
    /// out-of-order data yields no stop rather than a negative one.
    static func stops(
        between trips: [(start: Date, end: Date, lastCoordinate: Coordinate?)]
    ) -> [Stop] {
        let ordered = trips.sorted { $0.start < $1.start }
        return zip(ordered.indices.dropLast(), zip(ordered, ordered.dropFirst())).compactMap { index, pair in
            let (earlier, later) = pair
            let gap = later.start.timeIntervalSince(earlier.end)
            guard gap > 0 else { return nil }
            return Stop(afterTrip: index, duration: gap, coordinate: earlier.lastCoordinate)
        }
    }

    /// Walks whose midpoint lands inside a drive are Core Motion misreads
    /// (a passenger's fidgeting, a stop-and-go crawl) — the story keeps
    /// only walks that happened between drives. Pure and unit-tested.
    static func walksOutsideDrives(
        _ walks: [(start: Date, end: Date)],
        drives: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        walks.filter { walk in
            let midpoint = walk.start.addingTimeInterval(walk.end.timeIntervalSince(walk.start) / 2)
            return !drives.contains { $0.start <= midpoint && midpoint <= $0.end }
        }
    }

    /// The day's headline numbers, tied out over the same trips the story
    /// shows: total distance and total recorded drive time.
    static func totals(
        of trips: [(start: Date, end: Date, meters: Double)]
    ) -> (meters: Double, seconds: TimeInterval) {
        trips.reduce((0, 0)) { totals, trip in
            (totals.0 + trip.meters, totals.1 + trip.end.timeIntervalSince(trip.start))
        }
    }
}
