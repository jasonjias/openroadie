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
    /// Rolling log of what detection last did — surfaced in Settings so a
    /// silently missed drive can explain itself (field case: background
    /// wake-ups fired but the probe died unseen).
    static let eventLogKey = "autoDriveEventLog"

    static func note(_ event: String) {
        let stamp = Date.now.formatted(.dateTime.month(.defaultDigits).day().hour().minute())
        var log = UserDefaults.standard.stringArray(forKey: eventLogKey) ?? []
        log.append("\(stamp)  \(event)")
        UserDefaults.standard.set(Array(log.suffix(6)), forKey: eventLogKey)
    }
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
    /// Keeps a background-launched app awake from the wake event until the
    /// probe owns its own session.
    private var wakeSession: CLBackgroundActivitySession?
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
        guard Self.mode != .off, !session.isDriving else { return }
        // A background-LAUNCHED app is suspended within seconds of its wake
        // event unless it holds an activity session — including across this
        // motion query. Held until the probe takes over its own.
        wakeSession = CLBackgroundActivitySession()
        guard CMMotionActivityManager.isActivityAvailable() else {
            // No motion classifier on this device: the 500 m wake alone is
            // reason enough to look at the speedometer.
            Self.note("wake: no motion data — probing")
            detector = Self.likelyDetector()
            startSpeedProbe()
            endWakeSession()
            return
        }
        let start = Date.now.addingTimeInterval(-180)
        activityManager.queryActivityStarting(from: start, to: .now, to: .main) { [weak self] activities, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let samples = activities ?? []
                let automotive = samples.filter(\.automotive).count
                let onFoot = samples.filter { $0.walking || $0.running }.count
                guard Self.shouldProbe(automotive: automotive, onFoot: onFoot, samples: samples.count) else {
                    Self.note("wake: on foot (\(onFoot)/\(samples.count)) — no probe")
                    self.endWakeSession()
                    return
                }
                Self.note("wake: \(automotive) auto / \(samples.count) samples — probing")
                self.log.info("wake justifies a probe")
                _ = self.detector.processMotion(automotive: true, otherActivity: false, at: .now.addingTimeInterval(-60))
                if case .idle = self.detector.state {
                    self.detector = Self.likelyDetector()
                }
                self.startSpeedProbe()
                self.endWakeSession()
            }
        }
    }

    private func endWakeSession() {
        wakeSession?.invalidate()
        wakeSession = nil
    }

    /// Whether a background wake-up justifies spending GPS on a probe.
    ///
    /// The wake itself already means iOS saw ~500 m of travel — that is
    /// evidence, not noise. The old rule demanded 60% automotive over the
    /// previous three minutes, which the START of a drive can never
    /// satisfy: that window is dominated by walking to the car and sitting
    /// down, and Core Motion emits samples on CHANGE, so a real departure
    /// looks like {walking, stationary, automotive} = 33%. Field case: the
    /// wake at the top of the FedEx drive failed this gate and never
    /// probed at all.
    ///
    /// Now the probe runs unless the window is dominated by on-foot
    /// motion — you walked the 500 m. Pure and unit-tested.
    nonisolated static func shouldProbe(automotive: Int, onFoot: Int, samples: Int) -> Bool {
        if automotive > 0 { return true }
        // No classification either way: the travel itself stands alone.
        guard samples > 0 else { return true }
        return Double(onFoot) / Double(samples) <= 0.6
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
        // One liveUpdates stream per process: never probe over an active
        // walk recording. The walk ends itself at vehicle speed, and the
        // next driveLikely re-triggers the probe.
        guard probeTask == nil, !WalkRecorder.isActive else { return }
        Self.note("probe started")
        // The probe already primed the detector into possibleDrive, so
        // confirmSpeed (~10 mph) applies rather than the undeniable bar.
        probeTask = Task { [weak self] in
            // Always when granted: a probe that starts from a background
            // wake-up has no foreground to borrow When-In-Use from.
            let location = CLLocationManager().authorizationStatus == .authorizedAlways
                ? CLServiceSession(authorization: .always)
                : CLServiceSession(authorization: .whenInUse)
            // THE background-relaunch fix: without an activity session iOS
            // suspends a background-launched app seconds after the wake
            // event — before the probe ever sees a road-speed fix. Field
            // case: two wakes fired on the way to FedEx, both probes died
            // silently, the drive went unrecorded.
            let background = CLBackgroundActivitySession()
            LocationSessionJanitor.markSessionsOpen()
            defer {
                location.invalidate()
                background.invalidate()
                // Only stand the flag down if no drive took over the
                // sessions — a confirmed drive holds its own.
                if self?.session.isDriving != true {
                    LocationSessionJanitor.markSessionsClosed()
                    AutoDriveMonitor.note("probe ended unconfirmed")
                }
            }
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
        // Hard deadline. The loop's own timeout only evaluates when a fix
        // arrives, so a stalled GPS stream used to hold the session (and
        // the location pill) open forever — and swiping the app away
        // mid-probe left the system preserving it indefinitely.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(210))
            self?.probeTask?.cancel()
        }
    }

    private func triggerStart() {
        probeTask?.cancel()
        probeTask = nil
        switch Self.mode {
        case .automatic:
            log.info("drive confirmed — starting automatically")
            Self.note("drive confirmed — started")
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
