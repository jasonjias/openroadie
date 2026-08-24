import Foundation

/// Deterministic text the agent's tools hand to the language model.
///
/// The model never sees raw structs — it sees these strings. Keeping the
/// rendering pure and tested means the AI layer can only ever describe what
/// telemetry actually knows; unknown stays "unknown".
enum RoadieToolFormatting {
    static func describeDrive(_ context: DrivingContext, isDriving: Bool) -> String {
        var lines: [String] = []
        lines.append(isDriving ? "Drive status: active" : "Drive status: no active drive")

        if let coordinate = context.coordinate {
            lines.append("Position: \(DriveFormatting.coordinate(coordinate))")
        } else {
            lines.append("Position: unknown")
        }

        if let speed = context.speed {
            lines.append("Speed: \(DriveFormatting.milesPerHour(fromMetersPerSecond: speed)) mph")
        } else {
            lines.append("Speed: unknown")
        }

        if let course = context.course {
            lines.append("Heading: \(DriveFormatting.cardinal(fromCourse: course)) (\(Int(course.rounded()))°)")
        } else {
            lines.append("Heading: unknown")
        }

        if let road = context.road {
            var roadLine = "Road: \(road.displayName ?? "unnamed")"
            if let limit = road.speedLimit {
                roadLine += ", speed limit \(DriveFormatting.milesPerHour(fromMetersPerSecond: limit)) mph"
            }
            lines.append(roadLine)
        } else {
            lines.append("Road: unknown")
        }

        if let duration = context.tripDuration() {
            lines.append("Trip so far: \(spokenDuration(duration)), \(DriveFormatting.miles(fromMeters: context.tripDistance))")
        }
        if let maxSpeed = context.tripMaxSpeed {
            lines.append("Top speed this trip: \(DriveFormatting.milesPerHour(fromMetersPerSecond: maxSpeed)) mph")
        }

        return lines.joined(separator: "\n")
    }

    static func describePlaces(
        _ results: [(place: Place, distance: Double)],
        category: PlaceCategory,
        origin: Coordinate,
        limit: Int = 6
    ) -> String {
        guard !results.isEmpty else {
            return "No \(category.title.lowercased()) found within about 2 miles."
        }
        let lines = results.prefix(limit).map { result in
            let direction = DriveFormatting.cardinal(
                fromCourse: PlaceGeometry.bearing(from: origin, to: result.place.coordinate)
            )
            return "\(result.place.displayName) — \(DriveFormatting.shortDistance(fromMeters: result.distance)) \(direction)"
        }
        return "Nearest \(category.title.lowercased()) (straight-line distances):\n" + lines.joined(separator: "\n")
    }

    static func describeTrips(_ trips: [Trip]) -> String {
        guard !trips.isEmpty else { return "No recorded trips yet." }
        let lines = trips.map { trip in
            var line = trip.startDate.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
            line += " — \(DriveFormatting.miles(fromMeters: trip.distance))"
            if let duration = trip.duration {
                line += " in \(spokenDuration(duration))"
            }
            if let maxSpeed = trip.maxSpeed {
                line += ", top speed \(DriveFormatting.milesPerHour(fromMetersPerSecond: maxSpeed)) mph"
            }
            return line
        }
        return "Recent trips, newest first:\n" + lines.joined(separator: "\n")
    }

    /// "4 min", "1 hr 5 min" — durations phrased for a spoken-style answer.
    static func spokenDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        if totalMinutes < 1 { return "under a minute" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr"
        }
        return "\(minutes) min"
    }
}
