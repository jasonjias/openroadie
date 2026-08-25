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
    private let motionService = MotionService()
    private let alerts = AlertCenter()
    private let watchLink = PhoneWatchLink()
    private let store: TripStore?
    private var tracker = TripTracker()
    private var alertEngine = SpeedAlertEngine()
    /// Always-on recorder for the Drive Score: counts posted-limit and
    /// +5-over crossings regardless of whether the user enabled alerts.
    private var scoreRecorder = SpeedAlertEngine()
    private var updatesTask: Task<Void, Never>?
    private var currentTrip: Trip?
    private var stationarySince: Date?
    /// Alerts so far this drive — coaching escalates its tone politely.
    private var alertOccurrences = 0
    /// Recorded events (hard maneuvers + limit crossings) this drive.
    /// Zero at drive end = a clean drive that extends the streak.
    private var eventsThisDrive = 0

    /// Set by the app layer: speaks a coaching nudge through the shared
    /// voice pipeline (which pauses the wake listener around it).
    var speakCoaching: ((String) -> Void)?
    /// Recent (timestamp, mph) samples for classifying hard maneuvers.
    private var recentSpeeds: [(Date, Double)] = []

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
        scoreRecorder.config = SpeedAlertEngine.Config(alertOverPostedLimit: true, postedMarginMph: 5)
        scoreRecorder.reset()
        alertOccurrences = 0
        eventsThisDrive = 0
        tracker.start()
        context = tracker.context
        isDriving = true
        currentTrip = store?.beginTrip(at: tracker.context.tripStart ?? .now)
        locationService.begin()
        recentSpeeds = []
        motionService.onHardManeuver = { [weak self] peakG in
            self?.recordHardManeuver(peakG: peakG)
        }
        motionService.start()

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
        motionService.stop()
        tracker.stop()
        context = tracker.context
        watchLink.push(context: context, isDriving: false)
        if let trip = currentTrip {
            let willSave = trip.points.count >= 2
            store?.endTrip(
                trip,
                at: context.tripEnd ?? .now,
                distance: context.tripDistance,
                maxSpeed: context.tripMaxSpeed
            )
            currentTrip = nil
            // A saved drive with zero events extends the clean streak —
            // that's worth hearing about; a broken one stays silent.
            if willSave, eventsThisDrive == 0, let streak = store?.streak().current {
                alerts.deliverCleanDrive(streak: streak)
            }
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
            watchLink.push(context: context, isDriving: isDriving)
        }

        autoEndIfParked()
    }

    /// Classifies a g-force burst as braking or acceleration using the GPS
    /// speed trend around it, and records it for the trip map / safety score.
    private func recordHardManeuver(peakG: Double) {
        guard isDriving else { return }
        let nowMph = context.speed.map { $0 * 2.236936 }
        if let mph = nowMph {
            recentSpeeds.append((.now, mph))
        }
        let earlier = recentSpeeds.last { Date.now.timeIntervalSince($0.0) >= 1.5 }?.1
        let kind: String
        if let nowMph, let earlier {
            kind = nowMph < earlier ? "hardBraking" : "hardAcceleration"
        } else {
            kind = "hardBraking" // the conservative guess when GPS can't say
        }
        store?.saveEvent(kind: kind, peakG: peakG, coordinate: context.coordinate, speedMph: nowMph)
        eventsThisDrive += 1
    }

    /// Deterministic speed alerts, mirrored to a paired Apple Watch by iOS.
    private func evaluateSpeedRules() {
        let mph = { (metersPerSecond: Double) in metersPerSecond * 2.236936 }
        if let speed = context.speed.map(mph) {
            recentSpeeds.append((.now, speed))
            recentSpeeds.removeAll { Date.now.timeIntervalSince($0.0) > 6 }
        }
        let events = alertEngine.process(
            speedMph: context.speed.map(mph),
            postedLimitMph: context.road?.speedLimit.map(mph) ?? nil
        )
        if !events.isEmpty {
            let speedMphNow = context.speed.map { Int(($0 * 2.236936).rounded()) }
            let coached = events.map { event -> (SpeedAlertEngine.Event, String) in
                alertOccurrences += 1
                return (event, Coach.fromSettings(
                    for: event, speedMph: speedMphNow, occurrence: alertOccurrences
                ))
            }
            alerts.deliverCoached(coached)
            watchLink.send(events)
            if Coach.spokenEnabled, let nudge = coached.last?.1 {
                speakCoaching?(nudge)
            }
        }

        // Silent score bookkeeping - never notifies, always records.
        let mphNow = context.speed.map(mph)
        for event in scoreRecorder.process(speedMph: mphNow, postedLimitMph: context.road?.speedLimit.map(mph) ?? nil) {
            switch event {
            case .overPostedLimit:
                store?.saveEvent(kind: "overLimit", peakG: 0, coordinate: context.coordinate, speedMph: mphNow)
                eventsThisDrive += 1
            case .overPostedMargin:
                store?.saveEvent(kind: "wellOverLimit", peakG: 0, coordinate: context.coordinate, speedMph: mphNow)
                eventsThisDrive += 1
            default:
                break
            }
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
