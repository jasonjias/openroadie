import Foundation

/// Deterministic multi-signal drive detection: Core Motion says the phone is
/// in a vehicle, sustained; GPS confirms real road speed; only then does a
/// drive begin. Walking cancels; a possible drive that never confirms times
/// out. Pure state machine — the runtime (AutoDriveMonitor) owns sensors.
///
///     idle ──automotive sustained──▶ possibleDrive ──speed ≥ ~10 mph──▶ confirmed
///       ▲            walking ◀──┘         │ timeout / walking
///       └───────────────────────────────◀─┘
struct DriveDetector {
    enum State: Equatable {
        case idle
        case possibleDrive(since: Date)
        case confirmed
    }

    struct Config: Equatable {
        /// Automotive motion sustained this long → possible drive. Long
        /// enough that a passenger loading the car doesn't trigger it.
        var minAutomotiveDuration: TimeInterval = 20
        /// GPS speed (m/s ≈ 10 mph) that confirms actual driving —
        /// automotive motion alone can be a bus, a car wash, or a parked
        /// car with the engine on.
        var confirmSpeed: Double = 4.5
        /// A possible drive that never reaches road speed resets — sitting
        /// parked with the engine running is not a drive.
        var possibleTimeout: TimeInterval = 180
    }

    enum Event: Equatable {
        /// Sustained automotive motion: worth spending GPS power to confirm.
        case driveLikely
        /// Automotive motion at road speed: this is a drive.
        case driveConfirmed
    }

    var config = Config()
    private(set) var state: State = .idle
    private var automotiveSince: Date?

    /// Feed a motion-activity sample. `otherActivity` means the system
    /// explicitly saw walking/running/cycling — stationary and unknown do
    /// NOT cancel, because cars stop at lights.
    mutating func processMotion(automotive: Bool, otherActivity: Bool, at date: Date) -> Event? {
        expireIfTimedOut(at: date)

        if otherActivity {
            automotiveSince = nil
            if case .possibleDrive = state { state = .idle }
            return nil
        }

        guard case .idle = state else { return nil }
        guard automotive else { return nil }

        let since = automotiveSince ?? date
        automotiveSince = since
        if date.timeIntervalSince(since) >= config.minAutomotiveDuration {
            state = .possibleDrive(since: date)
            return .driveLikely
        }
        return nil
    }

    /// Feed a GPS speed sample (m/s; nil when GPS doesn't know). Only
    /// meaningful while a drive is possible.
    mutating func processSpeed(_ speedMps: Double?, at date: Date) -> Event? {
        expireIfTimedOut(at: date)
        guard case .possibleDrive = state else { return nil }
        guard let speedMps, speedMps >= config.confirmSpeed else { return nil }
        state = .confirmed
        return .driveConfirmed
    }

    /// Back to a clean slate — call when a drive ends or monitoring stops.
    mutating func reset() {
        state = .idle
        automotiveSince = nil
    }

    private mutating func expireIfTimedOut(at date: Date) {
        if case .possibleDrive(let since) = state,
           date.timeIntervalSince(since) > config.possibleTimeout {
            state = .idle
            automotiveSince = nil
        }
    }
}
