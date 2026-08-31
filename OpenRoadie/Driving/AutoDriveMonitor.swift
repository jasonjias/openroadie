import CoreLocation
import CoreMotion
import Foundation
import Observation
import UserNotifications
import os

/// Runs the DriveDetector against real sensors: Core Motion activity while
/// no drive is recording, a short GPS probe once a drive looks likely, and
/// then — per the driver's setting — either starts the drive or suggests it.
/// Driving should activate OpenRoadie, not the other way around.
///
/// Honest v1 limits: iOS suspends apps without an active location session,
/// so detection works while OpenRoadie is open or still alive in the
/// background. A cold start also checks recent motion history, so opening
/// the app mid-drive offers to record what you're doing right now.
@MainActor
@Observable
final class AutoDriveMonitor {
    enum Mode: String, CaseIterable, Identifiable {
        case off
        case notify
        case automatic

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "Off"
            case .notify: "Suggest"
            case .automatic: "Automatic"
            }
        }
    }

    static let modeKey = "autoStartDriveMode"
    /// Hands-free: no Start Drive button at all — OpenRoadie begins and ends
    /// drives on its own.
    static let handsFreeKey = "handsFreeDriveControl"

    static var mode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .off
    }

    /// The `mode` check is deliberately part of the accessor rather than the
    /// caller's problem: hiding the Start Drive button while nothing is
    /// watching for drives would leave no way to record at all.
    static var handsFree: Bool {
        UserDefaults.standard.bool(forKey: handsFreeKey) && mode == .automatic
    }

    private let session: DriveSessionManager
    private let activityManager = CMMotionActivityManager()
    private var detector = DriveDetector()
    private var monitoring = false
    private var probeTask: Task<Void, Never>?
    /// After a suggestion notification, stay quiet for a while — nagging
    /// every 20 seconds of the same drive would get the feature turned off.
    private var snoozedUntil: Date?

    private let log = Logger(subsystem: "com.openroadie", category: "autodrive")

    init(session: DriveSessionManager) {
        self.session = session
        // The mode picker applies live, same pattern as the alert rules.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    /// Re-evaluates whether detection should run. Call on app start, drive
    /// start/stop, and settings changes.
    func refresh() {
        let wants = Self.mode != .off
            && !session.isDriving
            && (snoozedUntil.map { Date.now > $0 } ?? true)
        switch (wants, monitoring) {
        case (true, false): start()
        case (false, true): stop()
        default: break
        }
    }

    /// Cold-start check: if the phone was already in automotive motion over
    /// the last few minutes, the drive is happening NOW — skip the wait.
    func checkRecentActivity() {
        guard Self.mode != .off, !session.isDriving,
              CMMotionActivityManager.isActivityAvailable() else { return }
        let start = Date.now.addingTimeInterval(-180)
        activityManager.queryActivityStarting(from: start, to: .now, to: .main) { [weak self] activities, _ in
            MainActor.assumeIsolated {
                guard let self, let activities, !activities.isEmpty else { return }
                let automotive = activities.filter(\.automotive).count
                if Double(automotive) / Double(activities.count) > 0.6 {
                    self.log.info("recent history is automotive — probing for speed")
                    _ = self.detector.processMotion(automotive: true, otherActivity: false, at: .now.addingTimeInterval(-60))
                    if case .idle = self.detector.state {
                        self.detector = Self.likelyDetector()
                    }
                    self.startSpeedProbe()
                }
            }
        }
    }

    /// A detector already in the possible-drive state (history proved the
    /// sustained-automotive part).
    private static func likelyDetector() -> DriveDetector {
        var detector = DriveDetector()
        _ = detector.processMotion(automotive: true, otherActivity: false, at: .now.addingTimeInterval(-60))
        _ = detector.processMotion(automotive: true, otherActivity: false, at: .now)
        return detector
    }

    private func start() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            log.info("motion activity unavailable on this device")
            return
        }
        monitoring = true
        detector.reset()
        log.info("drive detection armed (mode=\(Self.mode.rawValue, privacy: .public))")
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            MainActor.assumeIsolated {
                self?.handle(activity)
            }
        }
    }

    private func stop() {
        monitoring = false
        activityManager.stopActivityUpdates()
        probeTask?.cancel()
        probeTask = nil
        detector.reset()
    }

    private func handle(_ activity: CMMotionActivity) {
        let other = activity.walking || activity.running || activity.cycling
        if let event = detector.processMotion(automotive: activity.automotive, otherActivity: other, at: .now) {
            act(on: event)
        }
    }

    private func act(on event: DriveDetector.Event) {
        switch event {
        case .driveLikely:
            log.info("sustained automotive motion — probing GPS for road speed")
            startSpeedProbe()
        case .driveConfirmed:
            triggerStart()
        }
    }

    /// Short-lived GPS session purely to see road speed. Ends as soon as the
    /// detector decides either way.
    private func startSpeedProbe() {
        guard probeTask == nil else { return }
        probeTask = Task { [weak self] in
            // Always when granted: a probe that starts from a background
            // wake-up has no foreground to borrow When-In-Use from.
            let location = CLLocationManager().authorizationStatus == .authorizedAlways
                ? CLServiceSession(authorization: .always)
                : CLServiceSession(authorization: .whenInUse)
            defer { location.invalidate() }
            var samples = 0
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    guard let self, !Task.isCancelled, !self.session.isDriving else { break }
                    let speed = update.location.flatMap { $0.speed >= 0 ? $0.speed : nil }
                    if let event = self.detector.processSpeed(speed, at: .now) {
                        self.act(on: event)
                        break
                    }
                    if case .idle = self.detector.state { break } // timed out unconfirmed
                    samples += 1
                    if samples > 200 { break }
                }
            } catch {
                self?.log.error("speed probe failed: \(error.localizedDescription, privacy: .public)")
            }
            self?.probeTask = nil
        }
    }

    private func triggerStart() {
        probeTask?.cancel()
        probeTask = nil
        switch Self.mode {
        case .automatic:
            log.info("drive confirmed — starting automatically")
            session.startDrive()
            postNotification(
                title: "Drive started",
                body: "Looks like you're driving, so OpenRoadie started recording. It saves itself when you park."
            )
        case .notify:
            log.info("drive confirmed — suggesting")
            postNotification(
                title: "Driving?",
                body: "Looks like you're on the road. Open OpenRoadie and tap Start Drive to record this trip."
            )
            snoozedUntil = .now.addingTimeInterval(30 * 60)
        case .off:
            break
        }
        stop()
        refresh()
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
