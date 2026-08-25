import SwiftUI

/// A Tesla-style half gauge: gray track, colored fill, content in the middle.
struct SemicircleGauge<Content: View>: View {
    let fraction: Double // 0–1
    let color: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(.quaternary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(180))
            Circle()
                .trim(from: 0, to: 0.5 * min(max(fraction, 0.02), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(180))
            content
                .offset(y: -lineWidth)
        }
        .aspectRatio(1.6, contentMode: .fit)
        .padding(.horizontal, lineWidth / 2)
        .clipped()
    }
}

/// The speed readout, in the face of the user's choosing — pick several in
/// Settings and swipe between them on the dashboard, watch-face style.
enum OdometerStyle: String, CaseIterable, Identifiable, Codable {
    case classic
    case minimal
    case digital
    case gauge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .minimal: "Minimal"
        case .digital: "Digital"
        case .gauge: "Gauge"
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

    private var speedColor: Color { isOverLimit ? .red : .primary }

    var body: some View {
        switch style {
        case .classic: classic
        case .minimal: minimal
        case .digital: digital
        case .gauge: gauge
        }
    }

    private var unitLine: String {
        if let accuracyMph { "mph  ± \(accuracyMph)" } else { "mph" }
    }

    private var classic: some View {
        VStack(spacing: 4) {
            Text(speedMph.map(String.init) ?? "—")
                .font(.system(size: 96, weight: .bold, design: .rounded))
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
                .font(.system(size: 110, weight: .ultraLight))
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
                .font(.system(size: 72, weight: .bold, design: .monospaced))
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
            lineWidth: 16
        ) {
            VStack(spacing: 0) {
                Text(speedMph.map(String.init) ?? "—")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(speedMph == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(speedColor))
                Text(unitLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: 170)
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
