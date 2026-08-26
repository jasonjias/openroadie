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
    /// Earliest departure and latest arrival by TIME OF DAY, across all
    /// drives (minutes since midnight).
    var earliestStartMinute: Int?
    var latestEndMinute: Int?

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
            let startComponents = calendar.dateComponents([.hour, .minute], from: trip.startDate)
            let endComponents = calendar.dateComponents([.hour, .minute], from: end)
            let startMinute = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
            let endMinute = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)
            history.earliestStartMinute = min(history.earliestStartMinute ?? startMinute, startMinute)
            history.latestEndMinute = max(history.latestEndMinute ?? endMinute, endMinute)
        }
        history.daysDriven = days.count
        return history
    }

    /// "6:05 AM" style label for a minutes-since-midnight value.
    static func timeLabel(minute: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
