import SwiftUI

/// The drive's weather as a widget-style card — big degrees, condition,
/// and the ambient backdrop animating quietly inside it. Modeled on the
/// iOS Weather widget's shape.
struct WeatherCard: View {
    let weather: TripWeather
    var usAqi: Int?
    /// Where — the drive's destination, when known.
    var placeName: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
            WeatherBackdrop(wmoCode: weather.wmoCode, isDay: weather.isDay)
            VStack(alignment: .leading, spacing: 2) {
                if let placeName {
                    Text(placeName.components(separatedBy: " · ").first ?? placeName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text("\(DriveFormatting.fahrenheit(fromCelsius: weather.temperatureC))°")
                    .font(.system(size: 54, weight: .medium, design: .rounded))
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: weather.isDay
                          ? WeatherCode.symbol(weather.wmoCode)
                          : WeatherCode.nightSymbol(weather.wmoCode))
                    Text(WeatherCode.label(weather.wmoCode))
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                Text(details)
                    .font(.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var details: String {
        var parts = ["Wind \(Int((weather.windKph * 0.621371).rounded())) mph"]
        if let usAqi {
            parts.append("Air \(usAqi) \(AirQuality.label(usAqi))")
        }
        if weather.precipitationMm > 0 {
            parts.append(String(format: "%.1f mm", weather.precipitationMm))
        }
        return parts.joined(separator: " · ")
    }

    /// Sky-toned backgrounds, day vs night, roughly the Weather widget's.
    private var gradient: [Color] {
        switch WeatherBackdrop.Kind.from(wmoCode: weather.wmoCode) {
        case .clear, .partlyCloudy:
            weather.isDay
                ? [Color(red: 0.25, green: 0.52, blue: 0.89), Color(red: 0.45, green: 0.68, blue: 0.95)]
                : [Color(red: 0.10, green: 0.13, blue: 0.32), Color(red: 0.16, green: 0.20, blue: 0.42)]
        case .overcast, .fog:
            [Color(red: 0.42, green: 0.48, blue: 0.58), Color(red: 0.55, green: 0.60, blue: 0.68)]
        case .rain, .storm:
            [Color(red: 0.25, green: 0.31, blue: 0.42), Color(red: 0.36, green: 0.43, blue: 0.55)]
        case .snow:
            [Color(red: 0.51, green: 0.58, blue: 0.70), Color(red: 0.66, green: 0.72, blue: 0.82)]
        }
    }
}
