import Foundation
import SwiftData

/// A geo-anchored memory: something the driver asked Roadie to remember —
/// a spot, an idea, a landmark question. Stays on-device like everything else.
@Model
final class DriveNote {
    var timestamp: Date
    var latitude: Double?
    var longitude: Double?
    var text: String

    init(text: String, coordinate: Coordinate?, timestamp: Date = .now) {
        self.text = text
        self.timestamp = timestamp
        latitude = coordinate?.latitude
        longitude = coordinate?.longitude
    }

    var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}
