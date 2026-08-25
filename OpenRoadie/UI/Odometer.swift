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
    case racing
    case rainbowRoad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .minimal: "Minimal"
        case .digital: "Digital"
        case .gauge: "Gauge"
        case .racing: "Racing"
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
    /// For the Rainbow Road and Racing faces.
    var speedMps: Double?
    var limitMph: Int?
    var isDriving: Bool = false
    var sceneVehicle: Vehicle = .classic

    private var speedColor: Color { isOverLimit ? .red : .primary }

    var body: some View {
        switch style {
        case .classic: classic
        case .minimal: minimal
        case .digital: digital
        case .gauge: gauge
        case .racing: racing
        case .rainbowRoad:
            DriveSceneView(isDriving: isDriving, speedMps: speedMps, vehicle: sceneVehicle)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(speedMph.map(String.init) ?? "—")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(isOverLimit ? .red : .white)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                        Text("mph")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    .padding(.leading, 14)
                    .padding(.top, 6)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 12)
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

    /// LapTimer-style round dial: needle, tick ring, digital inset — and the
    /// red zone isn't decoration, it starts at the road's actual posted
    /// limit (defaults to 65 where the limit is unknown).
    private var racing: some View {
        let maxDial = 120.0
        let redline = Double(limitMph ?? 65)
        let startAngle = 135.0 // degrees; dial sweeps 270° clockwise
        let sweep = 270.0
        func angle(for mph: Double) -> Double {
            startAngle + sweep * min(max(mph / maxDial, 0), 1)
        }

        return Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 8

            func point(angleDegrees: Double, radius r: CGFloat) -> CGPoint {
                let rad = angleDegrees * .pi / 180
                return CGPoint(x: center.x + cos(rad) * r, y: center.y + sin(rad) * r)
            }

            // Face.
            context.fill(Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
            )), with: .color(Color(white: 0.08)))

            // Green-to-redline arc, then the red zone.
            var green = Path()
            green.addArc(center: center, radius: radius - 12,
                         startAngle: .degrees(angle(for: 0)), endAngle: .degrees(angle(for: redline)), clockwise: false)
            context.stroke(green, with: .color(.green.opacity(0.75)), style: StrokeStyle(lineWidth: 10, lineCap: .butt))
            var red = Path()
            red.addArc(center: center, radius: radius - 12,
                       startAngle: .degrees(angle(for: redline)), endAngle: .degrees(angle(for: maxDial)), clockwise: false)
            context.stroke(red, with: .color(.red.opacity(0.85)), style: StrokeStyle(lineWidth: 10, lineCap: .butt))

            // Ticks and numerals every 20, minor ticks every 10.
            for mph in stride(from: 0.0, through: maxDial, by: 10) {
                let major = mph.truncatingRemainder(dividingBy: 20) == 0
                let a = angle(for: mph)
                var tick = Path()
                tick.move(to: point(angleDegrees: a, radius: radius - (major ? 26 : 21)))
                tick.addLine(to: point(angleDegrees: a, radius: radius - 8))
                context.stroke(tick, with: .color(.white.opacity(major ? 0.95 : 0.5)), lineWidth: major ? 2.5 : 1.2)
                if major {
                    context.draw(
                        Text("\(Int(mph))").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white),
                        at: point(angleDegrees: a, radius: radius - 38)
                    )
                }
            }

            // Needle.
            let needleAngle = angle(for: Double(speedMph ?? 0))
            var needle = Path()
            needle.move(to: point(angleDegrees: needleAngle + 180, radius: 14))
            needle.addLine(to: point(angleDegrees: needleAngle, radius: radius - 24))
            context.stroke(needle, with: .color(.red), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 7, y: center.y - 7, width: 14, height: 14)), with: .color(.white.opacity(0.9)))

            // Digital inset, seven-segment feel.
            context.draw(
                Text(speedMph.map(String.init) ?? "--")
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(isOverLimit ? Color.red : .white),
                at: CGPoint(x: center.x, y: center.y + radius * 0.48)
            )
            context.draw(
                Text("mph").font(.system(size: 10, weight: .medium)).foregroundStyle(.gray),
                at: CGPoint(x: center.x, y: center.y + radius * 0.48 + 20)
            )
        }
        .animation(.easeOut(duration: 0.4), value: speedMph)
        .aspectRatio(1, contentMode: .fit)
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
