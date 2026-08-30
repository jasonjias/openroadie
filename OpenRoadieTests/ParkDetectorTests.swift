import Foundation
import Testing
@testable import OpenRoadie

struct ParkDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)

    @Test func drivingNeverEndsTheDrive() {
        var detector = ParkDetector()
        detector.reset(at: t0)
        for minute in 0...20 {
            let ended = detector.process(speedMps: 20, stationary: false, at: t0 + Double(minute) * 60)
            #expect(!ended)
        }
    }

    @Test func stoppedLongEnoughEndsTheDrive() {
        var detector = ParkDetector()
        detector.reset(at: t0)
        let atOneMinute = detector.process(speedMps: 0, stationary: true, at: t0 + 60)
        let atFourMinutes = detector.process(speedMps: 0, stationary: true, at: t0 + 240)
        let atSixMinutes = detector.process(speedMps: 0, stationary: true, at: t0 + 361)
        #expect(!atOneMinute)
        #expect(!atFourMinutes)
        #expect(atSixMinutes)
    }

    /// The field bug: some fixes never set the stationary flag, so the old
    /// rule waited forever. Speed alone must be enough.
    @Test func zeroSpeedCountsEvenWithoutTheStationaryFlag() {
        var detector = ParkDetector()
        detector.reset(at: t0)
        let early = detector.process(speedMps: 0.2, stationary: false, at: t0 + 60)
        let late = detector.process(speedMps: 0.2, stationary: false, at: t0 + 400)
        #expect(!early)
        #expect(late)
    }

    @Test func trafficLightsDoNotEndTheDrive() {
        var detector = ParkDetector()
        detector.reset(at: t0)
        // Two minutes at a light, then moving again: the timer restarts.
        let atLight = detector.process(speedMps: 0, stationary: true, at: t0 + 120)
        let movingAgain = detector.process(speedMps: 15, stationary: false, at: t0 + 150)
        let stoppedAgain = detector.process(speedMps: 0, stationary: true, at: t0 + 400)
        let parked = detector.process(speedMps: 0, stationary: true, at: t0 + 460)
        #expect(!atLight)
        #expect(!movingAgain)
        #expect(!stoppedAgain)   // only ~4 min into THIS stop
        #expect(parked)
    }

    @Test func fixesWithoutSpeedStayNeutral() {
        var detector = ParkDetector()
        detector.reset(at: t0)
        // No speed reading and not flagged stationary: treated as moving,
        // never as a silent slide toward ending the drive.
        let ended = detector.process(speedMps: nil, stationary: false, at: t0 + 600)
        #expect(!ended)
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
