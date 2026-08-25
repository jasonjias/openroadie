import Foundation

/// A geographic coordinate.
///
/// CoreLocation's `CLLocationCoordinate2D` isn't `Equatable` or `Codable`;
/// keeping the canonical driving state free of framework types makes it easy
/// to test, and later to persist or hand to an agent.
struct Coordinate: Equatable, Sendable, Codable {
    var latitude: Double
    var longitude: Double
}

/// What OpenRoadie knows about the road currently being driven, resolved from
/// OpenStreetMap data. All fields are `nil` when the source doesn't know.
struct RoadInfo: Equatable, Sendable {
    /// Street name, e.g. "El Camino Real".
    var name: String?
    /// Route reference, e.g. "US 101" or "CA 82".
    var ref: String?
    /// Posted speed limit in meters per second.
    var speedLimit: Double?

    /// The best human label available: name, else ref.
    var displayName: String? { name ?? ref }
}

/// The canonical snapshot of what OpenRoadie currently knows about the drive.
///
/// Telemetry (GPS today; road data, motion, and more later) produces it.
/// Consumers — the UI now; rules, the agent, and storage in later milestones —
/// only ever read it. Values the system genuinely doesn't know are `nil`,
/// never invented.
struct DrivingContext: Equatable, Sendable {
    /// Timestamp of the most recent accepted GPS sample.
    var timestamp: Date?

    /// Last known position.
    var coordinate: Coordinate?

    /// Uncertainty radius of `coordinate`, in meters.
    var horizontalAccuracy: Double?

    /// Ground speed in meters per second. `nil` when GPS can't determine it.
    var speed: Double?

    /// One-sigma uncertainty of `speed`, in meters per second.
    var speedAccuracy: Double?

    /// Direction of travel in degrees from true north (0–360).
    /// `nil` when unknown — for example while stationary.
    var course: Double?

    /// Altitude above mean sea level, in meters. `nil` when unknown.
    var altitude: Double?

    /// The road currently being driven, when road awareness is enabled and
    /// OpenStreetMap knows it. Populated by `RoadService`, not by telemetry.
    var road: RoadInfo?

    /// When the current (or most recently ended) drive started.
    var tripStart: Date?

    /// When the drive ended. `nil` while a drive is active.
    var tripEnd: Date?

    /// Accumulated driving distance in meters for the current drive.
    var tripDistance: Double = 0

    /// Highest valid GPS speed seen this drive, in meters per second.
    var tripMaxSpeed: Double?

    /// Elapsed trip time. For an active drive, measured up to `date`;
    /// for an ended drive, frozen at `tripEnd`.
    func tripDuration(at date: Date = .now) -> TimeInterval? {
        guard let tripStart else { return nil }
        return max(0, (tripEnd ?? date).timeIntervalSince(tripStart))
    }
}
