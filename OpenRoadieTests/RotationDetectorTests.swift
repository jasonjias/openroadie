import Foundation
import Testing
@testable import OpenRoadie

struct CorneringDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func sustainedHardCornerFires() {
        var d = CorneringDetector()
        // 0.5 rad/s at 20 m/s ≈ 1.02g lateral — well past threshold.
        #expect(d.process(yawRate: 0.5, speedMps: 20, at: t0) == nil)
        #expect(d.process(yawRate: 0.5, speedMps: 20, at: t0 + 0.1) == nil)
        #expect(d.process(yawRate: 0.5, speedMps: 20, at: t0 + 0.2) == nil)
        let peak = d.process(yawRate: 0.5, speedMps: 20, at: t0 + 0.3)
        #expect(peak != nil && peak! > 1.0)
    }

    @Test func slowSpeedTurnNeverFires() {
        var d = CorneringDetector()
        // Full-lock parking-lot turn: 1 rad/s at 3 m/s ≈ 0.31g — under.
        for i in 0..<20 {
            #expect(d.process(yawRate: 1.0, speedMps: 3, at: t0 + Double(i) * 0.1) == nil)
        }
    }

    @Test func firesOncePerBurstWithHoldOff() {
        var d = CorneringDetector()
        for i in 0..<4 { _ = d.process(yawRate: 0.5, speedMps: 20, at: t0 + Double(i) * 0.1) }
        // Still cornering — no second event.
        #expect(d.process(yawRate: 0.5, speedMps: 20, at: t0 + 0.5) == nil)
        // Straighten out, corner again within hold-off — still nothing.
        _ = d.process(yawRate: 0, speedMps: 20, at: t0 + 1)
        for i in 0..<5 {
            #expect(d.process(yawRate: 0.5, speedMps: 20, at: t0 + 2 + Double(i) * 0.1) == nil)
        }
    }
}

struct PhoneUseDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func sustainedHandlingFires() {
        var d = PhoneUseDetector()
        #expect(d.process(nonYawRotation: 1.2, at: t0) == nil)
        #expect(d.process(nonYawRotation: 1.2, at: t0 + 0.6) == nil)
        let duration = d.process(nonYawRotation: 1.2, at: t0 + 1.3)
        #expect(duration != nil && duration! >= 1.2)
    }

    @Test func briefBumpDoesNotFire() {
        var d = PhoneUseDetector()
        #expect(d.process(nonYawRotation: 2.0, at: t0) == nil)
        #expect(d.process(nonYawRotation: 2.0, at: t0 + 0.5) == nil)
        // Calm again before 1.2s — burst resets.
        #expect(d.process(nonYawRotation: 0.1, at: t0 + 0.8) == nil)
        #expect(d.process(nonYawRotation: 2.0, at: t0 + 1.0) == nil)
        #expect(d.process(nonYawRotation: 2.0, at: t0 + 1.9) == nil)
    }

    @Test func firesOncePerBurst() {
        var d = PhoneUseDetector()
        _ = d.process(nonYawRotation: 1.5, at: t0)
        #expect(d.process(nonYawRotation: 1.5, at: t0 + 1.3) != nil)
        #expect(d.process(nonYawRotation: 1.5, at: t0 + 2.0) == nil)
    }
}
