import Foundation
import SwiftData

/// A hard-maneuver event detected during a drive — the raw material for the
/// safety score and, opt-in, for anonymized community contribution.
@Model
final class DriveEvent {
    var timestamp: Date
    var latitude: Double?
    var longitude: Double?
    /// "hardBraking" or "hardAcceleration".
    var kind: String
    var peakG: Double
    var speedMph: Double?

    init(kind: String, peakG: Double, coordinate: Coordinate?, speedMph: Double?, timestamp: Date = .now) {
        self.kind = kind
        self.peakG = peakG
        self.timestamp = timestamp
        self.speedMph = speedMph
        latitude = coordinate?.latitude
        longitude = coordinate?.longitude
    }

    var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

/// Builds the anonymized export: coordinates coarsened to ~110 m, timestamps
/// reduced to date + hour, no identity, no route linkage. What you'd want a
/// stranger to be able to see, and nothing more.
enum CommunityExport {
    static func anonymized(_ events: [DriveEvent]) -> [[String: Any]] {
        events.compactMap { event in
            guard let coordinate = event.coordinate else { return nil }
            var entry: [String: Any] = [
                "kind": event.kind,
                "lat": (coordinate.latitude * 1000).rounded() / 1000,
                "lon": (coordinate.longitude * 1000).rounded() / 1000,
                "peakG": (event.peakG * 100).rounded() / 100,
                "dateHour": dateHour(event.timestamp),
            ]
            if let speed = event.speedMph {
                entry["speedMphBucket"] = Int(speed / 10) * 10
            }
            return entry
        }
    }

    static func json(_ events: [DriveEvent]) throws -> Data {
        let payload: [String: Any] = [
            "format": "openroadie-community-events",
            "version": 1,
            "events": anonymized(events),
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    static func dateHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
