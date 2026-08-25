import SwiftUI

/// The Rainbow Road odometer face — a Tesla-easter-egg-style view of your
/// car on a scrolling rainbow, except ours is honest: the stripes move at
/// your actual GPS speed (phase = real trip distance, extrapolated between
/// fixes). Parked, it stands still. No sensors are simulated — just you,
/// the road, and the speed you're really doing.
struct RainbowRoadView: View {
    let speedMph: Int?
    let speedMps: Double?
    let tripDistanceMeters: Double
    /// Timestamp of the last telemetry update, for smooth extrapolation.
    let contextTimestamp: Date?
    let isOverLimit: Bool

    private static let stripeLength: Double = 2.6      // meters per band
    private static let viewDepth: Double = 80          // meters to horizon
    private static let rainbow: [Color] = [
        Color(red: 0.94, green: 0.31, blue: 0.30),
        Color(red: 0.98, green: 0.60, blue: 0.22),
        Color(red: 0.99, green: 0.86, blue: 0.30),
        Color(red: 0.42, green: 0.80, blue: 0.40),
        Color(red: 0.31, green: 0.66, blue: 0.94),
        Color(red: 0.46, green: 0.44, blue: 0.90),
        Color(red: 0.72, green: 0.42, blue: 0.90),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let phase = Self.phase(
                    tripDistance: tripDistanceMeters,
                    speedMps: speedMps,
                    contextTimestamp: contextTimestamp,
                    now: timeline.date
                )
                Self.drawRoad(context: &context, size: size, phase: phase)
                Self.drawCar(context: &context, size: size)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                Text(speedMph.map(String.init) ?? "—")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(speedMph == nil
                        ? AnyShapeStyle(.tertiary)
                        : AnyShapeStyle(isOverLimit ? .red : .primary))
                Text("mph")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    /// World distance driven, in meters — real distance plus dead-reckoned
    /// motion since the last fix, so the road scrolls at 60fps between the
    /// ~1Hz GPS updates.
    static func phase(tripDistance: Double, speedMps: Double?, contextTimestamp: Date?, now: Date) -> Double {
        let sinceFix = contextTimestamp.map { max(0, min(2, now.timeIntervalSince($0))) } ?? 0
        return tripDistance + max(0, speedMps ?? 0) * sinceFix
    }

    /// Perspective: 0 at the viewer's bumper → 1 at the horizon. The gentle
    /// constant keeps near stripes from swallowing half the road.
    static func depthT(_ meters: Double) -> Double {
        1 - 1 / (1 + meters * 0.05)
    }

    private static func drawRoad(context: inout GraphicsContext, size: CGSize, phase: Double) {
        // A band, not a triangle: the road stays road-width at the far end.
        let horizonY = size.height * 0.38
        let bottomY = size.height + 6
        let centerX = size.width / 2
        let bottomHalfWidth = size.width * 0.30
        let horizonHalfWidth = size.width * 0.045

        func edge(atT t: Double) -> (y: CGFloat, halfWidth: CGFloat) {
            (
                y: bottomY - (bottomY - horizonY) * t,
                halfWidth: bottomHalfWidth + (horizonHalfWidth - bottomHalfWidth) * t
            )
        }

        // Ground haze under the horizon so the road has something to sit on.
        var ground = Path()
        ground.addRect(CGRect(x: 0, y: horizonY, width: size.width, height: size.height - horizonY))
        context.fill(ground, with: .linearGradient(
            Gradient(colors: [Color.gray.opacity(0.10), Color.gray.opacity(0.02)]),
            startPoint: CGPoint(x: 0, y: horizonY),
            endPoint: CGPoint(x: 0, y: size.height)
        ))

        // Rainbow bands, nearest drawn last. Band index is anchored to the
        // world (phase / length), so colors travel with the road.
        let firstBand = Int(floor(phase / stripeLength))
        var s = -phase.truncatingRemainder(dividingBy: stripeLength)
        var index = firstBand
        while s < viewDepth {
            let near = max(0, s)
            let far = min(viewDepth, s + stripeLength)
            if far > near {
                let a = edge(atT: depthT(near) / depthT(viewDepth))
                let b = edge(atT: depthT(far) / depthT(viewDepth))
                var band = Path()
                band.move(to: CGPoint(x: centerX - a.halfWidth, y: a.y))
                band.addLine(to: CGPoint(x: centerX + a.halfWidth, y: a.y))
                band.addLine(to: CGPoint(x: centerX + b.halfWidth, y: b.y))
                band.addLine(to: CGPoint(x: centerX - b.halfWidth, y: b.y))
                band.closeSubpath()
                let color = rainbow[((index % rainbow.count) + rainbow.count) % rainbow.count]
                let fade = 1 - depthT(near) / depthT(viewDepth) * 0.35
                context.fill(band, with: .color(color.opacity(fade)))
            }
            s += stripeLength
            index += 1
        }

        // Road edges.
        for side in [-1.0, 1.0] {
            var line = Path()
            let a = edge(atT: 0)
            let b = edge(atT: 1)
            line.move(to: CGPoint(x: centerX + a.halfWidth * side, y: a.y))
            line.addLine(to: CGPoint(x: centerX + b.halfWidth * side, y: b.y))
            context.stroke(line, with: .color(.white.opacity(0.85)), lineWidth: 2.5)
        }
    }

    /// Our car, seen from behind — simple, friendly shapes in the brand red.
    private static func drawCar(context: inout GraphicsContext, size: CGSize) {
        let w: CGFloat = 92
        let centerX = size.width / 2
        let bottom = size.height * 0.94

        // Soft shadow grounding the car on the road.
        let shadow = Path(ellipseIn: CGRect(x: centerX - w * 0.56, y: bottom - 8, width: w * 1.12, height: 16))
        context.fill(shadow, with: .color(.black.opacity(0.25)))

        // Wheels peeking out.
        for side in [-1.0, 1.0] {
            let wheel = Path(roundedRect: CGRect(
                x: centerX + side * w * 0.46 - 7, y: bottom - 20, width: 14, height: 18
            ), cornerRadius: 5)
            context.fill(wheel, with: .color(Color(white: 0.15)))
        }

        let red = Color(red: 0.89, green: 0.18, blue: 0.16)
        let darkRed = Color(red: 0.72, green: 0.10, blue: 0.10)

        // Cabin with the rear window.
        let cabin = Path(roundedRect: CGRect(x: centerX - w * 0.34, y: bottom - 62, width: w * 0.68, height: 34), cornerRadius: 12)
        context.fill(cabin, with: .linearGradient(
            Gradient(colors: [red, darkRed]),
            startPoint: CGPoint(x: 0, y: bottom - 62),
            endPoint: CGPoint(x: 0, y: bottom - 28)
        ))
        let window = Path(roundedRect: CGRect(x: centerX - w * 0.26, y: bottom - 57, width: w * 0.52, height: 18), cornerRadius: 7)
        context.fill(window, with: .linearGradient(
            Gradient(colors: [Color(red: 0.62, green: 0.82, blue: 0.90), Color(red: 0.35, green: 0.55, blue: 0.70)]),
            startPoint: CGPoint(x: 0, y: bottom - 57),
            endPoint: CGPoint(x: 0, y: bottom - 39)
        ))

        // Body.
        let body = Path(roundedRect: CGRect(x: centerX - w / 2, y: bottom - 36, width: w, height: 30), cornerRadius: 11)
        context.fill(body, with: .linearGradient(
            Gradient(colors: [red, darkRed]),
            startPoint: CGPoint(x: 0, y: bottom - 36),
            endPoint: CGPoint(x: 0, y: bottom - 6)
        ))

        // Taillights, glowing.
        for side in [-1.0, 1.0] {
            let light = Path(roundedRect: CGRect(
                x: centerX + side * w * 0.40 - 9, y: bottom - 31, width: 18, height: 7
            ), cornerRadius: 3.5)
            var glow = context
            glow.addFilter(.shadow(color: .red.opacity(0.9), radius: 5))
            glow.fill(light, with: .color(Color(red: 1.0, green: 0.25, blue: 0.2)))
        }

        // License plate wink.
        let plate = Path(roundedRect: CGRect(x: centerX - 15, y: bottom - 20, width: 30, height: 10), cornerRadius: 2)
        context.fill(plate, with: .color(.white.opacity(0.9)))
    }
}
