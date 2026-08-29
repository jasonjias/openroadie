import Foundation

/// Your complete driving record, as a file you own.
///
/// Distinct from `CommunityExport`, which strips and coarsens everything
/// for sharing: this is the full fidelity copy — every trip, every route
/// point, every event, every note — so the data OpenRoadie keeps on your
/// phone is never a hostage. Pure and deterministic; no I/O here.
enum PersonalExport {
    struct Payload: Codable, Equatable {
        var format = "openroadie.personal.v1"
        var exportedAt: Date
        var trips: [ExportedTrip]
        var events: [ExportedEvent]
        var notes: [ExportedNote]
    }

    struct ExportedTrip: Codable, Equatable {
        var start: Date
        var end: Date?
        var distanceMeters: Double
        var maxSpeedMps: Double?
        var route: [ExportedPoint]
    }

    struct ExportedPoint: Codable, Equatable {
        var time: Date
        var latitude: Double
        var longitude: Double
        var speedMps: Double?
        var altitudeMeters: Double?
        var speedLimitMps: Double?
    }

    struct ExportedEvent: Codable, Equatable {
        var kind: String
        var time: Date
        var peakG: Double
        var speedMph: Double?
        var latitude: Double?
        var longitude: Double?
    }

    struct ExportedNote: Codable, Equatable {
        var text: String
        var time: Date
        var latitude: Double?
        var longitude: Double?
    }

    static func payload(
        trips: [Trip],
        events: [DriveEvent],
        notes: [DriveNote],
        exportedAt: Date = .now
    ) -> Payload {
        Payload(
            exportedAt: exportedAt,
            trips: trips
                .sorted { $0.startDate < $1.startDate }
                .map { trip in
                    ExportedTrip(
                        start: trip.startDate,
                        end: trip.endDate,
                        distanceMeters: trip.distance,
                        maxSpeedMps: trip.maxSpeed,
                        route: trip.route.map {
                            ExportedPoint(
                                time: $0.timestamp,
                                latitude: $0.latitude,
                                longitude: $0.longitude,
                                speedMps: $0.speed,
                                altitudeMeters: $0.altitude,
                                speedLimitMps: $0.speedLimit
                            )
                        }
                    )
                },
            events: events
                .sorted { $0.timestamp < $1.timestamp }
                .map {
                    ExportedEvent(
                        kind: $0.kind,
                        time: $0.timestamp,
                        peakG: $0.peakG,
                        speedMph: $0.speedMph,
                        latitude: $0.coordinate?.latitude,
                        longitude: $0.coordinate?.longitude
                    )
                },
            notes: notes
                .sorted { $0.timestamp < $1.timestamp }
                .map {
                    ExportedNote(
                        text: $0.text,
                        time: $0.timestamp,
                        latitude: $0.coordinate?.latitude,
                        longitude: $0.coordinate?.longitude
                    )
                }
        )
    }

    static func json(
        trips: [Trip],
        events: [DriveEvent],
        notes: [DriveNote],
        exportedAt: Date = .now
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload(trips: trips, events: events, notes: notes, exportedAt: exportedAt))
    }

    /// A GPX track per trip — the interchange format every mapping tool
    /// reads, so routes can leave for anywhere.
    static func gpx(trips: [Trip]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="OpenRoadie" xmlns="http://www.topografix.com/GPX/1/1">"#,
        ]
        for trip in trips.sorted(by: { $0.startDate < $1.startDate }) {
            let route = trip.route
            guard !route.isEmpty else { continue }
            lines.append("  <trk>")
            lines.append("    <name>Drive \(formatter.string(from: trip.startDate))</name>")
            lines.append("    <trkseg>")
            for point in route {
                var segment = #"      <trkpt lat="\#(point.latitude)" lon="\#(point.longitude)">"#
                segment += "<time>\(formatter.string(from: point.timestamp))</time>"
                if let altitude = point.altitude {
                    segment += "<ele>\(altitude)</ele>"
                }
                segment += "</trkpt>"
                lines.append(segment)
            }
            lines.append("    </trkseg>")
            lines.append("  </trk>")
        }
        lines.append("</gpx>")
        return lines.joined(separator: "\n")
    }
}
