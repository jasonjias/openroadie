import SwiftUI

/// Developer/prototype dashboard: everything OpenRoadie currently knows about
/// the drive, biased toward observability over polish.
struct DashboardView: View {
    let session: DriveSessionManager

    @Environment(\.openURL) private var openURL
    @State private var showsSettings = false

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Text("OPENROADIE")
                    .font(.caption.weight(.bold))
                    .tracking(4)
                    .foregroundStyle(.secondary)
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.top, 8)

            Spacer()

            speedSection
            headingSection
            roadSection
            positionSection

            Spacer()

            tripSection
            statusBanner
            driveButton
        }
        .padding()
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .onChange(of: session.isDriving) { _, driving in
            // Keep the screen awake while a drive is active — this is a
            // glanceable dashboard.
            UIApplication.shared.isIdleTimerDisabled = driving
        }
    }

    private var speedSection: some View {
        VStack(spacing: 4) {
            if let speed = session.context.speed {
                Text("\(DriveFormatting.milesPerHour(fromMetersPerSecond: speed))")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isOverLimit ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            } else {
                Text("—")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Text(speedUnitLine)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    /// Over the posted limit with a little grace (~2 mph) so GPS noise at
    /// exactly the limit doesn't flicker the display.
    private var isOverLimit: Bool {
        guard let speed = session.context.speed,
              let limit = session.context.road?.speedLimit else { return false }
        return speed > limit + 0.9
    }

    private var speedUnitLine: String {
        if let accuracy = session.context.speedAccuracy {
            let mph = max(1, DriveFormatting.milesPerHour(fromMetersPerSecond: accuracy))
            return "mph  ± \(mph)"
        }
        return "mph"
    }

    private var headingSection: some View {
        HStack(spacing: 10) {
            if session.isDriving || session.context.course != nil {
                CompassNeedle(course: session.context.course)
            }
            if let course = session.context.course {
                Text("\(DriveFormatting.cardinal(fromCourse: course)) · \(Int(course.rounded()))°")
            } else {
                Text("heading —")
            }
        }
        .font(.title3.weight(.medium))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var roadSection: some View {
        if let road = session.context.road {
            HStack(spacing: 12) {
                Text(road.displayName ?? "Unnamed road")
                    .font(.headline)
                if let limit = road.speedLimit {
                    SpeedLimitSign(mph: DriveFormatting.milesPerHour(fromMetersPerSecond: limit))
                }
            }
        } else if session.isDriving && session.context.coordinate != nil && RoadService.isEnabled {
            Text("looking up road…")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }

    private var positionSection: some View {
        VStack(spacing: 2) {
            if let coordinate = session.context.coordinate {
                Text(DriveFormatting.coordinate(coordinate))
                    .font(.body.monospaced())
                HStack(spacing: 10) {
                    if let accuracy = session.context.horizontalAccuracy {
                        Text("± \(Int(accuracy.rounded())) m")
                    }
                    if let altitude = session.context.altitude {
                        Text("alt \(DriveFormatting.feet(fromMeters: altitude)) ft")
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            } else if session.isDriving {
                Text("waiting for GPS…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tripSection: some View {
        Group {
            if session.context.tripStart != nil {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    HStack(spacing: 12) {
                        Label(
                            DriveFormatting.duration(session.context.tripDuration(at: timeline.date) ?? 0),
                            systemImage: "clock"
                        )
                        Label(
                            DriveFormatting.miles(fromMeters: session.context.tripDistance),
                            systemImage: "road.lanes"
                        )
                        if session.isDriving {
                            Label(
                                session.isStationary ? "Stationary" : "Moving",
                                systemImage: session.isStationary ? "parkingsign" : "car.fill"
                            )
                        }
                    }
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if session.authorization == .denied {
            VStack(spacing: 8) {
                Text("Location access is off. OpenRoadie needs it to see the drive.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .font(.footnote.weight(.semibold))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        } else if let error = session.lastErrorDescription {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private var driveButton: some View {
        Button {
            if session.isDriving {
                session.stopDrive()
            } else {
                session.startDrive()
            }
        } label: {
            Text(session.isDriving ? "Stop Drive" : "Start Drive")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(session.isDriving ? .red : .green)
    }
}

/// A needle that points in the direction of travel (screen-up = north).
///
/// It stays mounted for the whole drive — dimmed and holding its last
/// direction while GPS course is unknown (e.g. stopped at a light) — and
/// rotates via the shortest arc so 350°→10° sweeps 20°, not 340°.
private struct CompassNeedle: View {
    let course: Double?

    /// Accumulated rotation; may exceed 0–360 so turns animate continuously.
    @State private var needleAngle: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: 1.5)
            Image(systemName: "location.north.fill")
                .font(.system(size: 13))
                .rotationEffect(.degrees(needleAngle))
                .opacity(course == nil ? 0.35 : 1)
        }
        .frame(width: 28, height: 28)
        .onAppear {
            needleAngle = course ?? 0
        }
        .onChange(of: course) { _, newCourse in
            guard let newCourse else { return }
            let current = needleAngle.truncatingRemainder(dividingBy: 360)
            var delta = (newCourse - current).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            withAnimation(.smooth(duration: 0.6)) {
                needleAngle += delta
            }
        }
    }
}

/// A miniature US-style speed limit sign.
private struct SpeedLimitSign: View {
    let mph: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("LIMIT")
                .font(.system(size: 8, weight: .semibold))
            Text("\(mph)")
                .font(.system(size: 17, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.black, lineWidth: 1.5))
    }
}

#Preview {
    DashboardView(session: DriveSessionManager())
}
