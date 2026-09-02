import Foundation

/// Weather at a moment of a drive, as recorded on the trip.
/// Codes are WMO weather interpretation codes (what Open-Meteo returns).
struct TripWeather: Equatable, Sendable {
    var wmoCode: Int
    var temperatureC: Double
    var precipitationMm: Double
    var windKph: Double
}

/// WMO weather code → human label + SF Symbol. Pure and unit-tested;
/// unknown codes get an honest generic answer, never an invented one.
enum WeatherCode {
    static func label(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55, 56, 57: "Drizzle"
        case 61, 63, 66, 80, 81: "Rain"
        case 65, 82: "Heavy rain"
        case 71, 73, 75, 77, 85, 86: "Snow"
        case 95, 96, 99: "Thunderstorm"
        default: "Unknown"
        }
    }

    static func symbol(_ code: Int) -> String {
        switch code {
        case 0, 1: "sun.max"
        case 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51, 53, 55, 56, 57: "cloud.drizzle"
        case 61, 63, 66, 80, 81: "cloud.rain"
        case 65, 82: "cloud.heavyrain"
        case 71, 73, 75, 77, 85, 86: "cloud.snow"
        case 95, 96, 99: "cloud.bolt.rain"
        default: "questionmark.circle"
        }
    }
}

/// Fetches historical/recent weather from Open-Meteo (open-meteo.com):
/// free, keyless open data, non-commercial use — the same posture as
/// Overpass for roads. The only thing sent is a coordinate and a date.
///
/// `timeformat=unixtime` keeps everything in epoch seconds so no local
/// time-zone arithmetic can go wrong.
final class WeatherService: Sendable {
    /// Settings toggle; on by default, same as road awareness.
    static let enabledKey = "tripWeatherEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Hourly series as Open-Meteo returns it.
    struct Response: Decodable {
        struct Hourly: Decodable {
            var time: [Int]
            var temperature_2m: [Double?]
            var precipitation: [Double?]
            var weather_code: [Int?]
            var wind_speed_10m: [Double?]
        }
        var hourly: Hourly
    }

    /// Nearest-hour sample from a decoded response. Pure and unit-tested.
    /// `nil` when the response has no hour within 2 h of the target —
    /// an uncertain bucket is a real bucket, not a fudge.
    static func nearest(to date: Date, in response: Response) -> TripWeather? {
        let target = Int(date.timeIntervalSince1970)
        let hourly = response.hourly
        guard let index = hourly.time.indices.min(by: {
            abs(hourly.time[$0] - target) < abs(hourly.time[$1] - target)
        }) else { return nil }
        guard abs(hourly.time[index] - target) <= 7200 else { return nil }
        guard let code = hourly.weather_code[index],
              let temp = hourly.temperature_2m[index] else { return nil }
        return TripWeather(
            wmoCode: code,
            temperatureC: temp,
            precipitationMm: hourly.precipitation[index] ?? 0,
            windKph: hourly.wind_speed_10m[index] ?? 0
        )
    }

    /// Recent dates come from the forecast API's `past_days`; older ones
    /// from the archive API (which lags a few days behind the present).
    static func url(for coordinate: Coordinate, date: Date, now: Date = .now) -> URL? {
        let fields = "temperature_2m,precipitation,weather_code,wind_speed_10m"
        let age = now.timeIntervalSince(date)
        if age < 6 * 86_400 {
            return URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&hourly=\(fields)&past_days=6&forecast_days=1&timeformat=unixtime")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        // A day either side of the target so UTC day boundaries can't clip
        // the hour we need.
        let start = formatter.string(from: date.addingTimeInterval(-86_400))
        let end = formatter.string(from: date.addingTimeInterval(86_400))
        return URL(string: "https://archive-api.open-meteo.com/v1/archive?latitude=\(coordinate.latitude)&longitude=\(coordinate.longitude)&start_date=\(start)&end_date=\(end)&hourly=\(fields)&timeformat=unixtime")
    }

    /// Best-effort: `nil` on any failure, and the caller just tries again
    /// another day. Weather is garnish, never load-bearing.
    func weather(at coordinate: Coordinate, date: Date) async -> TripWeather? {
        guard Self.isEnabled, let url = Self.url(for: coordinate, date: date) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return Self.nearest(to: date, in: decoded)
    }
}
