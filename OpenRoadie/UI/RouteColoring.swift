import MapKit
import SwiftUI

/// How a route gets colored: absolute speed, or actual-vs-expected against
/// the posted limit — the goal being "expected".
enum RouteColorMode: String, CaseIterable, Identifiable {
    case speed
    case vsLimit
    case pace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: "Speed"
        case .vsLimit: "Speeding"
        case .pace: "Pace"
        }
    }
}

/// Turns a recorded route into contiguous same-color runs, so trip maps draw
/// an Activity-style colored path with a handful of polylines.
enum RouteColoring {
    /// Speed bands (m/s) and their colors, slow → fast. Boundaries at
    /// 15 / 30 / 45 / 60 / 75 / 100 mph; escalation follows weather-radar
    /// convention, with purple reserved for the genuinely dangerous 100+.
    static let bands: [(upperBound: Double, color: Color, label: String)] = [
        (6.7, .teal, "<15"),
        (13.4, .green, "15–30"),
        (20.1, .yellow, "30–45"),
        (26.8, .orange, "45–60"),
        (33.5, .red, "60–75"),
        (44.7, Color(red: 0.6, green: 0.05, blue: 0.1), "75–100"),
        (.infinity, .purple, "100+"),
    ]

    /// Relative-to-limit bands. Index 0 is "no limit data" — old points and
    /// unmapped roads stay honestly gray instead of pretending compliance.
    static let relativeBands: [(color: Color, label: String)] = [
        (.gray, "no limit data"),
        (.teal, "10+ under"),
        (.green, "at limit"),
        (.yellow, "+1–5"),
        (.orange, "+5–10"),
        (.red, "+10 over"),
    ]

    /// Pace bands — where the time went, not how fast the needle read.
    /// Deliberately neutral colors: crawling through a jam is traffic, not
    /// a mistake, and shouldn't borrow the speeding palette's red.
    static let paceBands: [(color: Color, label: String)] = [
        (.gray, "stopped"),
        (.orange, "crawling"),
        (.teal, "city"),
        (.blue, "highway"),
        (.gray.opacity(0.4), "unrecorded"),
    ]

    static func bandIndex(forSpeed speed: Double?) -> Int? {
        guard let speed else { return nil }
        return bands.firstIndex { speed < $0.upperBound }
    }

    /// Which relative band a moment belongs to; 0 when either side is unknown.
    static func relativeBandIndex(speedMps: Double?, limitMps: Double?) -> Int {
        guard let speed = speedMps, let limit = limitMps else { return 0 }
        let deltaMph = (speed - limit) * 2.236936
        switch deltaMph {
        case ..<(-10): return 1
        case ..<1: return 2
        case ..<5.5: return 3
        case ..<10.5: return 4
        default: return 5
        }
    }

    struct Run: Equatable {
        var bandIndex: Int
        /// Indices into the source route; each run overlaps its neighbor by
        /// one point so the drawn path is continuous.
        var pointIndices: ClosedRange<Int>
    }

    /// Groups consecutive route points into same-band runs. A point with
    /// unknown speed inherits the current band so the path never breaks.
    static func runs(forSpeeds speeds: [Double?]) -> [Run] {
        var current = bandIndex(forSpeed: speeds.first ?? nil) ?? 1
        let indices = speeds.map { speed -> Int in
            if let band = bandIndex(forSpeed: speed) { current = band }
            return current
        }
        return merge(indices)
    }

    /// Actual-vs-expected runs; unknown limits land in the gray band.
    static func relativeRuns(speeds: [Double?], limits: [Double?]) -> [Run] {
        merge(zip(speeds, limits).map { relativeBandIndex(speedMps: $0, limitMps: $1) })
    }

    /// Merges consecutive equal indices into overlapping runs.
    static func merge(_ indices: [Int]) -> [Run] {
        guard indices.count >= 2 else { return [] }
        var runs: [Run] = []
        var current = indices[0]
        var start = 0
        for index in 1..<indices.count where indices[index] != current {
            runs.append(Run(bandIndex: current, pointIndices: start...index))
            current = indices[index]
            start = index
        }
        if start < indices.count - 1 {
            runs.append(Run(bandIndex: current, pointIndices: start...(indices.count - 1)))
        }
        return runs
    }

    /// The bands a trip actually visited, in order — so the legend
    /// only shows colors that appear on the map.
    static func presentBands(in runs: [Run]) -> [Int] {
        Set(runs.map(\.bandIndex)).sorted()
    }

    static func color(forBand index: Int, mode: RouteColorMode) -> Color {
        switch mode {
        case .speed: bands[index].color
        case .vsLimit: relativeBands[index].color
        case .pace: paceBands[index].color
        }
    }

    static func label(forBand index: Int, mode: RouteColorMode) -> String {
        switch mode {
        case .speed: bands[index].label
        case .vsLimit: relativeBands[index].label
        case .pace: paceBands[index].label
        }
    }

    static func runs(for route: [TripPoint], mode: RouteColorMode) -> [Run] {
        switch mode {
        case .speed: runs(forSpeeds: route.map(\.speed))
        case .vsLimit: relativeRuns(speeds: route.map(\.speed), limits: route.map(\.speedLimit))
        case .pace: merge(PaceBands.bandIndices(route.map(RouteSample.init)))
        }
    }
}

/// One trip's route as colored polylines — shared by the trip detail map
/// and the per-day overlay map.
struct ColoredRoute: MapContent {
    let route: [TripPoint]
    let mode: RouteColorMode

    var body: some MapContent {
        let coordinates = route.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let runs = RouteColoring.runs(for: route, mode: mode)
        ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
            MapPolyline(coordinates: Array(coordinates[run.pointIndices]))
                .stroke(
                    RouteColoring.color(forBand: run.bandIndex, mode: mode),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
        }
    }
}

/// The legend for whatever bands the shown routes actually visited.
struct RouteLegend: View {
    let runs: [RouteColoring.Run]
    let mode: RouteColorMode

    var body: some View {
        HStack(spacing: 10) {
            ForEach(RouteColoring.presentBands(in: runs), id: \.self) { index in
                HStack(spacing: 3) {
                    Capsule()
                        .fill(RouteColoring.color(forBand: index, mode: mode))
                        .frame(width: 14, height: 4)
                    Text(RouteColoring.label(forBand: index, mode: mode))
                }
            }
            if mode == .speed {
                Text("mph")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
