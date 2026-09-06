import CoreLocation
import Foundation
import os

/// The always-on location spine.
///
/// OpenRoadie used to record location only in bursts — during a drive it had
/// to first *detect*. Between and around drives nothing held a GPS session,
/// so breadcrumbs were fragmented and background drives were missed whenever
/// the detect→probe→confirm handoff was suspended mid-step.
///
/// This flips the model: while Always-on is enabled and the app is alive, a
/// single location stream runs continuously and drops a breadcrumb as you
/// move — through walks, errands, everything. A drive is no longer something
/// to catch; it is simply the fast stretch of this one stream, and the
/// recorder promotes itself into a real drive the moment it sees road speed.
///
/// Exactly one `liveUpdates` stream may exist per process, so this yields to
/// an active drive (paused while the drive owns the stream, resumed when it
/// ends). Battery is the honest cost of Always-on, which is why it is gated
/// behind that setting.
@MainActor
final class ContinuousRecorder {
    private(set) static var isActive = false

    /// Set by the owner: promotes the stream to a real drive.
    var onRoadSpeed: (() -> Void)?

    private let store: TripStore?
    private var detector = DriveDetector()
    private var serviceSession: CLServiceSession?
    private var backgroundSession: CLBackgroundActivitySession?
    private var task: Task<Void, Never>?
    private let log = Logger(subsystem: "com.openroadie", category: "continuous")

    init(store: TripStore?) {
        self.store = store
    }

    /// Pure gate, unit-tested: run only when the user opted into Always-on,
    /// location is granted, and no drive already owns the stream.
    nonisolated static func shouldRun(enabled: Bool, authorized: Bool, isDriving: Bool) -> Bool {
        enabled && authorized && !isDriving
    }

    func start() {
        let status = CLLocationManager().authorizationStatus
        let authorized = status == .authorizedAlways || status == .authorizedWhenInUse
        guard !Self.isActive,
              Self.shouldRun(enabled: BackgroundDriveWatcher.isEnabled, authorized: authorized, isDriving: false)
        else { return }
        Self.isActive = true
        LocationSessionJanitor.markSessionsOpen()
        AutoDriveMonitor.note("continuous recording on")
        detector = DriveDetector()
        serviceSession = status == .authorizedAlways
            ? CLServiceSession(authorization: .always)
            : CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        task = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                    guard let self, Self.isActive else { break }
                    guard let location = update.location else { continue }
                    let speed = location.speed >= 0 ? location.speed : nil
                    if location.horizontalAccuracy > 0, location.horizontalAccuracy <= 100 {
                        self.store?.saveCrumb(
                            Coordinate(latitude: location.coordinate.latitude,
                                       longitude: location.coordinate.longitude),
                            accuracy: location.horizontalAccuracy
                        )
                    }
                    // Road speed → this is a drive. Hand off and stop; the
                    // drive session opens its own (single) stream.
                    if self.detector.processSpeed(speed, at: .now) == .driveConfirmed {
                        AutoDriveMonitor.note("continuous → drive")
                        self.onRoadSpeed?()
                        break
                    }
                }
            } catch {
                self?.log.error("continuous stream ended: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Yield the stream (a drive is taking over, or the app is standing down).
    func stop() {
        guard Self.isActive else { return }
        Self.isActive = false
        task?.cancel()
        task = nil
        serviceSession?.invalidate()
        serviceSession = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        LocationSessionJanitor.markSessionsClosed()
    }
}
