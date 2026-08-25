import Foundation
import WatchConnectivity

/// Streams live drive stats and alert haptic triggers to the watch app.
/// Best-effort by design: no watch, no problem.
@MainActor
final class PhoneWatchLink: NSObject, WCSessionDelegate {
    private var lastPush = Date.distantPast

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Pushes the current drive state, throttled to ~1/s. `updateApplicationContext`
    /// coalesces, so the watch always wakes to the latest state.
    func push(context: DrivingContext, isDriving: Bool) {
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        guard Date.now.timeIntervalSince(lastPush) >= 1 else { return }
        lastPush = .now

        let mph = { (metersPerSecond: Double) in Int((metersPerSecond * 2.236936).rounded()) }
        var payload: [String: Any] = [
            "isDriving": isDriving,
            "distanceMi": context.tripDistance / 1609.344,
            "durationSec": Int(context.tripDuration() ?? 0),
        ]
        if let speed = context.speed { payload["speedMph"] = mph(speed) }
        if let limit = context.road?.speedLimit { payload["limitMph"] = mph(limit) }
        if let road = context.road?.displayName { payload["road"] = road }

        try? session.updateApplicationContext(payload)
    }

    /// Alert events buzz the watch app directly (instant, custom haptic) —
    /// on top of the mirrored notification, which still covers the case
    /// where the watch app isn't running.
    func send(_ events: [SpeedAlertEngine.Event]) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        for event in events {
            let payload: [String: Any] = [
                "text": AlertCenter.body(for: event),
                "severe": AlertCenter.isSevere(event),
            ]
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil)
            } else {
                session.transferUserInfo(payload)
            }
        }
    }

    // MARK: - WCSessionDelegate (background threads; nothing to hop for)

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
