import SwiftUI

/// Ambient full-screen weather, Apple-Weather style but deliberately
/// subtle — the dashboard is a driving instrument first. Sun glows,
/// clouds drift, rain falls, snow sways; everything low-opacity behind
/// the real content, drawn deterministically so it costs a Canvas pass
/// and nothing else. Honors Reduce Motion by freezing in place.
struct WeatherBackdrop: View {
    let wmoCode: Int
    var isDay: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// The animation vocabulary — coarser than WMO codes on purpose.
    /// Pure and unit-tested.
    enum Kind: Equatable {
        case clear
        case partlyCloudy
        case overcast
        case fog
        case rain(heavy: Bool)
        case snow
        case storm

        static func from(wmoCode: Int) -> Kind {
            switch wmoCode {
            case 0, 1: .clear
            case 2: .partlyCloudy
            case 3: .overcast
            case 45, 48: .fog
            case 51, 53, 55, 56, 57: .rain(heavy: false)
            case 61, 63, 66, 80, 81: .rain(heavy: false)
            case 65, 82: .rain(heavy: true)
            case 71, 73, 75, 77, 85, 86: .snow
            case 95, 96, 99: .storm
            default: .clear
            }
        }
    }

    var body: some View {
        let kind = Kind.from(wmoCode: wmoCode)
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                if kind == .clear || kind == .partlyCloudy {
                    isDay ? AnyView(sunGlow(t: t)) : AnyView(moonGlow(t: t))
                }
                if kind != .clear {
                    clouds(t: t, kind: kind)
                }
                if case .rain(let heavy) = kind {
                    precipitation(t: t, drops: heavy ? 110 : 55, speed: heavy ? 1_400 : 1_000, snow: false)
                }
                if kind == .storm {
                    precipitation(t: t, drops: 130, speed: 1_500, snow: false)
                    Color.indigo.opacity(0.06).ignoresSafeArea()
                }
                if kind == .snow {
                    precipitation(t: t, drops: 70, speed: 160, snow: true)
                }
                if kind == .fog {
                    LinearGradient(
                        colors: [.gray.opacity(0.16), .clear],
                        startPoint: .bottom, endPoint: .top
                    )
                    .ignoresSafeArea()
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// A soft breathing glow where the sun would be.
    private func sunGlow(t: TimeInterval) -> some View {
        let pulse = 0.5 + 0.5 * sin(t / 4)
        return RadialGradient(
            colors: [.yellow.opacity(0.16 + 0.05 * pulse), .clear],
            center: .init(x: 0.16, y: 0.06),
            startRadius: 0,
            endRadius: 260 + 30 * pulse
        )
        .ignoresSafeArea()
    }

    /// A clear NIGHT is not a sunny one: a small, cool, steady glow.
    private func moonGlow(t: TimeInterval) -> some View {
        let pulse = 0.5 + 0.5 * sin(t / 6)
        return RadialGradient(
            colors: [.indigo.opacity(0.10 + 0.03 * pulse), .clear],
            center: .init(x: 0.84, y: 0.05),
            startRadius: 0,
            endRadius: 170 + 15 * pulse
        )
        .ignoresSafeArea()
    }

    /// Two to four blurred blobs drifting slowly, wrapping at the edges.
    private func clouds(t: TimeInterval, kind: Kind) -> some View {
        let count = kind == .partlyCloudy ? 2 : 4
        let opacity = colorScheme == .dark ? 0.10 : 0.16
        return GeometryReader { geometry in
            ForEach(0..<count, id: \.self) { index in
                let seed = Double(index)
                let width = 190.0 + 60 * sin(seed * 5)
                let span = geometry.size.width + width * 2
                let x = (t * (9 + seed * 3) + seed * 431).truncatingRemainder(dividingBy: span) - width
                Ellipse()
                    .fill(.gray.opacity(opacity))
                    .frame(width: width, height: width * 0.36)
                    .blur(radius: 26)
                    .position(x: x, y: 60 + seed * 46)
            }
        }
        .ignoresSafeArea()
    }

    /// Falling particles: streaks for rain, swaying dots for snow.
    /// Deterministic per-index pseudo-randomness — no state to churn.
    private func precipitation(t: TimeInterval, drops: Int, speed: Double, snow: Bool) -> some View {
        Canvas { context, size in
            let height = size.height + 40
            for index in 0..<drops {
                let seed = Double(index)
                let x0 = (seed * 127.23).truncatingRemainder(dividingBy: size.width)
                let phase = (seed * 311.7).truncatingRemainder(dividingBy: height)
                let y = (t * speed * (0.75 + 0.5 * (seed / Double(drops))) + phase)
                    .truncatingRemainder(dividingBy: height) - 20
                if snow {
                    let sway = 10 * sin(t / 1.5 + seed)
                    let rect = CGRect(x: x0 + sway, y: y, width: 4, height: 4)
                    // White flakes vanish on a light background; gray ones
                    // on a dark one. Adapt.
                    let flake: Color = colorScheme == .dark
                        ? .white.opacity(0.55)
                        : .gray.opacity(0.5)
                    context.fill(Path(ellipseIn: rect), with: .color(flake))
                } else {
                    var path = Path()
                    path.move(to: CGPoint(x: x0, y: y))
                    path.addLine(to: CGPoint(x: x0 - 2, y: y + 13))
                    context.stroke(path, with: .color(.blue.opacity(0.28)), lineWidth: 1.3)
                }
            }
        }
        .ignoresSafeArea()
    }
}
