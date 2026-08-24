import Foundation

/// Presentation-only conversions from `DrivingContext`'s SI values.
/// US units for the prototype; localization can come later.
enum DriveFormatting {
    static func milesPerHour(fromMetersPerSecond speed: Double) -> Int {
        Int((speed * 2.236936).rounded())
    }

    static func miles(fromMeters meters: Double) -> String {
        String(format: "%.1f mi", meters / 1609.344)
    }

    static func feet(fromMeters meters: Double) -> Int {
        Int((meters * 3.28084).rounded())
    }

    /// 16-wind compass name for a course in degrees from true north.
    static func cardinal(fromCourse degrees: Double) -> String {
        let names = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                     "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalized = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        let index = Int((positive / 22.5).rounded()) % 16
        return names[index]
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func coordinate(_ coordinate: Coordinate) -> String {
        String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
}
