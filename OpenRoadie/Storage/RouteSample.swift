import Foundation

/// One recorded moment on a route, decoupled from SwiftData so route
/// analysis (`PaceBands`, `TripSegmenter`) is pure and unit-testable.
///
/// Route points are only written when the position meaningfully advances,
/// which makes the *gaps between* samples load-bearing: a twenty-minute
/// stop is not twenty minutes of zero-speed points, it is two points
/// twenty minutes apart. Everything downstream reads the gaps, not the
/// per-fix speed, so a stop is measured even though nothing was recorded
/// during it.
struct RouteSample: Equatable, Sendable {
    var timestamp: Date
    var coordinate: Coordinate

    init(timestamp: Date, coordinate: Coordinate) {
        self.timestamp = timestamp
        self.coordinate = coordinate
    }
}

extension RouteSample {
    init(_ point: TripPoint) {
        self.init(
            timestamp: point.timestamp,
            coordinate: Coordinate(latitude: point.latitude, longitude: point.longitude)
        )
    }
}

extension Trip {
    /// This drive's route as pure samples, in time order.
    var routeSamples: [RouteSample] {
        route.map(RouteSample.init)
    }
}
