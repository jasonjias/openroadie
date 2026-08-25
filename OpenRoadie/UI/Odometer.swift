import SwiftUI

/// A Tesla-style half gauge: gray track, colored fill, content in the middle.
/// Real arc geometry — nothing gets clipped, round caps included.
struct SemicircleGauge<Content: View>: View {
    let fraction: Double // 0–1
    let color: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width / 2 - lineWidth / 2, geo.size.height - lineWidth)
            let center = CGPoint(x: geo.size.width / 2, y: radius + lineWidth / 2)
            let sweep = 180 * min(max(fraction, 0.02), 1)

            ZStack {
                Path { path in
                    path.addArc(center: center, radius: radius,
                                startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                }
                .stroke(.quaternary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                Path { path in
                    path.addArc(center: center, radius: radius,
                                startAngle: .degrees(180), endAngle: .degrees(180 + sweep), clockwise: false)
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                content
                    .position(x: center.x, y: center.y - radius * 0.3)
            }
        }
        .aspectRatio(1.9, contentMode: .fit)
    }
}

/// The speed readout, in the face of the user's choosing — pick several in
/// Settings and swipe between them on the dashboard, watch-face style.
enum OdometerStyle: String, CaseIterable, Identifiable, Codable {
    case classic
    case minimal
    case digital
    case gauge
    case rainbowRoad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .minimal: "Minimal"
        case .digital: "Digital"
        case .gauge: "Gauge"
        case .rainbowRoad: "Rainbow Road"
        }
    }

    static let enabledKey = "enabledOdometerStyles"

    static var enabled: [OdometerStyle] {
        let raw = UserDefaults.standard.stringArray(forKey: enabledKey) ?? []
        let styles = allCases.filter { raw.contains($0.rawValue) }
        return styles.isEmpty ? [.classic] : styles
    }

    static func isEnabled(_ style: OdometerStyle) -> Bool {
        enabled.contains(style)
    }

    static func setEnabled(_ style: OdometerStyle, _ enabled: Bool) {
        var set = Set((UserDefaults.standard.stringArray(forKey: enabledKey) ?? ["classic"]))
        if enabled { set.insert(style.rawValue) } else { set.remove(style.rawValue) }
        UserDefaults.standard.set(allCases.map(\.rawValue).filter(set.contains), forKey: enabledKey)
    }
}

/// One odometer face. Same data every time: speed, confidence, over-limit.
struct OdometerView: View {
    let style: OdometerStyle
    let speedMph: Int?
    let accuracyMph: Int?
    let isOverLimit: Bool
    /// For the Rainbow Road face: real motion drives the animation.
    var speedMps: Double?
    var tripDistanceMeters: Double = 0
    var contextTimestamp: Date?

    private var speedColor: Color { isOverLimit ? .red : .primary }

    var body: some View {
        switch style {
        case .classic: classic
        case .minimal: minimal
        case .digital: digital
        case .gauge: gauge
        case .rainbowRoad:
            RainbowRoadView(
                speedMph: speedMph,
                speedMps: speedMps,
                tripDistanceMeters: tripDistanceMeters,
                contextTimestamp: contextTimestamp,
                isOverLimit: isOverLimit
            )
        }
    }

    private var unitLine: String {
        if let accuracyMph { "mph  ± \(accuracyMph)" } else { "mph" }
    }

    private var classic: some View {
        VStack(spacing: 4) {
            Text(speedMph.map(String.init) ?? "—")
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(speedMph == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(speedColor))
            Text(unitLine)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var minimal: some View {
        VStack(spacing: 0) {
            Text(speedMph.map(String.init) ?? "—")
                .font(.system(size: 94, weight: .ultraLight))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(speedMph == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(speedColor))
            Text("mph")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var digital: some View {
        VStack(spacing: 6) {
            Text(speedMph.map { String(format: "%03d", $0) } ?? "---")
                .font(.system(size: 60, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())
                .foregroundStyle(isOverLimit ? .red : .green)
                .shadow(color: (isOverLimit ? Color.red : .green).opacity(0.6), radius: 8)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(.black, in: RoundedRectangle(cornerRadius: 14))
            Text(unitLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var gauge: some View {
        SemicircleGauge(
            fraction: Double(speedMph ?? 0) / 120,
            color: isOverLimit ? .red : .accentColor,
            lineWidth: 15
        ) {
            VStack(spacing: 0) {
                Text(speedMph.map(String.init) ?? "—")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(speedMph == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(speedColor))
                Text(unitLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 310)
    }
}

/// The optional splash of color while a drive is live.
enum DrivingBackground: String, CaseIterable, Identifiable {
    case off
    case green
    case blue
    case purple
    case orange

    static let defaultsKey = "drivingBackgroundColor"

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var color: Color? {
        switch self {
        case .off: nil
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .orange: .orange
        }
    }

    static var current: DrivingBackground {
        DrivingBackground(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .green
    }
}
