import CoreMotion
import Foundation

/// Walks, read back from the motion history iOS keeps on its own.
///
/// The answer to "can this always be recording?" without an always-on app:
/// the motion coprocessor already records activity classification and
/// pedometer data for about a week, continuously, at zero cost to us. This
/// reads it retroactively — walks appear in the day story even though
/// OpenRoadie wasn't running when they happened. Entirely on-device; days
/// older than the system's window honestly return nothing.
@MainActor
final class WalkHistory {
    struct Walk: Equatable, Sendable {
        var start: Date
        var end: Date
        /// From the pedometer, when it knows.
        var meters: Double?
        var steps: Int?

        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()

    /// Coalesces raw activity samples into walk intervals: brief pauses
    /// (a crosswalk light) merge, blips shorter than the minimum drop.
    /// Pure and unit-tested.
    nonisolated static func walkIntervals(
        from samples: [(date: Date, walking: Bool)],
        until end: Date,
        mergeGap: TimeInterval = 120,
        minimumDuration: TimeInterval = 180
    ) -> [(start: Date, end: Date)] {
        // Each walking sample covers from its own date to the next sample's
        // (or the query end). Adjacent covered spans chain into one interval.
        var raw: [(start: Date, end: Date)] = []
        for (index, sample) in samples.enumerated() where sample.walking {
            let spanEnd = index + 1 < samples.count ? samples[index + 1].date : end
            if let last = raw.last, sample.date <= last.end {
                raw[raw.count - 1].end = max(last.end, spanEnd)
            } else {
                raw.append((sample.date, spanEnd))
            }
        }
        // Merge intervals separated by less than the gap.
        var merged: [(start: Date, end: Date)] = []
        for interval in raw {
            if let last = merged.last, interval.start.timeIntervalSince(last.end) < mergeGap {
                merged[merged.count - 1].end = interval.end
            } else {
                merged.append(interval)
            }
        }
        return merged.filter { $0.end.timeIntervalSince($0.start) >= minimumDuration }
    }

    /// The day's significant walks, oldest first. Empty when motion history
    /// is unavailable, denied, or the day is past the system's window.
    func walks(on day: Date, calendar: Calendar = .current) async -> [Walk] {
        guard CMMotionActivityManager.isActivityAvailable() else { return [] }
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let end = min(dayEnd, .now)
        guard end > dayStart else { return [] }

        // Reduce to Sendable value pairs inside the callback — CMMotionActivity
        // itself can't cross the actor boundary under Swift 6.
        let samples: [(date: Date, walking: Bool)] = await withCheckedContinuation { continuation in
            activityManager.queryActivityStarting(from: dayStart, to: end, to: .main) { activities, _ in
                continuation.resume(returning: (activities ?? []).map {
                    (date: $0.startDate, walking: $0.walking || $0.running)
                })
            }
        }
        let intervals = Self.walkIntervals(from: samples, until: end)

        var walks: [Walk] = []
        for interval in intervals {
            let (meters, steps): (Double?, Int?) = await withCheckedContinuation { continuation in
                pedometer.queryPedometerData(from: interval.start, to: interval.end) { data, _ in
                    continuation.resume(returning: (data?.distance?.doubleValue, data?.numberOfSteps.intValue))
                }
            }
            walks.append(Walk(start: interval.start, end: interval.end, meters: meters, steps: steps))
        }
        return walks
    }
}
