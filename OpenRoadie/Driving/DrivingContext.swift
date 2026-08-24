import Foundation

/// A geographic coordinate.
///
/// CoreLocation's `CLLocationCoordinate2D` isn't `Equatable` or `Codable`;
/// keeping the canonical driving state free of framework types makes it easy
/// to test, and later to persist or hand to an agent.
struct Coordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
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

    /// Direction of travel in degrees from true north (0–360).
    /// `nil` when unknown — for example while stationary.
    var course: Double?

    /// When the current (or most recently ended) drive started.
    var tripStart: Date?

    /// When the drive ended. `nil` while a drive is active.
    var tripEnd: Date?

    /// Accumulated driving distance in meters for the current drive.
    var tripDistance: Double = 0

    /// Elapsed trip time. For an active drive, measured up to `date`;
    /// for an ended drive, frozen at `tripEnd`.
    func tripDuration(at date: Date = .now) -> TimeInterval? {
        guard let tripStart else { return nil }
        return max(0, (tripEnd ?? date).timeIntervalSince(tripStart))
    }
}
