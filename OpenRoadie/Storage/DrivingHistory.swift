import Foundation

/// Lifetime driving history, computed straight from stored trips —
/// pure and deterministic, nothing granted or stored.
struct DrivingHistory: Equatable {
    var drives = 0
    var daysDriven = 0
    var totalSeconds: TimeInterval = 0
    var totalMiles = 0.0
    var maxSpeedMps: Double?
    /// Single longest trip by distance / by duration.
    var longestMiles = 0.0
    var longestSeconds: TimeInterval = 0
    /// The slowest trip pace in seconds per mile (trips of at least a
    /// mile, so parking-lot creeps don't count) — a rough traffic gauge:
    /// the more time a mile took, the more of it was spent sitting in it.
    var slowestPaceSecondsPerMile: Double?
    /// Typical (median across driving days) first departure and last
    /// arrival, as clock minutes since midnight. Lifetime min/max would
    /// converge on the midnight boundary and go meaningless; the median
    /// of each day's first/last stays a portrait of the routine. Days
    /// roll over at 4 AM, so a 12:30 AM arrival counts as very LATE,
    /// not as an early departure.
    var typicalFirstDepartureMinute: Int?
    var typicalLastArrivalMinute: Int?

    /// Minutes past 4 AM on a 24 h cycle — the day boundary for
    /// departure/arrival stats.
    static func cycleMinute(hour: Int, minute: Int) -> Int {
        ((hour * 60 + minute) - 240 + 1440) % 1440
    }

    var averageMph: Double? {
        totalSeconds > 0 ? totalMiles / (totalSeconds / 3600) : nil
    }

    var averageSecondsPerDay: TimeInterval {
        daysDriven > 0 ? totalSeconds / Double(daysDriven) : 0
    }

    var averageMilesPerDay: Double {
        daysDriven > 0 ? totalMiles / Double(daysDriven) : 0
    }

    static func compute(trips: [Trip], calendar: Calendar = .current) -> DrivingHistory {
        var history = DrivingHistory()
        var days = Set<Date>()
        // Per 4AM-cycle day: the day's first departure / last arrival.
        var firstDepartures: [Date: Int] = [:]
        var lastArrivals: [Date: Int] = [:]
        for trip in trips {
            guard let end = trip.endDate else { continue }
            let miles = trip.distance / 1609.344
            let seconds = trip.duration ?? 0
            history.drives += 1
            history.totalMiles += miles
            history.totalSeconds += seconds
            days.insert(calendar.startOfDay(for: trip.startDate))
            if let maxSpeed = trip.maxSpeed {
                history.maxSpeedMps = max(history.maxSpeedMps ?? 0, maxSpeed)
            }
            history.longestMiles = max(history.longestMiles, miles)
            history.longestSeconds = max(history.longestSeconds, seconds)
            if miles >= 1 {
                let pace = seconds / miles
                history.slowestPaceSecondsPerMile = max(history.slowestPaceSecondsPerMile ?? 0, pace)
            }

            let cycleDay = calendar.startOfDay(for: trip.startDate.addingTimeInterval(-4 * 3600))
            let startComponents = calendar.dateComponents([.hour, .minute], from: trip.startDate)
            let endComponents = calendar.dateComponents([.hour, .minute], from: end)
            let startCycle = Self.cycleMinute(hour: startComponents.hour ?? 0, minute: startComponents.minute ?? 0)
            let endCycle = Self.cycleMinute(hour: endComponents.hour ?? 0, minute: endComponents.minute ?? 0)
            firstDepartures[cycleDay] = min(firstDepartures[cycleDay] ?? startCycle, startCycle)
            lastArrivals[cycleDay] = max(lastArrivals[cycleDay] ?? endCycle, endCycle)
        }
        history.daysDriven = days.count
        history.typicalFirstDepartureMinute = Self.median(firstDepartures.values.sorted()).map { ($0 + 240) % 1440 }
        history.typicalLastArrivalMinute = Self.median(lastArrivals.values.sorted()).map { ($0 + 240) % 1440 }
        return history
    }

    private static func median(_ sorted: [Int]) -> Int? {
        guard !sorted.isEmpty else { return nil }
        return sorted[sorted.count / 2]
    }

    /// "6:05 AM" style label for a minutes-since-midnight value.
    static func timeLabel(minute: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
