import Foundation
import Testing
@testable import OpenRoadie

struct PracticeMathTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: day, hour: hour, minute: minute))!
    }

    @Test func daytimeDriveHasNoNight() {
        let seconds = PracticeMath.nightSeconds(start: date(10), end: date(11, 30), calendar: calendar)
        #expect(seconds == 0)
    }

    @Test func fullyNightDriveCountsWhole() {
        let seconds = PracticeMath.nightSeconds(start: date(21), end: date(22), calendar: calendar)
        #expect(seconds == 3600)
    }

    @Test func eveningDriveCountsOnlyThePartAfterEight() {
        let seconds = PracticeMath.nightSeconds(start: date(19, 30), end: date(20, 30), calendar: calendar)
        #expect(seconds == 1800)
    }

    @Test func earlyMorningCountsBeforeSix() {
        let seconds = PracticeMath.nightSeconds(start: date(5), end: date(7), calendar: calendar)
        #expect(seconds == 3600)
    }

    @Test func crossMidnightCountsBothSides() {
        let start = date(23, day: 10)
        let end = date(1, day: 11)
        let seconds = PracticeMath.nightSeconds(start: start, end: end, calendar: calendar)
        #expect(seconds == 7200)
    }
}
