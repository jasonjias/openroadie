import Foundation
import Testing
@testable import OpenRoadie

/// At latitude 37°, one degree of latitude is ~111,320 m — so a route can be
/// built by walking north a known number of meters.
private let metersPerDegree = 111_320.0

private func sample(metersNorth: Double, at seconds: TimeInterval, from t0: Date) -> RouteSample {
    RouteSample(
        timestamp: t0 + seconds,
        coordinate: Coordinate(latitude: 37.0 + metersNorth / metersPerDegree, longitude: -122.0)
    )
}

/// Builds a route from (meters covered, seconds taken) legs, walking north.
private func route(_ steps: [(meters: Double, seconds: TimeInterval)], from t0: Date) -> [RouteSample] {
    var samples = [sample(metersNorth: 0, at: 0, from: t0)]
    var meters = 0.0
    var seconds = 0.0
    for step in steps {
        meters += step.meters
        seconds += step.seconds
        samples.append(sample(metersNorth: meters, at: seconds, from: t0))
    }
    return samples
}

struct PaceBandsTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)

    @Test func intervalsLandInTheRightBands() {
        #expect(PaceBands.band(meters: 5, seconds: 60) == .stopped)        // 0.08 m/s
        #expect(PaceBands.band(meters: 200, seconds: 60) == .crawling)     // 3.3 m/s ≈ 7 mph
        #expect(PaceBands.band(meters: 600, seconds: 60) == .city)         // 10 m/s ≈ 22 mph
        #expect(PaceBands.band(meters: 1_500, seconds: 60) == .highway)    // 25 m/s ≈ 56 mph
    }

    /// The rule this whole breakdown exists to keep: the bands partition the
    /// drive's span exactly. A figure that won't tie out is a bug hunt, not
    /// a caption.
    @Test func bandsTieOutToTheDriveSpan() {
        let samples = route([
            (meters: 1_400, seconds: 60),   // highway
            (meters: 8, seconds: 240),      // stopped
            (meters: 500, seconds: 60),     // city
            (meters: 120, seconds: 90),     // crawling
            (meters: 2, seconds: 600),      // stopped
        ], from: t0)
        let pace = PaceBands.compute(samples)
        let span = samples.last!.timestamp.timeIntervalSince(samples.first!.timestamp)
        #expect(abs(pace.total - span) < 0.001)
        #expect(abs(pace.total - 1_050) < 0.001)
    }

    /// A gap longer than any plausible stop is missing data, and gets its
    /// own band rather than being filed as "stopped" — an uncertain bucket
    /// is a real bucket.
    @Test func aLongGapIsUnrecordedNotStopped() {
        let samples = route([(meters: 40, seconds: 4_000)], from: t0)
        let pace = PaceBands.compute(samples)
        #expect(pace.seconds(.unknown) == 4_000)
        #expect(pace.seconds(.stopped) == 0)
        #expect(pace.slowSeconds == 0)
    }

    @Test func trafficIsTimeUnderFifteenNotASlowAverage() {
        // 20 minutes crawling, then a fast half hour: the average looks
        // fine, but 20 minutes of it went nowhere.
        let samples = route([
            (meters: 2_000, seconds: 1_200),   // 3.7 mph — crawling
            (meters: 40_000, seconds: 1_800),  // 50 mph — highway
        ], from: t0)
        let pace = PaceBands.compute(samples)
        #expect(PaceBands.isTrafficHeavy(pace))
        #expect(pace.slowSeconds == 1_200)
        #expect(abs(pace.slowShare - 0.4) < 0.01)
    }

    @Test func aCleanHighwayRunHasNoTrafficStory() {
        let samples = route([(meters: 40_000, seconds: 1_800)], from: t0)
        let pace = PaceBands.compute(samples)
        #expect(!PaceBands.isTrafficHeavy(pace))
        #expect(pace.presentBands == [.highway])
    }

    /// Moving average ignores the time the car sat still — the number that
    /// stays meaningful now that a drive survives its own stops.
    @Test func movingAverageExcludesStoppedTime() {
        let samples = route([
            (meters: 1_000, seconds: 100),  // 10 m/s, city
            (meters: 5, seconds: 900),      // stopped 15 min
        ], from: t0)
        let pace = PaceBands.compute(samples)
        #expect(pace.movingSeconds == 100)
        #expect(abs((pace.movingSpeed ?? 0) - 10) < 0.1)
        // The overall average over the same drive is ~1 m/s.
        #expect(pace.total == 1_000)
    }

    @Test func aRouteTooShortToMeasureIsEmptyNotInvented() {
        #expect(PaceBands.compute([]).total == 0)
        #expect(PaceBands.compute([sample(metersNorth: 0, at: 0, from: t0)]).total == 0)
        #expect(PaceBands.compute([]).presentBands.isEmpty)
    }

    @Test func bandIndicesCoverEveryPoint() {
        let samples = route([
            (meters: 1_400, seconds: 60),
            (meters: 5, seconds: 400),
        ], from: t0)
        let indices = PaceBands.bandIndices(samples)
        #expect(indices.count == samples.count)
        #expect(indices == [
            PaceBands.Band.highway.rawValue,
            PaceBands.Band.highway.rawValue,
            PaceBands.Band.stopped.rawValue,
        ])
    }
}
