import Foundation
import Testing
@testable import OpenRoadie

private let degreesPerMeter = 1 / 111_320.0

private func point(metersNorth: Double, at seconds: TimeInterval, from t0: Date) -> RouteSample {
    RouteSample(
        timestamp: t0 + seconds,
        coordinate: Coordinate(latitude: 37.0 + metersNorth * degreesPerMeter, longitude: -122.0)
    )
}

/// A run of points covering `meters` over `seconds`, sampled every 10 s —
/// roughly what the tracker records while actually driving.
private func leg(
    meters: Double, seconds: TimeInterval, startingAt offset: Double, from clock: TimeInterval, base t0: Date
) -> [RouteSample] {
    let steps = max(1, Int(seconds / 10))
    return (1...steps).map { step in
        let fraction = Double(step) / Double(steps)
        return point(metersNorth: offset + meters * fraction, at: clock + seconds * fraction, from: t0)
    }
}

struct TripSegmenterTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)

    @Test func anUninterruptedDriveIsOneLeg() {
        let samples = [point(metersNorth: 0, at: 0, from: t0)]
            + leg(meters: 8_000, seconds: 600, startingAt: 0, from: 0, base: t0)
        let legs = TripSegmenter.legs(samples)
        #expect(legs.count == 1)
        #expect(legs[0].stoppedBefore == nil)
    }

    /// The payoff of recording through stops: one stored drive, shown as
    /// the two runs it really was.
    @Test func aLongStopSplitsTheDriveIntoLegs() {
        var samples = [point(metersNorth: 0, at: 0, from: t0)]
        samples += leg(meters: 8_000, seconds: 600, startingAt: 0, from: 0, base: t0)
        // 40 minutes parked, then the drive home.
        samples += leg(meters: 8_000, seconds: 600, startingAt: 8_000, from: 3_000, base: t0)
        let legs = TripSegmenter.legs(samples)
        #expect(legs.count == 2)
        #expect(legs[0].stoppedBefore == nil)
        #expect((legs[1].stoppedBefore ?? 0) > 2_000)
        #expect(abs(legs[0].meters - 8_000) < 200)
        #expect(abs(legs[1].meters - 8_000) < 200)
    }

    @Test func aShortStopDoesNotSplitAnything() {
        var samples = [point(metersNorth: 0, at: 0, from: t0)]
        samples += leg(meters: 5_000, seconds: 400, startingAt: 0, from: 0, base: t0)
        // Five minutes at a drive-thru window — under the split threshold.
        samples += leg(meters: 5_000, seconds: 400, startingAt: 5_000, from: 700, base: t0)
        #expect(TripSegmenter.legs(samples).count == 1)
    }

    /// A re-park inside the stop is not a leg of the drive. Its time folds
    /// into the stop, so the surviving legs still account for the whole gap.
    @Test func aParkingLotShuffleFoldsIntoTheStop() {
        var samples = [point(metersNorth: 0, at: 0, from: t0)]
        samples += leg(meters: 8_000, seconds: 600, startingAt: 0, from: 0, base: t0)
        // 20 min later: 60 meters of re-parking, then another long stop.
        samples += leg(meters: 60, seconds: 40, startingAt: 8_000, from: 1_800, base: t0)
        samples += leg(meters: 8_000, seconds: 600, startingAt: 8_060, from: 3_600, base: t0)
        let legs = TripSegmenter.legs(samples)
        #expect(legs.count == 2)
        // The dropped shuffle's time is carried, not lost: the reported
        // stop spans from the end of leg 1 to the start of leg 2.
        let gap = legs[1].start.timeIntervalSince(legs[0].end)
        #expect(abs((legs[1].stoppedBefore ?? 0) - gap) < 1)
    }

    @Test func aRouteTooShortToSegmentReturnsNothing() {
        #expect(TripSegmenter.legs([]).isEmpty)
        #expect(TripSegmenter.legs([point(metersNorth: 0, at: 0, from: t0)]).isEmpty)
    }

    @Test func legsNeverOverlapAndStayInOrder() {
        var samples = [point(metersNorth: 0, at: 0, from: t0)]
        samples += leg(meters: 6_000, seconds: 500, startingAt: 0, from: 0, base: t0)
        samples += leg(meters: 6_000, seconds: 500, startingAt: 6_000, from: 2_000, base: t0)
        samples += leg(meters: 6_000, seconds: 500, startingAt: 12_000, from: 4_000, base: t0)
        let legs = TripSegmenter.legs(samples)
        #expect(legs.count == 3)
        for (earlier, later) in zip(legs, legs.dropFirst()) {
            #expect(earlier.range.upperBound < later.range.lowerBound)
            #expect(earlier.end <= later.start)
        }
    }
}
