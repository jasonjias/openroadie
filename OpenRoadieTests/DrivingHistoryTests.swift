import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct DrivingHistoryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func trip(day: Int, hour: Int, minutes: Double, miles: Double, maxMps: Double? = nil) -> Trip {
        let base = Date(timeIntervalSince1970: 1_724_500_000)
        let start = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: base))!
            .addingTimeInterval(TimeInterval(hour) * 3600)
        let trip = Trip(startDate: start)
        trip.endDate = start.addingTimeInterval(minutes * 60)
        trip.distance = miles * 1609.344
        trip.maxSpeed = maxMps
        return trip
    }

    @Test func aggregatesAcrossDays() {
        let trips = [
            trip(day: 0, hour: 6, minutes: 30, miles: 10, maxMps: 29),   // 6 AM, 30 min
            trip(day: 0, hour: 22, minutes: 60, miles: 30, maxMps: 33),  // same day, ends 11 PM
            trip(day: 1, hour: 9, minutes: 15, miles: 2),                // second day
            Trip(startDate: .now),                                       // unfinished: ignored
        ]
        let history = DrivingHistory.compute(trips: trips, calendar: calendar)
        #expect(history.drives == 3)
        #expect(history.daysDriven == 2)
        #expect(abs(history.totalMiles - 42) < 0.01)
        #expect(history.totalSeconds == 105 * 60)
        #expect(history.maxSpeedMps == 33)
        #expect(abs(history.averageMilesPerDay - 21) < 0.01)
        #expect(history.averageSecondsPerDay == 52.5 * 60)
    }

    @Test func recordsPickTheExtremes() {
        let trips = [
            trip(day: 0, hour: 6, minutes: 30, miles: 10),   // 3 min/mi
            trip(day: 0, hour: 22, minutes: 60, miles: 5),   // 12 min/mi — slowest
            trip(day: 1, hour: 9, minutes: 90, miles: 60),   // longest both ways
            trip(day: 1, hour: 12, minutes: 20, miles: 0.5), // sub-mile: no pace
        ]
        let history = DrivingHistory.compute(trips: trips, calendar: calendar)
        #expect(history.longestMiles == 60)
        #expect(history.longestSeconds == 90 * 60)
        #expect(abs((history.slowestPaceSecondsPerMile ?? 0) - 720) < 0.01)
        #expect(history.earliestStartMinute == 6 * 60)
        #expect(history.latestEndMinute == 23 * 60)
    }

    @Test func emptyHistoryIsAllZeros() {
        let history = DrivingHistory.compute(trips: [], calendar: calendar)
        #expect(history.drives == 0)
        #expect(history.daysDriven == 0)
        #expect(history.averageMph == nil)
        #expect(history.slowestPaceSecondsPerMile == nil)
        #expect(history.earliestStartMinute == nil)
    }
}
