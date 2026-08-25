import Foundation

/// One day of driving, aggregated for the Fitness-style Trips view.
/// Pure computation — deterministic and unit-tested.
struct DayStats: Equatable {
    var miles: Double = 0
    var duration: TimeInterval = 0
    var maxSpeedMph: Int?
    var tripCount: Int = 0
    var hardEvents: Int = 0
    /// The split behind `hardEvents`, for display.
    var hardBraking: Int = 0
    var hardAcceleration: Int = 0
    /// Times the posted limit was crossed.
    var overLimitCrossings: Int = 0
    /// Times speed went more than 5 mph past the posted limit.
    var wellOverCrossings: Int = 0

    /// The Drive Score, 0–100 — Tesla-calibrated after field testing: an
    /// afternoon of ordinary flow-of-traffic driving should score in the
    /// 80s-90s, not single digits. Crossing the posted limit by a little is
    /// informational (counted, shown, zero deduction — the chime tier);
    /// the score reacts to genuinely-over crossings (−5, adaptive margin:
    /// max of 5 mph and 15% of the limit) and hard maneuvers (−10).
    /// `nil` on days with no driving — no drive, no ring.
    var score: Int? {
        guard tripCount > 0 else { return nil }
        return max(0, 100 - hardEvents * 10 - wellOverCrossings * 5)
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
            // Retroactive false-positive filter: a g-spike recorded while
            // (near-)stationary was the phone being handled, not driving.
            // The recorder now gates these at capture; this cleans history.
            let stationary = event.speedMph.map { $0 < 8 } ?? false
            switch event.kind {
            case "hardBraking":
                guard !stationary else { break }
                stats.hardBraking += 1
                stats.hardEvents += 1
            case "hardAcceleration":
                guard !stationary else { break }
                stats.hardAcceleration += 1
                stats.hardEvents += 1
            case "overLimit": stats.overLimitCrossings += 1
            case "wellOverLimit": stats.wellOverCrossings += 1
            default: break
            }
        }
        return stats
    }
}
