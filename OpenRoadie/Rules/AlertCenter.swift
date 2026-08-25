import Foundation
import UserNotifications

/// Delivers rule alerts as local notifications — which iOS automatically
/// mirrors to a paired Apple Watch with a haptic, so wrist alerts need no
/// watch app at all.
@MainActor
final class AlertCenter: NSObject, UNUserNotificationCenterDelegate {
    // Settings keys for the alert rules (see SpeedAlertEngine.Config).
    static let overLimitKey = "alertOverPostedLimit"        // legacy bool, migrated
    static let overLimitStyleKey = "alertOverLimitStyle"    // OverLimitStyle raw
    static let marginKey = "alertPostedMarginMph"           // 0 = off, -1 = adaptive
    static let maxSpeedKey = "alertMaxSpeedMph"             // 0 = off
    static let autoEndKey = "autoEndDriveEnabled"

    /// What crossing the posted limit does. Tesla-calibrated default: a
    /// chime, not a lecture — 26 in a 25 doesn't deserve a notification.
    enum OverLimitStyle: String, CaseIterable, Identifiable {
        case off
        case chime
        case coach

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "Off"
            case .chime: "Chime"
            case .coach: "Coach"
            }
        }
    }

    static var overLimitStyle: OverLimitStyle {
        migrateLegacyOverLimitToggle()
        let raw = UserDefaults.standard.string(forKey: overLimitStyleKey) ?? ""
        return OverLimitStyle(rawValue: raw) ?? .off
    }

    /// The pre-tier releases stored a bool: notify-and-speak on every
    /// crossing. Field-tested as way too chatty — carry it forward as chime.
    static func migrateLegacyOverLimitToggle() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: overLimitStyleKey) == nil else { return }
        if defaults.object(forKey: overLimitKey) != nil {
            defaults.set(defaults.bool(forKey: overLimitKey) ? OverLimitStyle.chime.rawValue : OverLimitStyle.off.rawValue, forKey: overLimitStyleKey)
            defaults.removeObject(forKey: overLimitKey)
        }
    }

    override init() {
        super.init()
        // Show banners (and play sound) even while the app is foregrounded.
        UNUserNotificationCenter.current().delegate = self
    }

    static func configFromDefaults() -> SpeedAlertEngine.Config {
        let defaults = UserDefaults.standard
        var config = SpeedAlertEngine.Config()
        config.alertOverPostedLimit = overLimitStyle != .off
        // Margin tier: absent = adaptive (the recommended default),
        // 0 = explicitly off, -1 = explicitly adaptive, else fixed mph.
        switch defaults.object(forKey: marginKey) as? Double {
        case nil, -1: config.postedMarginIsAdaptive = true
        case 0: break
        case .some(let mph): config.postedMarginMph = mph
        }
        let maxSpeed = defaults.double(forKey: maxSpeedKey)
        config.maxSpeedMph = maxSpeed > 0 ? maxSpeed : nil
        return config
    }

    static var autoEndEnabled: Bool {
        UserDefaults.standard.object(forKey: autoEndKey) as? Bool ?? true
    }

    static func requestAuthorization() {
        // @Sendable: the callback arrives on a background queue and must not
        // carry this class's main-actor isolation (device-only trap).
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in }
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

    /// The earn-points moment: a finished drive with zero events.
    func deliverCleanDrive(streak: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Clean drive"
        content.body = streak >= 2
            ? "No alerts, no hard maneuvers. That's \(streak) in a row — keep it going."
            : "No alerts, no hard maneuvers. Streak started."
        post(content)
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
