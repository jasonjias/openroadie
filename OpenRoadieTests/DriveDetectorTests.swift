import Foundation
import Testing
@testable import OpenRoadie

struct DriveDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func sustainedAutomotiveBecomesLikely() {
        var detector = DriveDetector()
        #expect(detector.processMotion(automotive: true, otherActivity: false, at: t0) == nil)
        #expect(detector.processMotion(automotive: true, otherActivity: false, at: t0 + 10) == nil)
        #expect(detector.processMotion(automotive: true, otherActivity: false, at: t0 + 21) == .driveLikely)
        #expect(detector.state == .possibleDrive(since: t0 + 21))
    }

    @Test func roadSpeedConfirmsALikelyDrive() {
        var detector = DriveDetector()
        _ = detector.processMotion(automotive: true, otherActivity: false, at: t0)
        _ = detector.processMotion(automotive: true, otherActivity: false, at: t0 + 25)
        #expect(detector.processSpeed(2.0, at: t0 + 30) == nil)   // parking-lot creep
        #expect(detector.processSpeed(nil, at: t0 + 32) == nil)   // GPS blind
        #expect(detector.processSpeed(8.0, at: t0 + 35) == .driveConfirmed)
        #expect(detector.state == .confirmed)
    }

    @Test func speedAloneNeverConfirms() {
        // A train ride looks fast to GPS but never passed the automotive gate.
        var detector = DriveDetector()
        #expect(detector.processSpeed(30, at: t0) == nil)
        #expect(detector.state == .idle)
    }

    @Test func walkingCancelsEverything() {
        var detector = DriveDetector()
        _ = detector.processMotion(automotive: true, otherActivity: false, at: t0)
        _ = detector.processMotion(automotive: true, otherActivity: false, at: t0 + 25)
        #expect(detector.state != .idle)
        _ = detector.processMotion(automotive: false, otherActivity: true, at: t0 + 30)
        #expect(detector.state == .idle)
        #expect(detector.processSpeed(20, at: t0 + 31) == nil)
    }

    @Test func stationaryAtALightDoesNotCancel() {
        var detector = DriveDetector()
        _ = detector.processMotion(automotive: true, otherActivity: false, at: t0)
        // Red light: not automotive, but not walking either.
        _ = detector.processMotion(automotive: false, otherActivity: false, at: t0 + 10)
        #expect(detector.processMotion(automotive: true, otherActivity: false, at: t0 + 21) == .driveLikely)
    }

    @Test func briefAutomotiveBlipNeverTriggers() {
        var detector = DriveDetector()
        #expect(detector.processMotion(automotive: true, otherActivity: false, at: t0) == nil)
        #expect(detector.processMotion(automotive: true, otherActivity: false, at: t0 + 5) == nil)
        #expect(detector.state == .idle)
    }

    @Test func unconfirmedPossibleDriveTimesOut() {
        var detector = DriveDetector()
        _ = detector.processMotion(automotive: true, otherActivity: false, at: t0)
        _ = detector.processMotion(automotive: true, otherActivity: false, at: t0 + 25)
        // Engine on, parked, for four minutes: not a drive.
        #expect(detector.processSpeed(1.0, at: t0 + 250) == nil)
        #expect(detector.state == .idle)
    }

    @Test func resetReturnsToIdle() {
        var detector = DriveDetector()
        _ = detector.processMotion(automotive: true, otherActivity: false, at: t0)
        _ = detector.processMotion(automotive: true, otherActivity: false, at: t0 + 25)
        _ = detector.processSpeed(10, at: t0 + 30)
        #expect(detector.state == .confirmed)
        detector.reset()
        #expect(detector.state == .idle)
    }
}
