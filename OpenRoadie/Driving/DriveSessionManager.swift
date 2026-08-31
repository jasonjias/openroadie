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
    /// True while the drive is stopped but still recording — a gas stop, a
    /// drive-thru, a jam. The trip stays open and resumes on its own.
    private(set) var isPaused = false
    private(set) var lastErrorDescription: String?

    private let locationService = LocationService()
    private let roadService = RoadService()
    private let motionService = MotionService()
    private let alerts = AlertCenter()
    private let chime = ChimePlayer()
    private let hazards = HazardService()
    private let watchLink = PhoneWatchLink()
    private let store: TripStore?
    private var tracker = TripTracker()
    private var alertEngine = SpeedAlertEngine()
    /// Always-on recorder for the Drive Score: counts posted-limit and
    /// +5-over crossings regardless of whether the user enabled alerts.
    private var scoreRecorder = SpeedAlertEngine()
    private var updatesTask: Task<Void, Never>?
    private var currentTrip: Trip?
    /// Speed-based pause/end detection (the stationary flag alone was
    /// unreliable in the field).
    private var parkDetector = ParkDetector()
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
    private var corneringDetector = CorneringDetector()
    private var phoneUseDetector = PhoneUseDetector()
    /// Latest yaw rate (rad/s) — read by the drive scene for turn lean.
    /// ObservationIgnored: it updates at 10Hz and must not churn SwiftUI.
    @ObservationIgnored private(set) var latestYawRate: Double = 0

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
        isPaused = false
        parkDetector.reset()
        alertEngine.config = AlertCenter.configFromDefaults()
        alertEngine.reset()
        // Scoring counts SUSTAINED speeding only, at most once every few
        // minutes: a day of ordinary driving shouldn't collect a fistful
        // of events for briefly drifting over on a downhill.
        scoreRecorder.config = SpeedAlertEngine.Config(
            sustainedSeconds: 15,
            minimumIntervalSeconds: 300,
            alertOverPostedLimit: true,
            postedMarginIsAdaptive: true
        )
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
        corneringDetector = CorneringDetector()
        phoneUseDetector = PhoneUseDetector()
        hazards.startDrive()
        motionService.onRotationSample = { [weak self] yawRate, nonYaw in
            self?.processRotation(yawRate: yawRate, nonYaw: nonYaw)
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
        isPaused = false
        latestYawRate = 0
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
            checkHazards()
            watchLink.push(context: context, isDriving: isDriving)
        }

        applyParkDecision()
    }

    /// Classifies a g-force burst as braking or acceleration using the GPS
    /// speed trend around it, and records it for the trip map / safety score.
    private func recordHardManeuver(peakG: Double) {
        guard isDriving else { return }
        let nowMph = context.speed.map { $0 * 2.236936 }
        if let mph = nowMph {
            recentSpeeds.append((.now, mph))
        }
        // A g-spike while (near-)stationary is the phone being handled, a
        // door slam, a pothole in a parking spot — not driving. Field data:
        // "hard acceleration, 0 mph, 1.23 g" while walking into a restaurant.
        let recentMax = recentSpeeds
            .filter { Date.now.timeIntervalSince($0.0) <= 3 }
            .map(\.1)
            .max() ?? nowMph ?? 0
        guard recentMax >= 8 else { return }
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

    /// Cornering (yaw × speed = lateral g) and phone handling (sustained
    /// non-yaw rotation at speed) — both saved as score events.
    private func processRotation(yawRate: Double, nonYaw: Double) {
        latestYawRate = yawRate
        guard isDriving, let speed = context.speed else { return }
        if let peakG = corneringDetector.process(yawRate: yawRate, speedMps: speed, at: .now) {
            store?.saveEvent(kind: "harshCornering", peakG: peakG, coordinate: context.coordinate, speedMph: speed * 2.236936)
            eventsThisDrive += 1
        }
        // Handling only counts at real road speed — passengers and parked
        // fiddling are not distracted driving.
        if speed * 2.236936 >= 10,
           let duration = phoneUseDetector.process(nonYawRotation: nonYaw, at: .now) {
            store?.saveEvent(kind: "phoneUse", peakG: duration, coordinate: context.coordinate, speedMph: speed * 2.236936)
            eventsThisDrive += 1
        }
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
            // Tiered response, Tesla-calibrated: crossing the posted limit
            // is a chime (or nothing); the coaching voice is saved for
            // genuinely-over (the margin tier) and the driver's own max.
            var coached: [(SpeedAlertEngine.Event, String)] = []
            for event in events {
                if case .overPostedLimit = event {
                    switch AlertCenter.overLimitStyle {
                    case .off: continue
                    case .chime:
                        chime.play()
                        continue
                    case .coach: break // falls through to full coaching
                    }
                }
                alertOccurrences += 1
                coached.append((event, Coach.fromSettings(
                    for: event, speedMph: speedMphNow, occurrence: alertOccurrences
                )))
            }
            if !coached.isEmpty {
                alerts.deliverCoached(coached)
                watchLink.send(coached.map(\.0))
                if Coach.spokenEnabled, let nudge = coached.last?.1 {
                    speakCoaching?(nudge)
                }
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

    /// Crash-data road warnings: approaching a spot where multiple fatal
    /// crashes are on record (bundled NHTSA FARS extract) chimes and
    /// notifies, once per zone per drive.
    private func checkHazards() {
        guard HazardService.isEnabled, isDriving,
              let coordinate = context.coordinate,
              let hazard = hazards.check(coordinate) else { return }
        chime.play()
        alerts.deliverHazard(crashes: hazard.crashes)
    }

    /// Stopping pauses the drive; only a long settled stop ends it.
    ///
    /// Recording continues through a pause, so a gas stop or a jam is a
    /// quiet stretch inside one drive rather than two drives with a
    /// notification pair between them. `TripSegmenter` splits the stored
    /// route into legs afterwards, which is where the judgment call about
    /// "was that one trip or two?" now lives — reversible, and off the
    /// critical path.
    private func applyParkDecision() {
        switch parkDetector.process(speedMps: context.speed, stationary: isStationary, at: .now) {
        case .unchanged:
            break
        case .paused:
            isPaused = true
        case .resumed:
            isPaused = false
        case .ended:
            // The driver can opt out of ever ending automatically; the
            // pause bookkeeping above stays on either way. Hands-free
            // overrides the opt-out — with no Start Drive button, a drive
            // that never ends itself would run until the battery died.
            guard AlertCenter.autoEndEnabled || AutoDriveMonitor.handsFree else { break }
            stopDrive()
            alerts.deliverDriveAutoEnded()
        }
    }

    /// Road awareness rides on top of telemetry: match against the local road
    /// cache each fix, refetching the cache as the drive moves. Optional and
    /// best-effort — the drive works identically with it off or offline.
    private func attachRoadInfo() {
        guard RoadService.isEnabled, let coordinate = context.coordinate else {
            context.road = nil
            context.roadCurve = nil
            return
        }
        roadService.refreshIfNeeded(around: coordinate)
        // Course + speed let the matcher reject perpendicular overpasses.
        context.road = roadService.currentRoad(
            at: coordinate, courseDegrees: context.course, speedMps: context.speed
        )
        context.roadCurve = roadService.upcomingCurve(
            at: coordinate, courseDegrees: context.course, speedMps: context.speed
        )
    }
}
