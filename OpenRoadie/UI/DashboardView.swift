import SwiftUI

/// Developer/prototype dashboard: everything OpenRoadie currently knows about
/// the drive, biased toward observability over polish.
struct DashboardView: View {
    let session: DriveSessionManager
    var wake: WakeWordCoordinator? = nil

    @Environment(\.openURL) private var openURL
    @State private var showsSettings = false
    @AppStorage(DrivingBackground.defaultsKey) private var drivingBackground = DrivingBackground.green.rawValue
    @AppStorage(Vehicle.defaultsKey) private var sceneVehicle = Vehicle.classic.rawValue

    var body: some View {
        ZStack {
            // A splash of color while the drive is live (user-selectable).
            if session.isDriving, let color = DrivingBackground.current.color {
                LinearGradient(
                    colors: [color.opacity(0.55), color.opacity(0.22), color.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
            dashboard
        }
        .animation(.easeInOut(duration: 0.6), value: session.isDriving)
    }

    private var dashboard: some View {
        VStack(spacing: 24) {
            // The wordmark, centered — this screen IS the app.
            ZStack {
                Text("OpenRoadie")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                Button {
                    showsSettings = true
                } label: {
                    ProfileAvatar(size: 60)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.top, 4)

            Spacer()

            speedSection
            if showHeading {
                headingSection
            }
            roadSection
            positionSection

            Spacer()

            tripSection
            if wake?.status == .listening {
                Label("Say \u{201C}Hey Roadie\u{201D}", systemImage: "waveform")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }
            statusBanner
            driveButton
        }
        .padding()
        .fullScreenCover(isPresented: $showsSettings) {
            SettingsView()
        }
        .onChange(of: session.isDriving) { _, driving in
            // Keep the screen awake while a drive is active — this is a
            // glanceable dashboard.
            UIApplication.shared.isIdleTimerDisabled = driving
        }
    }

    /// Swipe between the odometer faces chosen in Settings — watch-face style.
    private var speedSection: some View {
        let styles = OdometerStyle.enabled
        let speedMph = session.context.speed.map { DriveFormatting.milesPerHour(fromMetersPerSecond: $0) }
        let accuracyMph = session.context.speedAccuracy.map { max(1, DriveFormatting.milesPerHour(fromMetersPerSecond: $0)) }

        return TabView {
            ForEach(styles) { style in
                OdometerView(
                    style: style,
                    speedMph: speedMph,
                    accuracyMph: accuracyMph,
                    isOverLimit: isOverLimit,
                    speedMps: session.context.speed,
                    limitMph: session.context.road?.speedLimit.map { DriveFormatting.milesPerHour(fromMetersPerSecond: $0) },
                    isDriving: session.isDriving,
                    sceneVehicle: Vehicle(rawValue: sceneVehicle) ?? .classic
                )
                .tag(style.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: styles.count > 1 ? .automatic : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .frame(height: 205)
    }

    /// Over the posted limit with a little grace (~2 mph) so GPS noise at
    /// exactly the limit doesn't flicker the display.
    private var isOverLimit: Bool {
        guard let speed = session.context.speed,
              let limit = session.context.road?.speedLimit else { return false }
        return speed > limit + 0.9
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

    @AppStorage("showGPSDetails") private var showGPSDetails = false
    @AppStorage("showHeading") private var showHeading = false

    private var positionSection: some View {
        VStack(spacing: 2) {
            if let coordinate = session.context.coordinate {
                // Coordinates, GPS accuracy, and altitude are developer
                // telemetry, not driver info — hidden unless the flag is on.
                if showGPSDetails {
                    Text(DriveFormatting.coordinate(coordinate))
                        .font(.body.monospaced())
                    HStack(spacing: 10) {
                        if let accuracy = session.context.horizontalAccuracy {
                            Text("GPS ± \(Int(accuracy.rounded())) m")
                        }
                        if let altitude = session.context.altitude {
                            Text("alt \(DriveFormatting.feet(fromMeters: altitude)) ft")
                        }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                }
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
