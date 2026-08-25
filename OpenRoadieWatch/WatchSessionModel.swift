import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// Receives live drive stats and alert haptics from the iPhone.
/// The phone remains the single source of truth; the watch only displays.
@MainActor
@Observable
final class WatchSessionModel: NSObject, WCSessionDelegate {
    private(set) var isDriving = false
    private(set) var speedMph: Int?
    private(set) var limitMph: Int?
    private(set) var road: String?
    private(set) var distanceMiles: Double = 0
    private(set) var durationSeconds: Int = 0
    private(set) var lastAlert: String?

    /// Everything the phone streams, as a Sendable value.
    struct Snapshot: Sendable {
        var isDriving = false
        var speedMph: Int?
        var limitMph: Int?
        var road: String?
        var distanceMiles: Double = 0
        var durationSeconds: Int = 0
    }

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    var isOverLimit: Bool {
        guard let speedMph, let limitMph else { return false }
        return speedMph > limitMph
    }

    // MARK: - WCSessionDelegate (background threads: parse, then hop)

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let snapshot = Self.parse(session.receivedApplicationContext)
        Task { @MainActor in self.apply(snapshot) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let snapshot = Self.parse(applicationContext)
        Task { @MainActor in self.apply(snapshot) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let text = message["text"] as? String
        let severe = message["severe"] as? Bool ?? false
        Task { @MainActor in self.handleAlert(text: text, severe: severe) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let text = userInfo["text"] as? String
        let severe = userInfo["severe"] as? Bool ?? false
        Task { @MainActor in self.handleAlert(text: text, severe: severe) }
    }

    // MARK: - State

    private static nonisolated func parse(_ payload: [String: Any]) -> Snapshot {
        var snapshot = Snapshot()
        snapshot.isDriving = payload["isDriving"] as? Bool ?? false
        snapshot.speedMph = payload["speedMph"] as? Int
        snapshot.limitMph = payload["limitMph"] as? Int
        snapshot.road = payload["road"] as? String
        snapshot.distanceMiles = payload["distanceMi"] as? Double ?? 0
        snapshot.durationSeconds = payload["durationSec"] as? Int ?? 0
        return snapshot
    }

    private func apply(_ snapshot: Snapshot) {
        isDriving = snapshot.isDriving
        speedMph = snapshot.speedMph
        limitMph = snapshot.limitMph
        road = snapshot.road
        distanceMiles = snapshot.distanceMiles
        durationSeconds = snapshot.durationSeconds
        if !snapshot.isDriving { lastAlert = nil }
    }

    private func handleAlert(text: String?, severe: Bool) {
        lastAlert = text
        // Distinct wrist feel: urgent for crossings, a tap for approaches.
        // Double-buzz — a single haptic is easy to miss at highway speed.
        let haptic: WKHapticType = severe ? .failure : .notification
        WKInterfaceDevice.current().play(haptic)
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            WKInterfaceDevice.current().play(haptic)
        }
    }
}
