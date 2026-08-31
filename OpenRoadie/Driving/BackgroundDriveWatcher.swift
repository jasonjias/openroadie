import CoreLocation
import Foundation
import os

/// Always-on drive detection: the app stops being something you remember
/// to open.
///
/// iOS suspends (and eventually terminates) an app with no active location
/// session, which is why detection used to need OpenRoadie already running.
/// Significant-location-change monitoring is the one mechanism that
/// **relaunches a terminated app** — iOS wakes us after roughly 500 m of
/// travel, and we hand off to the existing detector: motion history says
/// automotive, a short GPS probe confirms road speed, the drive starts.
///
/// Costs the user nothing in battery beyond what the cell-tower-based
/// significant-change service already does for the system, and requires
/// Always authorization, which is asked for only when the toggle is armed.
@MainActor
final class BackgroundDriveWatcher: NSObject, CLLocationManagerDelegate {
    /// Settings toggle; off until the driver opts in.
    static let enabledKey = "alwaysOnDriveDetection"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// True once the driver has granted Always — the only authorization
    /// that survives termination.
    var hasAlwaysAuthorization: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    private let manager = CLLocationManager()
    private var running = false
    private var onWake: (() -> Void)?
    private let log = Logger(subsystem: "com.openroadie", category: "background")

    override init() {
        super.init()
        manager.delegate = self
        // The toggle applies live, same pattern as the other rule settings.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let onWake = self.onWake else { return }
                self.refresh(onWake: onWake)
            }
        }
    }

    /// Starts (or stops) monitoring to match the setting. Safe to call on
    /// every launch and whenever the setting changes.
    func refresh(onWake: @escaping () -> Void) {
        self.onWake = onWake
        guard Self.isEnabled else {
            stop()
            return
        }
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            log.info("significant-change monitoring unavailable on this device")
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            // When-in-use first, then Always — iOS requires the escalation
            // and shows the second prompt only after the first is granted.
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
            start()
        case .authorizedAlways:
            start()
        default:
            log.info("location authorization denied — always-on detection cannot run")
        }
    }

    private func start() {
        guard !running else { return }
        running = true
        manager.startMonitoringSignificantLocationChanges()
        log.info("always-on drive detection armed")
    }

    func stop() {
        // Deliberately NOT guarded on `running`: significant-change
        // registration persists across launches until explicitly stopped,
        // so a fresh process with the toggle off must still deregister
        // what a previous session armed. Field symptom: the location
        // arrow survived swiping the app away even after opting out.
        let wasRunning = running
        running = false
        manager.stopMonitoringSignificantLocationChanges()
        if wasRunning {
            log.info("always-on drive detection disarmed")
        }
    }

    // MARK: - CLLocationManagerDelegate
    //
    // Delegate callbacks arrive on the queue the manager was created on
    // (main here), but the protocol isn't main-actor annotated.

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            log.info("woken by significant location change")
            onWake?()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Read our own isolated manager rather than the parameter, which
        // would be sent across the isolation boundary.
        MainActor.assumeIsolated {
            guard Self.isEnabled else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse:
                self.manager.requestAlwaysAuthorization()
            case .authorizedAlways:
                start()
            default:
                stop()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            log.error("significant-change monitoring failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
