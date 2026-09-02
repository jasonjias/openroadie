import Foundation

/// Fills in weather for trips recorded before the feature existed (or while
/// offline), a few per launch, gently — Open-Meteo is a free public service.
@MainActor
enum WeatherBackfill {
    static func run(store: TripStore, service: WeatherService = WeatherService()) async {
        guard WeatherService.isEnabled else { return }
        for trip in store.tripsNeedingWeather(limit: 25) {
            guard let anchor = trip.weatherAnchor else { continue }
            guard let weather = await service.weather(at: anchor.coordinate, date: anchor.date) else {
                // Offline or rate-limited: stop for this launch rather than
                // hammering a free API with the same failure 25 times.
                return
            }
            store.setWeather(weather, on: trip)
            try? await Task.sleep(for: .milliseconds(400))
        }
    }
}
