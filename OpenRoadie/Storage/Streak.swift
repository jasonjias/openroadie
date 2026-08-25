import Foundation

/// The positive flip side of speed alerts: consecutive completed drives with
/// zero recorded events — no hard braking or acceleration, no limit
/// crossings. Tesla's strike system takes features away; OpenRoadie gives
/// you something you'd rather not lose.
enum Streak {
    struct Summary: Equatable {
        var current: Int
        var best: Int
    }

    /// Pure core, testable without SwiftData: trip time spans (any order)
    /// and event timestamps. A trip is clean when no event falls inside it.
    static func compute(spans: [(start: Date, end: Date)], eventTimes: [Date]) -> Summary {
        let ordered = spans.sorted { $0.start < $1.start }
        var current = 0
        var best = 0
        for span in ordered {
            let clean = !eventTimes.contains { $0 >= span.start && $0 <= span.end }
            current = clean ? current + 1 : 0
            best = max(best, current)
        }
        return Summary(current: current, best: best)
    }

    @MainActor
    static func compute(trips: [Trip], events: [DriveEvent]) -> Summary {
        compute(
            spans: trips.compactMap { trip in
                trip.endDate.map { (start: trip.startDate, end: $0) }
            },
            eventTimes: events.map(\.timestamp)
        )
    }
}
