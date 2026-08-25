import CoreMotion
import Foundation

/// Deterministic hard-maneuver detection from accelerometer magnitude:
/// a sustained burst above threshold fires once, then holds off so one
/// braking event can't machine-gun. Pure logic, unit-tested.
struct GForceDetector {
    /// User acceleration (gravity already removed) above this is "hard".
    static let thresholdG: Double = 0.35
    /// Samples in a row above threshold before an event fires (at 10 Hz,
    /// ~0.3 s — filters potholes and phone bumps).
    static let minConsecutive = 3
    /// Seconds before another event may fire.
    static let holdOff: TimeInterval = 4

    private var consecutive = 0
    private var peakG: Double = 0
    private var lastEventAt: Date?
    /// One event per burst: re-arms only after acceleration calms down.
    private var firedThisBurst = false

    /// Feed every motion sample; returns the event's peak g when one fires.
    mutating func process(magnitudeG: Double, at date: Date) -> Double? {
        guard magnitudeG >= Self.thresholdG else {
            consecutive = 0
            peakG = 0
            firedThisBurst = false
            return nil
        }
        consecutive += 1
        peakG = max(peakG, magnitudeG)
        guard !firedThisBurst, consecutive >= Self.minConsecutive else { return nil }
        if let last = lastEventAt, date.timeIntervalSince(last) < Self.holdOff {
            return nil
        }
        lastEventAt = date
        firedThisBurst = true
        return peakG
    }
}

/// Streams device motion during a drive and surfaces hard-maneuver events.
/// Accelerometer data never leaves this class except as discrete events.
@MainActor
final class MotionService {
    private let manager = CMMotionManager()
    private var detector = GForceDetector()

    /// Fired with the event's peak g-force.
    var onHardManeuver: ((Double) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        detector = GForceDetector()
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                self?.process(motion)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func process(_ motion: CMDeviceMotion) {
        let acceleration = motion.userAcceleration
        let magnitude = (acceleration.x * acceleration.x
            + acceleration.y * acceleration.y
            + acceleration.z * acceleration.z).squareRoot()
        if let peak = detector.process(magnitudeG: magnitude, at: .now) {
            onHardManeuver?(peak)
        }
    }
}
