import CoreLocation
import Foundation
import Observation

/// Live weather for the Drive tab: fetched around the current position,
/// cached for half an hour or ten kilometers, whichever breaks first.
/// Same Open-Meteo source and disclosure as trip weather — and gone
/// entirely when the Trip weather toggle is off.
@MainActor
@Observable
final class CurrentWeatherModel {
    private(set) var weather: TripWeather?

    private let service = WeatherService()
    private var fetchedAt: Date?
    private var fetchedNear: Coordinate?

    /// Uses the live drive's position when there is one; falls back to a
    /// one-shot fix only when location is already authorized — the weather
    /// garnish must never be what triggers a permission prompt.
    func refresh(around coordinate: Coordinate?) async {
        guard WeatherService.isEnabled else {
            weather = nil
            return
        }
        var position = coordinate
        if position == nil {
            let status = CLLocationManager().authorizationStatus
            guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
            position = await LocationService.currentFix()
        }
        guard let position else { return }
        if weather != nil, let fetchedAt, let fetchedNear,
           Date.now.timeIntervalSince(fetchedAt) < 1_800,
           TripTracker.distance(from: fetchedNear, to: position) < 10_000 {
            return
        }
        guard let fresh = await service.weather(at: position, date: .now) else { return }
        weather = fresh
        fetchedAt = .now
        fetchedNear = position
    }
}
