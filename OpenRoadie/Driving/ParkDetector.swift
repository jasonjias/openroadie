import Foundation

/// Decides what a stopped vehicle means: a pause in the drive, or the end
/// of it.
///
/// The rule used to be one-shot — five minutes under 3 mph ended and saved
/// the drive. In the field that chopped single drives into pieces: a gas
/// stop, a drive-thru, or a genuine jam ended the trip, and (in Automatic
/// mode) the detector immediately confirmed road speed again and started a
/// new one, notification pair included.
///
/// So stopping now *pauses*. Recording continues, the trip stays open, and
/// moving again resumes the same drive. Only a long settled stop ends it.
/// Getting the pause threshold wrong is cheap; getting the end threshold
/// wrong is not, so the two are far apart.
///
/// Pure and deterministic: every decision is a function of the samples fed
/// in and the clock passed with them.
struct ParkDetector: Equatable {
    struct Config: Equatable {
        /// Below this (m/s ≈ 3 mph) the vehicle isn't going anywhere;
        /// above it, GPS noise while stopped can't fake motion.
        var movingSpeed: Double = 1.4
        /// Continuously stopped this long → the drive is paused.
        var pausedAfter: TimeInterval = 300
        /// Continuously stopped this long → the drive is genuinely over.
        /// Long enough to cover a meal, a shop, or a bad jam.
        var endedAfter: TimeInterval = 1500
        /// A drive that never moves at all — Start Drive tapped and then
        /// nothing — closes itself out rather than holding GPS forever.
        var neverMovedTimeout: TimeInterval = 900
    }

    /// What changed with this sample. Each transition is reported exactly
    /// once, so the caller can act without deduplicating.
    enum Decision: Equatable {
        case unchanged
        /// Stopped long enough to pause the drive.
        case paused
        /// Moving again after a pause: the same drive continues.
        case resumed
        /// Settled long enough that the drive is over.
        case ended
    }

    var config = Config()

    /// Last moment the vehicle was demonstrably moving.
    private(set) var lastMovingAt: Date?
    /// True between a `.paused` and its `.resumed`.
    private(set) var isPaused = false

    private var startedAt: Date?
    /// The stop clock only runs once the drive has actually gone somewhere;
    /// before that, `neverMovedTimeout` applies instead.
    private var hasEverMoved = false

    /// Feed every telemetry update.
    mutating func process(speedMps: Double?, stationary: Bool, at now: Date) -> Decision {
        let startedAt = startedAt ?? now
        self.startedAt = startedAt

        // Moving means either real road speed OR CoreLocation saying so —
        // a fix with no speed while not flagged stationary stays neutral
        // rather than counting as parked.
        let moving = (speedMps ?? 0) >= config.movingSpeed || (!stationary && speedMps == nil)
        if moving {
            hasEverMoved = true
            lastMovingAt = now
            guard isPaused else { return .unchanged }
            isPaused = false
            return .resumed
        }

        guard hasEverMoved else {
            return now.timeIntervalSince(startedAt) >= config.neverMovedTimeout ? .ended : .unchanged
        }

        let since = lastMovingAt ?? now
        lastMovingAt = since
        let stopped = now.timeIntervalSince(since)
        if stopped >= config.endedAfter { return .ended }
        if stopped >= config.pausedAfter, !isPaused {
            isPaused = true
            return .paused
        }
        return .unchanged
    }

    /// How long the vehicle has been stopped, for display. Zero while moving.
    func stoppedFor(at now: Date) -> TimeInterval {
        guard let lastMovingAt else { return 0 }
        return max(0, now.timeIntervalSince(lastMovingAt))
    }

    mutating func reset(at now: Date = .now) {
        lastMovingAt = nil
        startedAt = now
        hasEverMoved = false
        isPaused = false
    }
}
