import Foundation
import UserNotifications

/// Delivers rule alerts as local notifications — which iOS automatically
/// mirrors to a paired Apple Watch with a haptic, so wrist alerts need no
/// watch app at all.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    // Settings keys for the alert rules (see SpeedAlertEngine.Config).
    static let overLimitKey = "alertOverPostedLimit"
    static let marginKey = "alertPostedMarginMph"     // 0 = off
    static let maxSpeedKey = "alertMaxSpeedMph"       // 0 = off
    static let autoEndKey = "autoEndDriveEnabled"

    override init() {
        super.init()
        // Show banners (and play sound) even while the app is foregrounded.
        UNUserNotificationCenter.current().delegate = self
    }

    static func configFromDefaults() -> SpeedAlertEngine.Config {
        let defaults = UserDefaults.standard
        var config = SpeedAlertEngine.Config()
        config.alertOverPostedLimit = defaults.bool(forKey: overLimitKey)
        let margin = defaults.double(forKey: marginKey)
        config.postedMarginMph = margin > 0 ? margin : nil
        let maxSpeed = defaults.double(forKey: maxSpeedKey)
        config.maxSpeedMph = maxSpeed > 0 ? maxSpeed : nil
        return config
    }

    static var autoEndEnabled: Bool {
        UserDefaults.standard.object(forKey: autoEndKey) as? Bool ?? true
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Shared by notifications and the watch app's live alerts.
    static func body(for event: SpeedAlertEngine.Event) -> String {
        switch event {
        case .overPostedLimit(let limit):
            "Over the posted \(limit) mph limit."
        case .overPostedMargin(let limit, let margin):
            "More than \(margin) over the posted \(limit) mph limit."
        case .approachingMaxSpeed(let max):
            "Approaching your \(max) mph max."
        case .overMaxSpeed(let max):
            "Over your \(max) mph max."
        }
    }

    /// True for crossings (urgent haptic); false for approach warnings.
    static func isSevere(_ event: SpeedAlertEngine.Event) -> Bool {
        switch event {
        case .approachingMaxSpeed: false
        default: true
        }
    }

    func deliver(_ events: [SpeedAlertEngine.Event]) {
        deliverCoached(events.map { ($0, Self.body(for: $0)) })
    }

    /// Coaching-style delivery: the notification says what the driver chose
    /// to hear ("Hey Jason, 78 is past 65…"), not a robot's incident report.
    func deliverCoached(_ items: [(event: SpeedAlertEngine.Event, message: String)]) {
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = "Roadie"
            content.sound = .default
            content.body = item.message
            post(content)
        }
    }

    func deliverDriveAutoEnded() {
        let content = UNMutableNotificationContent()
        content.title = "Drive saved"
        content.body = "You've been parked a while, so OpenRoadie ended and saved the drive."
        post(content)
    }

    private func post(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
