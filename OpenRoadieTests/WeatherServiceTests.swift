import Foundation
import Testing
@testable import OpenRoadie

struct WeatherServiceTests {
    private let fixture = """
    {"hourly":{"time":[1756700000,1756703600,1756707200],
    "temperature_2m":[21.5,23.0,24.5],
    "precipitation":[0.0,0.2,null],
    "weather_code":[2,61,3],
    "wind_speed_10m":[10.0,12.5,null]}}
    """.data(using: .utf8)!

    @Test func picksTheNearestHour() throws {
        let response = try JSONDecoder().decode(WeatherService.Response.self, from: fixture)
        let weather = WeatherService.nearest(to: Date(timeIntervalSince1970: 1_756_703_000), in: response)
        #expect(weather?.wmoCode == 61)
        #expect(weather?.temperatureC == 23.0)
        #expect(weather?.precipitationMm == 0.2)
    }

    /// A target hours away from anything in the response is unknown, not
    /// approximated — an uncertain bucket is a real bucket.
    @Test func farFromAnySampleMeansNoAnswer() throws {
        let response = try JSONDecoder().decode(WeatherService.Response.self, from: fixture)
        #expect(WeatherService.nearest(to: Date(timeIntervalSince1970: 1_756_800_000), in: response) == nil)
    }

    @Test func nullsInTheSeriesFallBackHonestly() throws {
        let response = try JSONDecoder().decode(WeatherService.Response.self, from: fixture)
        let weather = WeatherService.nearest(to: Date(timeIntervalSince1970: 1_756_707_200), in: response)
        #expect(weather?.wmoCode == 3)
        #expect(weather?.precipitationMm == 0)   // null → zero, not invented rain
        #expect(weather?.windKph == 0)
    }

    @Test func recentDatesUseTheForecastAPIOlderOnesTheArchive() {
        let here = Coordinate(latitude: 37.4, longitude: -122.1)
        let now = Date(timeIntervalSince1970: 1_756_800_000)
        let recent = WeatherService.url(for: here, date: now.addingTimeInterval(-2 * 86_400), now: now)
        let old = WeatherService.url(for: here, date: now.addingTimeInterval(-30 * 86_400), now: now)
        #expect(recent?.host() == "api.open-meteo.com")
        #expect(old?.host() == "archive-api.open-meteo.com")
        #expect(old?.absoluteString.contains("start_date=") == true)
    }

    @Test func wmoCodesMapToLabelsAndSymbols() {
        #expect(WeatherCode.label(0) == "Clear")
        #expect(WeatherCode.label(63) == "Rain")
        #expect(WeatherCode.label(75) == "Snow")
        #expect(WeatherCode.symbol(95) == "cloud.bolt.rain")
        // Unknown codes are honest, not invented.
        #expect(WeatherCode.label(42) == "Unknown")
    }

    @Test func fahrenheitConversion() {
        #expect(DriveFormatting.fahrenheit(fromCelsius: 0) == 32)
        #expect(DriveFormatting.fahrenheit(fromCelsius: 23) == 73)
    }
}
