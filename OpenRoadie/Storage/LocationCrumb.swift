import Foundation
import SwiftData

/// One breadcrumb from an Always-on wake-up. iOS relaunches the app after
/// roughly 500 m of travel; each wake carries the position that triggered
/// it. Stored only while Always-on is enabled (the deal that setting
/// makes), only when no drive is recording (trips log themselves), and
/// pruned after seven days to match the motion history that gives crumbs
/// their meaning.
@Model
final class LocationCrumb {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Meters; wake fixes are cell/Wi-Fi grade, often 50-500 m.
    var accuracy: Double

    init(timestamp: Date, coordinate: Coordinate, accuracy: Double) {
        self.timestamp = timestamp
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.accuracy = accuracy
    }

    var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }
}
