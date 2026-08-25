import Foundation

/// One day of driving, aggregated for the Fitness-style Trips view.
/// Pure computation — deterministic and unit-tested.
struct DayStats: Equatable {
    var miles: Double = 0
    var duration: TimeInterval = 0
    var maxSpeedMph: Int?
    var tripCount: Int = 0
    var hardEvents: Int = 0
    /// Times the posted limit was crossed.
    var overLimitCrossings: Int = 0
    /// Times speed went more than 5 mph past the posted limit.
    var wellOverCrossings: Int = 0

    /// The Drive Score, 0–100 — actual vs expected, where expected is the
    /// posted limit and smooth inputs. Deterministic and explainable:
    /// start at 100; −8 per hard maneuver, −3 per limit crossing, −8 per
    /// +5-over crossing. `nil` on days with no driving — no drive, no ring.
    var score: Int? {
        guard tripCount > 0 else { return nil }
        return max(0, 100 - hardEvents * 8 - overLimitCrossings * 3 - wellOverCrossings * 8)
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
        for event in events where calendar.isDate(event.timestamp, inSameDayAs: day) {
            switch event.kind {
            case "hardBraking", "hardAcceleration": stats.hardEvents += 1
            case "overLimit": stats.overLimitCrossings += 1
            case "wellOverLimit": stats.wellOverCrossings += 1
            default: break
            }
        }
        return stats
    }
}
