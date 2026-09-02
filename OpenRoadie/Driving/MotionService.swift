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

/// Harsh-cornering detection: lateral g estimated from yaw rate × speed
/// (a = v·ω), sustained past threshold. Same fire-once/hold-off shape as
/// GForceDetector. Pure logic, unit-tested.
struct CorneringDetector {
    /// Lateral acceleration above this is a harsh corner (~0.35g is where
    /// passengers grab the door handle).
    static let thresholdG: Double = 0.35
    static let minConsecutive = 4      // ~0.4s at 10Hz — filters jitter
    static let holdOff: TimeInterval = 5

    private var consecutive = 0
    private var peakG: Double = 0
    private var lastEventAt: Date?
    private var firedThisBurst = false

    /// Feed yaw rate (rad/s) and speed (m/s); returns peak lateral g when
    /// a harsh corner fires. Low speed naturally suppresses events (v·ω).
    mutating func process(yawRate: Double, speedMps: Double, at date: Date) -> Double? {
        let lateralG = abs(yawRate) * speedMps / 9.81
        guard lateralG >= Self.thresholdG else {
            consecutive = 0
            peakG = 0
            firedThisBurst = false
            return nil
        }
        consecutive += 1
        peakG = max(peakG, lateralG)
        guard !firedThisBurst, consecutive >= Self.minConsecutive else { return nil }
        if let last = lastEventAt, date.timeIntervalSince(last) < Self.holdOff {
            return nil
        }
        lastEventAt = date
        firedThisBurst = true
        return peakG
    }
}

/// Phone-handling detection: picking up and manipulating the phone rotates
/// it about pitch/roll axes in a way a mounted (or pocketed) phone during
/// normal driving does not — vehicle turns rotate the phone about GRAVITY
/// only. Sustained non-yaw rotation while at speed = handling. Pure logic.
struct PhoneUseDetector {
    /// Non-yaw rotation (rad/s) above this looks like hands on the phone.
    static let threshold: Double = 0.8
    /// Sustained this long before it counts (filters bumps and mounts).
    static let minDuration: TimeInterval = 1.2
    static let holdOff: TimeInterval = 10

    private var burstStart: Date?
    private var lastEventAt: Date?
    private var firedThisBurst = false

    /// Feed non-yaw rotation magnitude; returns the burst duration when a
    /// handling event fires. Caller gates on vehicle speed.
    mutating func process(nonYawRotation: Double, at date: Date) -> TimeInterval? {
        guard nonYawRotation >= Self.threshold else {
            burstStart = nil
            firedThisBurst = false
            return nil
        }
        let start = burstStart ?? date
        burstStart = start
        let duration = date.timeIntervalSince(start)
        guard !firedThisBurst, duration >= Self.minDuration else { return nil }
        if let last = lastEventAt, date.timeIntervalSince(last) < Self.holdOff {
            return nil
        }
        lastEventAt = date
        firedThisBurst = true
        return duration
    }
}

/// Streams device motion during a drive and surfaces hard-maneuver events.
/// Accelerometer data never leaves this class except as discrete events.
@MainActor
final class MotionService {
    private let manager = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private var detector = GForceDetector()

    /// Fired with the event's peak g-force.
    var onHardManeuver: ((Double) -> Void)?
    /// Fired every sample with (yaw rate about gravity, non-yaw rotation
    /// magnitude) — the raw material for cornering, phone-use, and the
    /// drive scene's lean. Values only; motion data stays here.
    var onRotationSample: ((Double, Double) -> Void)?
    /// Fired when Core Motion's activity classification flips between
    /// on-foot (walking/running) and anything else. The end-of-drive signal:
    /// a walking driver is a parked car.
    var onWalkingChange: ((Bool) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        startActivity()
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

    private func startActivity() {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            MainActor.assumeIsolated {
                self?.onWalkingChange?(activity.walking || activity.running)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        activityManager.stopActivityUpdates()
    }

    private func process(_ motion: CMDeviceMotion) {
        let acceleration = motion.userAcceleration
        let magnitude = (acceleration.x * acceleration.x
            + acceleration.y * acceleration.y
            + acceleration.z * acceleration.z).squareRoot()
        if let peak = detector.process(magnitudeG: magnitude, at: .now) {
            onHardManeuver?(peak)
        }

        // Split rotation into yaw-about-gravity (vehicle turning) and the
        // rest (phone being handled) — orientation-independent.
        let g = motion.gravity
        let gMag = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
        let r = motion.rotationRate
        let total = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        var yaw = 0.0
        if gMag > 0.5 {
            yaw = (r.x * g.x + r.y * g.y + r.z * g.z) / gMag
        }
        let nonYaw = max(0, total * total - yaw * yaw).squareRoot()
        onRotationSample?(yaw, nonYaw)
    }
}
