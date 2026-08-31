import Foundation
import Testing
@testable import OpenRoadie

struct ParkDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)

    /// Gets a detector past the "has it ever moved?" gate.
    private func rolling(from t0: Date) -> ParkDetector {
        var detector = ParkDetector()
        detector.reset(at: t0)
        _ = detector.process(speedMps: 20, stationary: false, at: t0)
        return detector
    }

    @Test func drivingNeverPausesOrEndsTheDrive() {
        var detector = rolling(from: t0)
        for minute in 0...40 {
            let decision = detector.process(speedMps: 20, stationary: false, at: t0 + Double(minute) * 60)
            #expect(decision == .unchanged)
        }
    }

    /// The field bug this whole change exists for: a gas stop used to end
    /// and save the drive, and (in Automatic mode) a second drive started
    /// moments later. Now it pauses and the same drive continues.
    @Test func aGasStopPausesAndResumesOneDrive() {
        var detector = rolling(from: t0)
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 120) == .unchanged)
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 301) == .paused)
        #expect(detector.isPaused)
        // Still paused, not ended, eight minutes in.
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 480) == .unchanged)
        #expect(detector.process(speedMps: 12, stationary: false, at: t0 + 500) == .resumed)
        #expect(!detector.isPaused)
    }

    @Test func pauseIsReportedOnlyOnce() {
        var detector = rolling(from: t0)
        let first = detector.process(speedMps: 0, stationary: true, at: t0 + 320)
        let second = detector.process(speedMps: 0, stationary: true, at: t0 + 380)
        #expect(first == .paused)
        #expect(second == .unchanged)
    }

    @Test func settledLongEnoughEndsTheDrive() {
        var detector = rolling(from: t0)
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 900) == .paused)
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 1_400) == .unchanged)
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 1_501) == .ended)
    }

    /// The field bug: some fixes never set the stationary flag, so the old
    /// rule waited forever. Speed alone must be enough.
    @Test func zeroSpeedCountsEvenWithoutTheStationaryFlag() {
        var detector = rolling(from: t0)
        #expect(detector.process(speedMps: 0.2, stationary: false, at: t0 + 400) == .paused)
        #expect(detector.process(speedMps: 0.2, stationary: false, at: t0 + 1_600) == .ended)
    }

    @Test func trafficLightsChangeNothing() {
        var detector = rolling(from: t0)
        let atLight = detector.process(speedMps: 0, stationary: true, at: t0 + 120)
        let movingAgain = detector.process(speedMps: 15, stationary: false, at: t0 + 150)
        let stoppedAgain = detector.process(speedMps: 0, stationary: true, at: t0 + 400)
        #expect(atLight == .unchanged)
        #expect(movingAgain == .unchanged)
        #expect(stoppedAgain == .unchanged) // only ~4 min into THIS stop
    }

    /// Tapping Start Drive and sitting in the driveway must not burn the
    /// stop clock — that used to end the drive before it began. It closes
    /// itself out only after the never-moved timeout.
    @Test func aDriveThatNeverMovesGetsAGracePeriodThenCloses() {
        var detector = ParkDetector()
        detector.reset(at: t0)
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 301) == .unchanged)
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 600) == .unchanged)
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 901) == .ended)
    }

    @Test func pullingOutLateStartsTheStopClockFromThere() {
        var detector = ParkDetector()
        detector.reset(at: t0)
        // Eight minutes loading the car, then actually driving.
        _ = detector.process(speedMps: 0, stationary: true, at: t0 + 480)
        #expect(detector.process(speedMps: 18, stationary: false, at: t0 + 500) == .unchanged)
        // The stop clock now runs from t0+500, not from the start.
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 700) == .unchanged)
        #expect(detector.process(speedMps: 0, stationary: true, at: t0 + 810) == .paused)
    }

    @Test func fixesWithoutSpeedStayNeutral() {
        var detector = ParkDetector()
        detector.reset(at: t0)
        // No speed reading and not flagged stationary: treated as moving,
        // never as a silent slide toward ending the drive.
        #expect(detector.process(speedMps: nil, stationary: false, at: t0 + 600) == .unchanged)
        #expect(detector.lastMovingAt == t0 + 600)
    }
}

/// Reliability additions after the field report that auto-start "doesn't
/// seem reliable".
struct DriveDetectorFastPathTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)

    @Test func freewaySpeedConfirmsWithoutAnyMotionLabel() {
        var detector = DriveDetector()
        // No automotive activity ever reported — a phone that classifies
        // badly, or an activity update that simply hasn't arrived yet.
        let event = detector.processSpeed(30, at: t0) // ~67 mph
        #expect(event == .driveConfirmed)
    }

    @Test func walkingPaceStillNeedsTheMotionEvidence() {
        var detector = DriveDetector()
        let event = detector.processSpeed(1.5, at: t0) // ~3 mph
        #expect(event == nil)
    }

    @Test func fastPathFiresOnlyOnce() {
        var detector = DriveDetector()
        let first = detector.processSpeed(30, at: t0)
        let second = detector.processSpeed(31, at: t0 + 5)
        #expect(first == .driveConfirmed)
        #expect(second == nil)
    }
}
