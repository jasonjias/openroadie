import Foundation

/// Active severe-weather alerts from the US National Weather Service —
/// api.weather.gov, keyless public data. Checked occasionally during a
/// drive; each alert is announced once. US-only by nature: elsewhere the
/// API simply has nothing, and the feature is silently absent.
final class SevereWeatherWatch: Sendable {
    /// Settings toggle; on by default, disclosed like the other feeds.
    static let enabledKey = "weatherAlertsEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    struct Alert: Equatable, Identifiable, Sendable {
        let id: String
        let event: String
        let headline: String
    }

    /// GeoJSON shape of /alerts/active — only the fields used.
    struct Response: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                var event: String?
                var headline: String?
                var severity: String?
            }
            var id: String?
            var properties: Properties
        }
        var features: [Feature]
    }

    /// Severe and Extreme only — a Small Craft Advisory is not a reason to
    /// interrupt a driver. Pure and unit-tested.
    static func parse(_ data: Data) -> [Alert] {
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return decoded.features.compactMap { feature in
            guard let severity = feature.properties.severity,
                  severity == "Severe" || severity == "Extreme",
                  let event = feature.properties.event,
                  let id = feature.id else { return nil }
            return Alert(id: id, event: event, headline: feature.properties.headline ?? event)
        }
    }

    func active(at coordinate: Coordinate) async -> [Alert] {
        guard Self.isEnabled else { return [] }
        let point = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
        guard let url = URL(string: "https://api.weather.gov/alerts/active?point=\(point)") else { return [] }
        var request = URLRequest(url: url)
        // NWS requires an identifying User-Agent and blocks anonymous ones.
        request.setValue("OpenRoadie (github.com/jasonjias/openroadie)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return Self.parse(data)
    }
}
