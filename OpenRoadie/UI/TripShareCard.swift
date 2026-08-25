import SwiftUI

/// The shareable trip summary: the route drawn as a speed-colored line on a
/// dark card with the drive's stats — no map tiles, no street names, no
/// coordinates. The shape of the drive is the driver's to share; nothing
/// else leaves the device.
struct TripShareCard: View {
    let trip: Trip

    /// 4:5 portrait — the friendliest aspect ratio for sharing.
    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        let route = trip.route

        VStack(spacing: 0) {
            HStack {
                Text("🚗")
                Text("OpenRoadie")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                Spacer()
                Text(trip.startDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.caption)
                    .opacity(0.7)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            RoutePathCanvas(route: route)
                .padding(24)

            Grid(horizontalSpacing: 8, verticalSpacing: 14) {
                GridRow {
                    stat(DriveFormatting.miles(fromMeters: trip.distance), "distance")
                    stat(trip.duration.map(DriveFormatting.duration) ?? "—", "duration")
                }
                GridRow {
                    stat(trip.averageSpeed.map { "\(DriveFormatting.milesPerHour(fromMetersPerSecond: $0)) mph" } ?? "—", "avg speed")
                    stat(trip.maxSpeed.map { "\(DriveFormatting.milesPerHour(fromMetersPerSecond: $0)) mph" } ?? "—", "max speed")
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 12)

            Text("openroadie — the open-source driving copilot")
                .font(.caption2)
                .opacity(0.55)
                .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.20, blue: 0.32), Color(red: 0.09, green: 0.12, blue: 0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The route as a speed-colored polyline, aspect-fit with simple
/// equirectangular projection (longitude scaled by cos(latitude) so shapes
/// aren't stretched).
struct RoutePathCanvas: View {
    let route: [TripPoint]

    var body: some View {
        Canvas { context, size in
            let points = Self.project(route, into: size)
            guard points.count >= 2 else { return }

            for run in RouteColoring.runs(for: route, mode: .speed) {
                var path = Path()
                let slice = run.pointIndices.clamped(to: 0...(points.count - 1))
                path.move(to: points[slice.lowerBound])
                for index in slice.dropFirst() {
                    path.addLine(to: points[index])
                }
                context.stroke(
                    path,
                    with: .color(RouteColoring.color(forBand: run.bandIndex, mode: .speed)),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
            }

            if let start = points.first {
                context.fill(Path(ellipseIn: CGRect(x: start.x - 6, y: start.y - 6, width: 12, height: 12)), with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8)), with: .color(.green))
            }
            if let end = points.last {
                context.fill(Path(ellipseIn: CGRect(x: end.x - 6, y: end.y - 6, width: 12, height: 12)), with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(.red))
            }
        }
    }

    /// Aspect-fit projection of the route into a drawing area, testable on
    /// plain values.
    static func project(_ route: [TripPoint], into size: CGSize) -> [CGPoint] {
        guard !route.isEmpty else { return [] }
        let midLatitude = route.map(\.latitude).reduce(0, +) / Double(route.count)
        let scaleX = cos(midLatitude * .pi / 180)

        let xs = route.map { $0.longitude * scaleX }
        let ys = route.map(\.latitude)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return [] }

        let spanX = max(maxX - minX, 1e-9)
        let spanY = max(maxY - minY, 1e-9)
        let scale = min(size.width / spanX, size.height / spanY)
        let offsetX = (size.width - spanX * scale) / 2
        let offsetY = (size.height - spanY * scale) / 2

        return zip(xs, ys).map { x, y in
            CGPoint(
                x: offsetX + (x - minX) * scale,
                // Latitude grows north; screen y grows down.
                y: offsetY + (maxY - y) * scale
            )
        }
    }
}

/// Renders the card to a PNG the share sheet can hand anywhere.
@MainActor
enum TripShareRenderer {
    static func pngURL(for trip: Trip) -> URL? {
        let renderer = ImageRenderer(content: TripShareCard(trip: trip))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenRoadie Trip \(trip.startDate.formatted(.dateTime.month(.defaultDigits).day().hour().minute())).png")
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}

#Preview {
    let trip = Trip(startDate: .now)
    return TripShareCard(trip: trip)
}
