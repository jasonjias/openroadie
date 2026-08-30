import Foundation

/// Decides when a drive has ended, from telemetry alone.
///
/// The old rule trusted CoreLocation's `stationary` flag and waited ten
/// minutes; in the field that meant drives that never closed themselves
/// (the flag isn't always set) or closed long after the driver walked
/// away. This watches actual speed as well, so "parked" means the car
/// genuinely stopped moving — and it says so within a few minutes.
///
/// Pure and deterministic: every decision is a function of the samples
/// fed in and the clock passed with them.
struct ParkDetector: Equatable {
    struct Config: Equatable {
        /// Below this (m/s ≈ 3 mph) the vehicle isn't going anywhere;
        /// above it, GPS noise while stopped can't fake motion.
        var movingSpeed: Double = 1.4
        /// Continuously stopped this long → the drive is over.
        var parkedFor: TimeInterval = 300
    }

    var config = Config()

    /// Last moment the vehicle was demonstrably moving.
    private(set) var lastMovingAt: Date?

    /// Feed every telemetry update; returns true exactly once, when the
    /// drive should end.
    mutating func process(speedMps: Double?, stationary: Bool, at now: Date) -> Bool {
        // Moving means either real road speed OR CoreLocation saying so —
        // a fix with no speed while not flagged stationary stays neutral
        // rather than counting as parked.
        let moving = (speedMps ?? 0) >= config.movingSpeed || (!stationary && speedMps == nil)
        guard !moving else {
            lastMovingAt = now
            return false
        }
        let since = lastMovingAt ?? now
        lastMovingAt = since
        return now.timeIntervalSince(since) >= config.parkedFor
    }

    mutating func reset(at now: Date = .now) {
        lastMovingAt = now
    }
}
