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
    /// Degrees from true north. Values `< 0` mean course is unknown.
    var course: Double
    var timestamp: Date
}

extension LocationSample {
    init(_ location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed,
            course: location.course,
            timestamp: location.timestamp
        )
    }
}

/// Deterministic accumulator that turns raw GPS samples into a `DrivingContext`.
///
/// This is pure state-machine logic — no CoreLocation sessions, no AI, no UI —
/// so it can be exercised directly in unit tests.
struct TripTracker {
    private(set) var context = DrivingContext()
    private(set) var isActive = false

    /// Samples with worse horizontal accuracy than this are discarded entirely.
    static let maxHorizontalAccuracy: Double = 50

    /// Minimum movement (meters) from the last counted point before distance
    /// accumulates. Below this, stationary GPS drift would masquerade as travel.
    /// The effective threshold is `max(minimumDistanceStep, sample accuracy)`.
    static let minimumDistanceStep: Double = 10

    /// Implied speeds above this (~200 mph) between consecutive counted points
    /// are treated as GPS glitches, not travel.
    static let maxPlausibleSpeed: Double = 90

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

    mutating func process(_ sample: LocationSample) {
        guard isActive else { return }
        guard sample.horizontalAccuracy > 0,
              sample.horizontalAccuracy <= Self.maxHorizontalAccuracy else { return }

        let coordinate = Coordinate(latitude: sample.latitude, longitude: sample.longitude)
        context.timestamp = sample.timestamp
        context.coordinate = coordinate
        context.horizontalAccuracy = sample.horizontalAccuracy
        context.speed = sample.speed >= 0 ? sample.speed : nil
        context.course = sample.course >= 0 ? sample.course : nil

        accumulateDistance(to: coordinate, at: sample.timestamp, accuracy: sample.horizontalAccuracy)
    }

    private mutating func accumulateDistance(to coordinate: Coordinate, at timestamp: Date, accuracy: Double) {
        guard let anchor else {
            self.anchor = (coordinate, timestamp)
            return
        }

        let elapsed = timestamp.timeIntervalSince(anchor.timestamp)
        guard elapsed > 0 else { return }

        let delta = Self.distance(from: anchor.coordinate, to: coordinate)

        // A teleport-like jump is a glitch: re-anchor at the new position so
        // later movement is measured from there, but count nothing for the jump.
        if delta / elapsed > Self.maxPlausibleSpeed {
            self.anchor = (coordinate, timestamp)
            return
        }

        if delta >= max(Self.minimumDistanceStep, accuracy) {
            context.tripDistance += delta
            self.anchor = (coordinate, timestamp)
        }
    }

    /// Great-circle distance in meters.
    static func distance(from: Coordinate, to: Coordinate) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
