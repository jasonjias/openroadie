import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct DayStatsTests {
    private func trip(startOffset: TimeInterval, duration: TimeInterval, meters: Double, maxMps: Double?, from reference: Date) -> Trip {
        let trip = Trip(startDate: reference.addingTimeInterval(startOffset))
        trip.endDate = reference.addingTimeInterval(startOffset + duration)
        trip.distance = meters
        trip.maxSpeed = maxMps
        return trip
    }

    @Test func aggregatesOnlyTheSelectedDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_724_500_000))

        let trips = [
            trip(startOffset: 8 * 3600, duration: 1200, meters: 16093, maxMps: 29.06, from: day),   // today: 10 mi, 65 mph
            trip(startOffset: 18 * 3600, duration: 600, meters: 3219, maxMps: 15.6, from: day),     // today: 2 mi, 35 mph
            trip(startOffset: -10 * 3600, duration: 900, meters: 8047, maxMps: 20, from: day),      // yesterday
        ]
        let events = [
            DriveEvent(kind: "hardBraking", peakG: 0.4, coordinate: nil, speedMph: 40,
                       timestamp: day.addingTimeInterval(8 * 3600 + 300)),
            DriveEvent(kind: "hardBraking", peakG: 0.5, coordinate: nil, speedMph: 30,
                       timestamp: day.addingTimeInterval(-9 * 3600)), // yesterday's
        ]

        let stats = DayStats.compute(trips: trips, events: events, on: day, calendar: calendar)
        #expect(stats.tripCount == 2)
        #expect(abs(stats.miles - 12) < 0.01)
        #expect(stats.duration == 1800)
        #expect(stats.maxSpeedMph == 65)
        #expect(stats.hardEvents == 1)
        #expect(stats.score == 92) // 100 - 8
    }

    @Test func noDrivingMeansNoScore() {
        let stats = DayStats.compute(trips: [], events: [], on: .now)
        #expect(stats.score == nil)
        #expect(stats.tripCount == 0)
    }

    @Test func scoreFloorsAtZero() {
        var stats = DayStats()
        stats.tripCount = 1
        stats.hardEvents = 20
        #expect(stats.score == 0)
    }

    @Test func cleanDayScoresPerfect() {
        var stats = DayStats()
        stats.tripCount = 3
        stats.hardEvents = 0
        #expect(stats.score == 100)
    }
}
