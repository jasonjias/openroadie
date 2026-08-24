import Foundation

/// Deterministic speed-alert rules — no AI anywhere near this.
///
/// Each rule fires once when its threshold is crossed and re-arms only after
/// speed drops a couple of mph back below it (hysteresis), so GPS jitter at
/// the boundary can't machine-gun alerts.
struct SpeedAlertEngine {
    struct Config: Equatable {
        /// Alert when crossing the posted limit.
        var alertOverPostedLimit = false
        /// Additionally alert this many mph over the posted limit (e.g. 5).
        var postedMarginMph: Double?
        /// The driver's own top speed (mph); alerts on approach and crossing.
        var maxSpeedMph: Double?
        /// "Approaching" means within this many mph of the max.
        var maxSpeedApproachMph: Double = 3

        static let off = Config()
    }

    enum Event: Equatable {
        case overPostedLimit(limitMph: Int)
        case overPostedMargin(limitMph: Int, marginMph: Int)
        case approachingMaxSpeed(maxMph: Int)
        case overMaxSpeed(maxMph: Int)
    }

    /// Hysteresis band: re-arm once speed falls this far below a threshold.
    private static let rearmDeltaMph: Double = 2

    var config = Config.off

    private var overPostedArmed = true
    private var overMarginArmed = true
    private var approachingMaxArmed = true
    private var overMaxArmed = true

    /// Feed every telemetry update; returns the alerts that fire on this one.
    mutating func process(speedMph: Double?, postedLimitMph: Double?) -> [Event] {
        guard let speed = speedMph else { return [] }
        var events: [Event] = []

        if config.alertOverPostedLimit, let limit = postedLimitMph {
            if step(&overPostedArmed, speed: speed, threshold: limit) {
                events.append(.overPostedLimit(limitMph: Int(limit.rounded())))
            }
        }

        if let margin = config.postedMarginMph, let limit = postedLimitMph {
            if step(&overMarginArmed, speed: speed, threshold: limit + margin) {
                events.append(.overPostedMargin(limitMph: Int(limit.rounded()), marginMph: Int(margin.rounded())))
            }
        }

        if let max = config.maxSpeedMph {
            if step(&approachingMaxArmed, speed: speed, threshold: max - config.maxSpeedApproachMph) {
                events.append(.approachingMaxSpeed(maxMph: Int(max.rounded())))
            }
            if step(&overMaxArmed, speed: speed, threshold: max) {
                events.append(.overMaxSpeed(maxMph: Int(max.rounded())))
            }
        }

        return events
    }

    mutating func reset() {
        overPostedArmed = true
        overMarginArmed = true
        approachingMaxArmed = true
        overMaxArmed = true
    }

    /// Fire-once-with-hysteresis: fires when crossing above `threshold` while
    /// armed; re-arms when speed drops below `threshold - rearmDelta`.
    private func step(_ armed: inout Bool, speed: Double, threshold: Double) -> Bool {
        if armed, speed > threshold {
            armed = false
            return true
        }
        if !armed, speed < threshold - Self.rearmDeltaMph {
            armed = true
        }
        return false
    }
}
