import Foundation
import SwiftData

/// A recorded walk trail — breadcrumbs laid after a drive ends by
/// walk-away, while the app is still alive from the drive. Deliberately
/// its own model, NOT a Trip: walks must never leak into driving stats,
/// scores, or exports.
@Model
final class WalkPath {
    var startDate: Date
    var endDate: Date
    /// Meters, as accumulated by the same tracker rules drives use.
    var distance: Double
    /// The trail, as parallel arrays (SwiftData stores scalar arrays
    /// directly; a relationship table would be overkill for ≤400 points).
    var latitudes: [Double]
    var longitudes: [Double]

    init(startDate: Date, endDate: Date, distance: Double, coordinates: [Coordinate]) {
        self.startDate = startDate
        self.endDate = endDate
        self.distance = distance
        self.latitudes = coordinates.map(\.latitude)
        self.longitudes = coordinates.map(\.longitude)
    }

    var coordinates: [Coordinate] {
        zip(latitudes, longitudes).map { Coordinate(latitude: $0, longitude: $1) }
    }
}
