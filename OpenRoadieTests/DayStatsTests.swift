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
        #expect(stats.score == 90) // 100 - 10
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

    @Test func overspeedCrossingsCostPoints() {
        var stats = DayStats()
        stats.tripCount = 1
        stats.overLimitCrossings = 2   // informational — the chime tier costs nothing
        stats.wellOverCrossings = 1    // -5
        stats.hardEvents = 1           // -10
        #expect(stats.score == 85)
    }

    @Test func ordinaryFlowOfTrafficDayScoresWell() {
        // Field calibration: 13 small crossings + 4 genuinely-over in an
        // afternoon of normal driving should read like Tesla's "fine",
        // not a single-digit shame score.
        var stats = DayStats()
        stats.tripCount = 4
        stats.overLimitCrossings = 13
        stats.wellOverCrossings = 4
        #expect(stats.score == 80)
    }

    @Test func stationaryGSpikesAreNotHardEvents() {
        // "Hard acceleration, 0 mph, 1.23 g" = picking up the phone.
        let day = Calendar.current.startOfDay(for: .now)
        let trip = Trip(startDate: day.addingTimeInterval(3600))
        trip.endDate = day.addingTimeInterval(4000)
        trip.distance = 1609
        let events = [
            DriveEvent(kind: "hardAcceleration", peakG: 1.23, coordinate: nil, speedMph: 0, timestamp: day.addingTimeInterval(3700)),
            DriveEvent(kind: "hardBraking", peakG: 0.5, coordinate: nil, speedMph: 3, timestamp: day.addingTimeInterval(3750)),
            DriveEvent(kind: "hardBraking", peakG: 0.4, coordinate: nil, speedMph: 30, timestamp: day.addingTimeInterval(3800)),
        ]
        let stats = DayStats.compute(trips: [trip], events: events, on: day)
        #expect(stats.hardEvents == 1)         // only the 30 mph one is real
        #expect(stats.score == 90)
    }

    @Test func countsEventKindsSeparately() {
        let day = Calendar.current.startOfDay(for: .now)
        let trip = Trip(startDate: day.addingTimeInterval(3600))
        trip.endDate = day.addingTimeInterval(4000)
        trip.distance = 1609
        let events = [
            DriveEvent(kind: "overLimit", peakG: 0, coordinate: nil, speedMph: 40, timestamp: day.addingTimeInterval(3700)),
            DriveEvent(kind: "wellOverLimit", peakG: 0, coordinate: nil, speedMph: 50, timestamp: day.addingTimeInterval(3800)),
            DriveEvent(kind: "hardBraking", peakG: 0.4, coordinate: nil, speedMph: 30, timestamp: day.addingTimeInterval(3900)),
        ]
        let stats = DayStats.compute(trips: [trip], events: events, on: day)
        #expect(stats.overLimitCrossings == 1)
        #expect(stats.wellOverCrossings == 1)
        #expect(stats.hardEvents == 1)
        #expect(stats.hardBraking == 1)
        #expect(stats.hardAcceleration == 0)
        #expect(stats.score == 100 - 5 - 10)
    }
}

@MainActor
struct RelativeColoringTests {
    @Test func mapsDeltasToBands() {
        let limit = 29.06 // 65 mph in m/s
        // Unknown limit or speed → gray band 0.
        #expect(RouteColoring.relativeBandIndex(speedMps: 30, limitMps: nil) == 0)
        #expect(RouteColoring.relativeBandIndex(speedMps: nil, limitMps: limit) == 0)
        // 50 mph in a 65: well under.
        #expect(RouteColoring.relativeBandIndex(speedMps: 22.35, limitMps: limit) == 1)
        // 65 in a 65: at limit.
        #expect(RouteColoring.relativeBandIndex(speedMps: 29.06, limitMps: limit) == 2)
        // 68 in a 65: +1–5.
        #expect(RouteColoring.relativeBandIndex(speedMps: 30.4, limitMps: limit) == 3)
        // 72 in a 65: +5–10.
        #expect(RouteColoring.relativeBandIndex(speedMps: 32.2, limitMps: limit) == 4)
        // 80 in a 65: +10 over.
        #expect(RouteColoring.relativeBandIndex(speedMps: 35.8, limitMps: limit) == 5)
    }

    @Test func relativeRunsGroupAndCoverEverything() {
        let limit: Double? = 29.06
        // Well under → +1–5 over → +10 over, two points each.
        let speeds: [Double?] = [22, 22, 30.5, 30.5, 35.8, 35.8]
        let runs = RouteColoring.relativeRuns(speeds: speeds, limits: Array(repeating: limit, count: 6))
        #expect(runs.first?.pointIndices.lowerBound == 0)
        #expect(runs.last?.pointIndices.upperBound == 5)
        #expect(runs.count == 3)
        #expect(runs.map(\.bandIndex) == [1, 3, 5])
    }
}
