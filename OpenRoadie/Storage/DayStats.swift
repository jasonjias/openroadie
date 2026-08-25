import Foundation

/// One day of driving, aggregated for the Fitness-style Trips view.
/// Pure computation — deterministic and unit-tested.
struct DayStats: Equatable {
    var miles: Double = 0
    var duration: TimeInterval = 0
    var maxSpeedMph: Int?
    var tripCount: Int = 0
    var hardEvents: Int = 0

    /// The Drive Score, 0–100: start at 100, lose 8 per hard maneuver.
    /// `nil` on days with no driving — no drive, no ring.
    var score: Int? {
        guard tripCount > 0 else { return nil }
        return max(0, 100 - hardEvents * 8)
    }

    static func compute(
        trips: [Trip],
        events: [DriveEvent],
        on day: Date,
        calendar: Calendar = .current
    ) -> DayStats {
        var stats = DayStats()
        for trip in trips where calendar.isDate(trip.startDate, inSameDayAs: day) {
            guard trip.endDate != nil else { continue }
            stats.tripCount += 1
            stats.miles += trip.distance / 1609.344
            stats.duration += trip.duration ?? 0
            if let maxSpeed = trip.maxSpeed {
                let mph = Int((maxSpeed * 2.236936).rounded())
                stats.maxSpeedMph = max(stats.maxSpeedMph ?? 0, mph)
            }
        }
        stats.hardEvents = events.count { calendar.isDate($0.timestamp, inSameDayAs: day) }
        return stats
    }
}
