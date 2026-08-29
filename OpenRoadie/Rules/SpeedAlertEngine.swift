import Foundation

/// Deterministic speed-alert rules — no AI anywhere near this.
///
/// A rule fires only when speed stays past its threshold for `sustained`
/// seconds, re-arms after speed drops a couple of mph back below it
/// (hysteresis), and then keeps quiet for `minimumInterval` before it can
/// speak again. Field-tuned: brief crossings while passing, cresting a
/// hill, or riding a bad map match are not worth a word.
struct SpeedAlertEngine {
    struct Config: Equatable {
        /// How long speed must stay past a threshold before it's real.
        var sustainedSeconds: TimeInterval = 10
        /// Quiet period after a rule fires, per rule.
        var minimumIntervalSeconds: TimeInterval = 240
        /// Alert when crossing the posted limit.
        var alertOverPostedLimit = false
        /// Additionally alert this many mph over the posted limit (e.g. 5).
        var postedMarginMph: Double?
        /// Adaptive margin: max(5 mph, 15% of the limit) — ~30 in a 25,
        /// ~75 in a 65. Matches how speeding is actually treated: a fixed
        /// mph is too loose in a school zone and too tight on a freeway.
        /// When set, `postedMarginMph` is ignored.
        var postedMarginIsAdaptive = false
        /// The driver's own top speed (mph); alerts on approach and crossing.
        var maxSpeedMph: Double?
        /// "Approaching" means within this many mph of the max.
        var maxSpeedApproachMph: Double = 3

        static let off = Config()

        /// The margin that applies on a road with this limit, or nil if the
        /// margin tier is off.
        func effectiveMarginMph(forLimit limit: Double) -> Double? {
            if postedMarginIsAdaptive { return max(5, limit * 0.15) }
            return postedMarginMph
        }
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

    /// Per-rule state: armed, when the threshold was first exceeded, and
    /// when it last fired.
    private struct RuleState {
        var armed = true
        var overSince: Date?
        var lastFired: Date?
        /// The threshold this rule is currently timing against. When the
        /// road's limit changes the sustained window restarts, so entering
        /// a new zone always comes with a few seconds of grace to adjust.
        var threshold: Double?
    }

    private var overPosted = RuleState()
    private var overMargin = RuleState()
    private var approachingMax = RuleState()
    private var overMax = RuleState()

    /// Feed every telemetry update; returns the alerts that fire on this one.
    mutating func process(speedMph: Double?, postedLimitMph: Double?, at now: Date = .now) -> [Event] {
        guard let speed = speedMph else { return [] }
        var events: [Event] = []

        if config.alertOverPostedLimit, let limit = postedLimitMph {
            if step(&overPosted, speed: speed, threshold: limit, now: now) {
                events.append(.overPostedLimit(limitMph: Int(limit.rounded())))
            }
        }

        if let limit = postedLimitMph, let margin = config.effectiveMarginMph(forLimit: limit) {
            if step(&overMargin, speed: speed, threshold: limit + margin, now: now) {
                events.append(.overPostedMargin(limitMph: Int(limit.rounded()), marginMph: Int(margin.rounded())))
            }
        }

        if let max = config.maxSpeedMph {
            if step(&approachingMax, speed: speed, threshold: max - config.maxSpeedApproachMph, now: now) {
                events.append(.approachingMaxSpeed(maxMph: Int(max.rounded())))
            }
            if step(&overMax, speed: speed, threshold: max, now: now) {
                events.append(.overMaxSpeed(maxMph: Int(max.rounded())))
            }
        }

        return events
    }

    mutating func reset() {
        overPosted = RuleState()
        overMargin = RuleState()
        approachingMax = RuleState()
        overMax = RuleState()
    }

    /// Fires when speed has stayed above `threshold` for the sustained
    /// window, the rule is armed, and its quiet period has elapsed.
    /// Re-arms when speed drops below `threshold - rearmDelta`.
    private func step(_ state: inout RuleState, speed: Double, threshold: Double, now: Date) -> Bool {
        if let previous = state.threshold, abs(previous - threshold) > 1 {
            state.overSince = nil
            state.armed = true
        }
        state.threshold = threshold
        guard speed > threshold else {
            state.overSince = nil
            if speed < threshold - Self.rearmDeltaMph { state.armed = true }
            return false
        }
        let since = state.overSince ?? now
        state.overSince = since
        guard state.armed,
              now.timeIntervalSince(since) >= config.sustainedSeconds,
              state.lastFired.map({ now.timeIntervalSince($0) >= config.minimumIntervalSeconds }) ?? true
        else { return false }
        state.armed = false
        state.lastFired = now
        return true
    }
}
