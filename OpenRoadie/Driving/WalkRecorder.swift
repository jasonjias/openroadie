import CoreLocation
import CoreMotion
import Foundation
import os

/// Decides when a recorded walk is over. Pure and unit-tested.
struct WalkEndDetector: Equatable {
    struct Config: Equatable {
        /// Not walking this long → the outing is over. Thirty minutes, not
        /// three: sitting down to lunch is a PAUSE in a walk the way a red
        /// light is a pause in a drive — the trail out of the restaurant
        /// belongs to the same outing as the trail in. Think of it as a
        /// slow drive being recorded.
        var notWalkingEndsAfter: TimeInterval = 30 * 60
        /// Sustained speed no pedestrian reaches → back in a vehicle.
        var vehicleSpeed: Double = 6
        /// An afternoon on foot is one outing; a whole day is not.
        var maxDuration: TimeInterval = 3 * 3_600
    }

    var config = Config()
    private var startedAt: Date?
    private var lastWalkingAt: Date?

    mutating func process(walking: Bool, speedMps: Double?, at now: Date) -> Bool {
        let startedAt = startedAt ?? now
        self.startedAt = startedAt
        if walking { lastWalkingAt = now }
        let lastWalkingAt = lastWalkingAt ?? startedAt
        self.lastWalkingAt = lastWalkingAt
        if let speedMps, speedMps >= config.vehicleSpeed { return true }
        if now.timeIntervalSince(lastWalkingAt) >= config.notWalkingEndsAfter { return true }
        if now.timeIntervalSince(startedAt) >= config.maxDuration { return true }
        return false
    }
}

/// Breadcrumbs for the walk after parking.
///
/// When a drive ends by walk-away, the app is still alive at that exact
/// moment — the one window where walk location exists without always-on
/// tracking. The recorder keeps a GPS session through the walk and stores
/// the trail; it ends the moment walking stops for a few minutes, a
/// vehicle speed appears, or the cap hits. Indoors the accuracy filter
/// mostly rejects fixes, so trails honestly go quiet inside buildings.
@MainActor
final class WalkRecorder {
    /// Settings toggle; on by default, disclosed beside the recording model.
    static let enabledKey = "walkBreadcrumbsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// One liveUpdates stream per process — the detection probe checks this
    /// before opening its own (the janitor saga's lesson, applied forward).
    private(set) static var isActive = false

    private let store: TripStore?
    private let activityManager = CMMotionActivityManager()
    private var tracker = TripTracker()
    private var detector = WalkEndDetector()
    private var coordinates: [Coordinate] = []
    private var isWalking = true
    private var updatesTask: Task<Void, Never>?
    private var serviceSession: CLServiceSession?
    /// Without this the app is suspended seconds after the drive that
    /// spawned this recorder tears ITS session down — which is exactly
    /// when walk recording begins. Field symptom: no walk trails, ever.
    private var backgroundSession: CLBackgroundActivitySession?
    private let log = Logger(subsystem: "com.openroadie", category: "walk")

    init(store: TripStore?) {
        self.store = store
    }

    func start() {
        guard Self.isEnabled, !Self.isActive else { return }
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        Self.isActive = true
        LocationSessionJanitor.markSessionsOpen()
        log.info("walk recording started")
        tracker.config = TripTracker.walking
        tracker.start()
        coordinates = []
        detector = WalkEndDetector()
        isWalking = true
        serviceSession = status == .authorizedAlways
            ? CLServiceSession(authorization: .always)
            : CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity else { return }
                MainActor.assumeIsolated {
                    self?.isWalking = activity.walking || activity.running
                }
            }
        }
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, Self.isActive else { break }
                    if let location = update.location {
                        let result = self.tracker.process(LocationSample(location))
                        if case .accepted(movedFromLastPoint: true) = result,
                           let coordinate = self.tracker.context.coordinate {
                            self.coordinates.append(coordinate)
                        }
                    }
                    if self.detector.process(
                        walking: self.isWalking,
                        speedMps: self.tracker.context.speed,
                        at: .now
                    ) {
                        self.finish()
                        break
                    }
                    if self.coordinates.count > 8_000 {
                        self.finish()
                        break
                    }
                }
            } catch {
                self?.log.error("walk stream ended: \(error.localizedDescription, privacy: .public)")
                self?.finish()
            }
        }
        // Hard deadline, mirroring the probe's: the loop's own checks only
        // run when a fix arrives.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3 * 3_600 + 300))
            self?.finish()
        }
    }

    func finish() {
        guard Self.isActive else { return }
        Self.isActive = false
        updatesTask?.cancel()
        updatesTask = nil
        serviceSession?.invalidate()
        serviceSession = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        activityManager.stopActivityUpdates()
        LocationSessionJanitor.markSessionsClosed()
        tracker.stop()
        // A trail worth keeping actually went somewhere on foot.
        if coordinates.count >= 2, tracker.context.tripDistance >= 30 {
            store?.saveWalkPath(
                start: tracker.context.tripStart ?? .now,
                end: tracker.context.tripEnd ?? .now,
                distance: tracker.context.tripDistance,
                coordinates: coordinates
            )
            log.info("walk saved: \(Int(self.tracker.context.tripDistance))m, \(self.coordinates.count) points")
        } else {
            log.info("walk discarded (too short)")
        }
        coordinates = []
    }
}
