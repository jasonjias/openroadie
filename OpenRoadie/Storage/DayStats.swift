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
    /// Harsh corners (lateral g past threshold).
    var harshCornering: Int = 0
    /// Phone handled while moving at road speed.
    var phoneUseEvents: Int = 0

    /// Severity-weighted event points — the numerator of the score's
    /// rate. Distracted driving weighs heaviest; crossing the posted
    /// limit by a little is informational (counted, shown, zero weight —
    /// the chime tier); genuinely-over crossings weigh 4 (adaptive
    /// margin: max of 5 mph and 15% of the limit).
    var weightedEventPoints: Double {
        Double(hardEvents * 8
            + harshCornering * 8
            + wellOverCrossings * 4
            + phoneUseEvents * 12)
    }

    /// The Drive Score, 0–100, normalized by EXPOSURE: raw deductions
    /// punish driving a lot (a 200-mile day collects more events than a
    /// 2-mile one and everyone trends to 0), so the score grades the
    /// RATE — weighted points per 100 miles — through an exponential:
    ///
    ///     rate  = weighted / max(miles, 20) × 100
    ///     score = 100 · e^(−rate / 450)
    ///
    /// Exponential, not linear-clamped, on purpose: like a graded test
    /// there's no true 0 — bad days land in the 30s and stay ordered.
    /// The 20-mile floor keeps one mistake on a short hop from cratering
    /// the day. Field-softened after the first real week: 1 hard brake in
    /// a 40-mile day ≈ 96; that same brake plus 2 more and a phone pickup
    /// ≈ 83; 10 hard brakes in 30 miles ≈ 39. `nil` on days with no
    /// driving — no drive, no ring.
    var score: Int? {
        guard tripCount > 0 else { return nil }
        return Self.score(weightedPoints: weightedEventPoints, miles: miles)
    }

    /// The rate→score mapping, shared by day scores and the pooled
    /// multi-day overall score.
    static func score(weightedPoints: Double, miles: Double) -> Int {
        let ratePer100Miles = weightedPoints / max(miles, 20) * 100
        return Int((100 * exp(-ratePer100Miles / 450)).rounded())
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
            case "harshCornering":
                guard !stationary else { break }
                stats.harshCornering += 1
            case "phoneUse": stats.phoneUseEvents += 1
            default: break
            }
        }
        return stats
    }
}
