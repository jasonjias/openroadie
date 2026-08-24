import CoreLocation
import Foundation
import Observation

/// Owns the drive session lifecycle: Start Drive → consume GPS updates →
/// keep `DrivingContext` current → Stop Drive.
///
/// This is the single object the UI observes. It glues `LocationService`
/// (where fixes come from) to `TripTracker` (what they mean) without either
/// knowing about the other.
@MainActor
@Observable
final class DriveSessionManager {
    enum AuthorizationState {
        case unknown
        case requesting
        case authorized
        case denied
    }

    private(set) var context = DrivingContext()
    private(set) var isDriving = false
    private(set) var authorization: AuthorizationState = .unknown
    /// True when iOS reports the device hasn't moved meaningfully.
    private(set) var isStationary = false
    private(set) var lastErrorDescription: String?

    private let locationService = LocationService()
    private let roadService = RoadService()
    private let alerts = AlertCenter()
    private let store: TripStore?
    private var tracker = TripTracker()
    private var alertEngine = SpeedAlertEngine()
    private var updatesTask: Task<Void, Never>?
    private var currentTrip: Trip?
    private var stationarySince: Date?

    /// Parked this long → the drive ends and saves itself.
    private static let autoEndAfter: TimeInterval = 600

    /// `store` is optional so previews and tests can run without persistence.
    init(store: TripStore? = nil) {
        self.store = store
        // Alert rules apply live: whether changed in Settings or written by
        // Roadie ("warn me at 80"), the engine reconfigures mid-drive.
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadAlertConfig()
            }
        }
    }

    private func reloadAlertConfig() {
        guard isDriving else { return }
        let fresh = AlertCenter.configFromDefaults()
        if fresh != alertEngine.config {
            alertEngine.config = fresh
        }
    }

    func startDrive() {
        guard !isDriving else { return }
        lastErrorDescription = nil
        isStationary = false
        stationarySince = nil
        alertEngine.config = AlertCenter.configFromDefaults()
        alertEngine.reset()
        tracker.start()
        context = tracker.context
        isDriving = true
        currentTrip = store?.beginTrip(at: tracker.context.tripStart ?? .now)
        locationService.begin()

        updatesTask = Task { [weak self] in
            guard let service = self?.locationService else { return }
            do {
                for try await update in service.updates() {
                    guard let self, self.isDriving else { break }
                    self.handle(update)
                }
            } catch {
                guard let self, self.isDriving else { return }
                self.lastErrorDescription = error.localizedDescription
                self.stopDrive()
            }
        }
    }

    func stopDrive() {
        guard isDriving else { return }
        isDriving = false
        updatesTask?.cancel()
        updatesTask = nil
        locationService.end()
        roadService.cancel()
        tracker.stop()
        context = tracker.context
        if let trip = currentTrip {
            store?.endTrip(
                trip,
                at: context.tripEnd ?? .now,
                distance: context.tripDistance,
                maxSpeed: context.tripMaxSpeed
            )
            currentTrip = nil
        }
    }

    private func handle(_ update: CLLocationUpdate) {
        if update.authorizationRequestInProgress {
            authorization = .requesting
        }
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            authorization = .denied
            return
        }

        isStationary = update.stationary

        if let location = update.location {
            authorization = .authorized
            let result = tracker.process(LocationSample(location))
            context = tracker.context
            attachRoadInfo()
            if case .accepted(movedFromLastPoint: true) = result, let trip = currentTrip {
                store?.recordPoint(from: context, in: trip)
            }
            evaluateSpeedRules()
        }

        autoEndIfParked()
    }

    /// Deterministic speed alerts, mirrored to a paired Apple Watch by iOS.
    private func evaluateSpeedRules() {
        let mph = { (metersPerSecond: Double) in metersPerSecond * 2.236936 }
        let events = alertEngine.process(
            speedMph: context.speed.map(mph),
            postedLimitMph: context.road?.speedLimit.map(mph) ?? nil
        )
        if !events.isEmpty {
            alerts.deliver(events)
        }
    }

    /// Parked for a while → end and save the drive on the driver's behalf.
    private func autoEndIfParked() {
        guard AlertCenter.autoEndEnabled else {
            stationarySince = nil
            return
        }
        if isStationary {
            let since = stationarySince ?? .now
            stationarySince = since
            if Date.now.timeIntervalSince(since) > Self.autoEndAfter {
                stopDrive()
                alerts.deliverDriveAutoEnded()
            }
        } else {
            stationarySince = nil
        }
    }

    /// Road awareness rides on top of telemetry: match against the local road
    /// cache each fix, refetching the cache as the drive moves. Optional and
    /// best-effort — the drive works identically with it off or offline.
    private func attachRoadInfo() {
        guard RoadService.isEnabled, let coordinate = context.coordinate else {
            context.road = nil
            return
        }
        roadService.refreshIfNeeded(around: coordinate)
        context.road = roadService.currentRoad(at: coordinate)
    }
}
