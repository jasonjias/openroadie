import CoreLocation
import Foundation

/// One GPS fix, decoupled from `CLLocation` so telemetry logic can be tested
/// without hardware. Negative values carry CoreLocation's "invalid" meaning.
struct LocationSample: Sendable {
    var latitude: Double
    var longitude: Double
    /// Meters. Values `<= 0` mean the fix is invalid.
    var horizontalAccuracy: Double
    /// Meters per second. Values `< 0` mean speed is unknown.
    var speed: Double
    /// One-sigma speed uncertainty in m/s. Values `< 0` mean unknown.
    var speedAccuracy: Double
    /// Degrees from true north. Values `< 0` mean course is unknown.
    var course: Double
    /// Meters above sea level. Valid only when `verticalAccuracy > 0`.
    var altitude: Double
    /// Meters. Values `<= 0` mean `altitude` is invalid.
    var verticalAccuracy: Double
    var timestamp: Date
}

extension LocationSample {
    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            speedAccuracy: location.speedAccuracy,
            course: location.course,
            altitude: location.altitude,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: location.timestamp
        )
    }
}

/// Deterministic accumulator that turns raw GPS samples into a `DrivingContext`.
///
/// This is pure state-machine logic — no CoreLocation sessions, no AI, no UI —
/// so it can be exercised directly in unit tests.
struct TripTracker {
    /// Filter thresholds. Defaults are the driving values these were born
    /// as; walks need their own scale (see `walking`).
    struct Config: Equatable {
        /// Samples with worse horizontal accuracy than this are discarded.
        var maxHorizontalAccuracy: Double = 50
        /// Minimum movement (meters) from the last counted point before
        /// distance accumulates. Below this, stationary GPS drift would
        /// masquerade as travel. Effective threshold is
        /// `max(minimumDistanceStep, sample accuracy)`.
        var minimumDistanceStep: Double = 10
        /// Implied speeds above this between consecutive counted points are
        /// GPS glitches, not travel. ~200 mph for a car.
        var maxPlausibleSpeed: Double = 90
    }

    /// Walking scale. Ten-meter steps are coarse for a footpath, so this
    /// halves them — and the accuracy gate TIGHTENS, because a fix with
    /// ±40 m of error would draw a random scribble rather than a route.
    /// The honest consequence: crisp trails outdoors, silence indoors,
    /// where nothing better than a scribble is available anyway.
    static let walking = Config(
        maxHorizontalAccuracy: 35,
        minimumDistanceStep: 5,
        maxPlausibleSpeed: 12
    )

    var config = Config()

    private(set) var context = DrivingContext()
    private(set) var isActive = false

    /// Samples with worse horizontal accuracy than this are discarded entirely.
    static let maxHorizontalAccuracy: Double = Config().maxHorizontalAccuracy

    /// Minimum movement (meters) from the last counted point before distance
    /// accumulates.
    static let minimumDistanceStep: Double = Config().minimumDistanceStep

    /// Implied speeds above this (~200 mph) between consecutive counted points
    /// are treated as GPS glitches, not travel.
    static let maxPlausibleSpeed: Double = Config().maxPlausibleSpeed

    /// The last position that contributed to `tripDistance`.
    private var anchor: (coordinate: Coordinate, timestamp: Date)?

    mutating func start(at date: Date = .now) {
        context = DrivingContext(tripStart: date)
        anchor = nil
        isActive = true
    }

    mutating func stop(at date: Date = .now) {
        guard isActive else { return }
        isActive = false
        context.tripEnd = date
    }

    /// What `process` did with a sample, so callers (like a trip recorder)
    /// can react without re-deriving the filtering rules.
    enum ProcessResult: Equatable {
        /// The sample failed quality filters (or no drive is active).
        case rejected
        /// The sample updated the context. `movedFromLastPoint` is true when
        /// the position advanced meaningfully — the moments worth recording
        /// as route points.
        case accepted(movedFromLastPoint: Bool)
    }

    @discardableResult
    mutating func process(_ sample: LocationSample) -> ProcessResult {
        guard isActive else { return .rejected }
        guard sample.horizontalAccuracy > 0,
              sample.horizontalAccuracy <= config.maxHorizontalAccuracy else { return .rejected }

        let coordinate = Coordinate(latitude: sample.latitude, longitude: sample.longitude)
        context.timestamp = sample.timestamp
        context.coordinate = coordinate
        context.horizontalAccuracy = sample.horizontalAccuracy
        context.speed = sample.speed >= 0 ? sample.speed : nil
        context.speedAccuracy = (sample.speed >= 0 && sample.speedAccuracy >= 0) ? sample.speedAccuracy : nil
        context.course = sample.course >= 0 ? sample.course : nil
        context.altitude = sample.verticalAccuracy > 0 ? sample.altitude : nil

        if let speed = context.speed, speed > (context.tripMaxSpeed ?? 0) {
            context.tripMaxSpeed = speed
        }

        let moved = accumulateDistance(to: coordinate, at: sample.timestamp, accuracy: sample.horizontalAccuracy)
        return .accepted(movedFromLastPoint: moved)
    }

    /// Returns true when the anchor advanced (first fix, real movement, or a
    /// glitch re-anchor) — i.e. the position is new enough to be worth keeping.
    private mutating func accumulateDistance(to coordinate: Coordinate, at timestamp: Date, accuracy: Double) -> Bool {
        guard let anchor else {
            self.anchor = (coordinate, timestamp)
            return true
        }

        let elapsed = timestamp.timeIntervalSince(anchor.timestamp)
        guard elapsed > 0 else { return false }

        let delta = Self.distance(from: anchor.coordinate, to: coordinate)

        // A teleport-like jump is a glitch: re-anchor at the new position so
        // later movement is measured from there, but count nothing for the jump.
        if delta / elapsed > config.maxPlausibleSpeed {
            self.anchor = (coordinate, timestamp)
            return true
        }

        if delta >= max(config.minimumDistanceStep, accuracy) {
            context.tripDistance += delta
            self.anchor = (coordinate, timestamp)
            return true
        }
        return false
    }

    /// Great-circle distance in meters.
    static func distance(from: Coordinate, to: Coordinate) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
