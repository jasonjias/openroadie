import Foundation
import Testing
@testable import OpenRoadie

struct StreakTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func span(_ dayOffset: Int) -> (start: Date, end: Date) {
        let start = base.addingTimeInterval(Double(dayOffset) * 86_400)
        return (start: start, end: start.addingTimeInterval(1_800))
    }

    @Test func noTripsMeansNoStreak() {
        #expect(Streak.compute(spans: [], eventTimes: []) == .init(current: 0, best: 0))
    }

    @Test func allCleanDrivesCountUp() {
        let spans = [span(0), span(1), span(2)]
        #expect(Streak.compute(spans: spans, eventTimes: []) == .init(current: 3, best: 3))
    }

    @Test func eventInsideMostRecentDriveResetsCurrentButKeepsBest() {
        let spans = [span(0), span(1), span(2)]
        let eventInLast = span(2).start.addingTimeInterval(60)
        let result = Streak.compute(spans: spans, eventTimes: [eventInLast])
        #expect(result == .init(current: 0, best: 2))
    }

    @Test func eventInMiddleDriveLeavesTrailingRun() {
        let spans = [span(0), span(1), span(2), span(3)]
        let eventInSecond = span(1).start.addingTimeInterval(60)
        let result = Streak.compute(spans: spans, eventTimes: [eventInSecond])
        #expect(result == .init(current: 2, best: 2))
    }

    @Test func eventBetweenDrivesDoesNotBreakTheStreak() {
        let spans = [span(0), span(1)]
        let betweenDrives = span(0).end.addingTimeInterval(3_600)
        let result = Streak.compute(spans: spans, eventTimes: [betweenDrives])
        #expect(result == .init(current: 2, best: 2))
    }

    @Test func unorderedSpansAreSortedBeforeCounting() {
        let spans = [span(2), span(0), span(1)]
        let eventInFirst = span(0).start.addingTimeInterval(60)
        let result = Streak.compute(spans: spans, eventTimes: [eventInFirst])
        #expect(result == .init(current: 2, best: 2))
    }
}
