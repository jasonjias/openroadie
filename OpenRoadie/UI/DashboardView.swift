import SwiftUI

/// Developer/prototype dashboard: everything OpenRoadie currently knows about
/// the drive, biased toward observability over polish.
struct DashboardView: View {
    let session: DriveSessionManager
    var wake: WakeWordCoordinator? = nil

    @Environment(\.openURL) private var openURL
    @State private var showsSettings = false
    @AppStorage(DrivingBackground.defaultsKey) private var drivingBackground = DrivingBackground.green.rawValue
    // Read as @AppStorage rather than through AutoDriveMonitor so flipping
    // either setting redraws the drive control immediately.
    @AppStorage(AutoDriveMonitor.handsFreeKey) private var handsFree = false
    @AppStorage(AutoDriveMonitor.modeKey) private var autoStartMode = AutoDriveMonitor.Mode.off.rawValue
    @AppStorage(Vehicle.defaultsKey) private var sceneVehicle = Vehicle.classic.id
    @State private var selectedFace = ""

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

            // With the 3D scene in the rotation the odometer zone is
            // flexible and swallows all spare height itself; otherwise a
            // spacer holds the flat faces in the middle.
            if !OdometerStyle.enabled.contains(.rainbowRoad) {
                Spacer()
            }

            // NOTHING in this stack may depend on the selected face —
            // swiping faces must never move the wordmark, page dots, or
            // drive button. When the 3D scene face is enabled the road
            // info lives INSIDE the fixed odometer zone (see speedSection);
            // otherwise it gets its own fixed-height slot here.
            if !OdometerStyle.enabled.contains(.rainbowRoad) {
                roadSection
            }
            speedSection
            if showHeading {
                headingSection
            }
            positionSection

            // Capped: keeps the trip bar close under the odometer instead
            // of pinning the Start Drive button against the tab bar.
            Spacer().frame(maxHeight: 28)

            tripSection
            statusBanner
            driveButton

            Spacer().frame(maxHeight: 18)
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

        return TabView(selection: $selectedFace) {
            ForEach(styles) { style in
                OdometerView(
                    style: style,
                    speedMph: speedMph,
                    isOverLimit: isOverLimit,
                    speedMps: session.context.speed,
                    limitMph: session.context.road?.speedLimit.map { DriveFormatting.milesPerHour(fromMetersPerSecond: $0) },
                    isDriving: session.isDriving,
                    sceneVehicle: Vehicle.find(sceneVehicle),
                    roadName: session.context.road?.displayName,
                    yawProvider: { [weak session] in session?.latestYawRate ?? 0 },
                    roadCurve: session.context.roadCurve
                )
                .tag(style.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: styles.count > 1 ? .automatic : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        // Constant height per enabled set — with the 3D scene in the
        // rotation the zone stretches to swallow ALL spare height (the
        // bottom cluster is pinned by its capped spacers, so this only
        // grows upward); flat-only setups keep the standard 205. Either
        // way the zone is identical for every face, so the page dots
        // and everything below never move between swipes.
        .frame(height: styles.contains(.rainbowRoad) ? nil : 205)
        .frame(maxHeight: styles.contains(.rainbowRoad) ? .infinity : 205)
        // Full-bleed: cancel the dashboard's side padding so the 3D scene
        // reaches the screen edges — roadside trees and lamps shouldn't
        // vanish at an invisible wall 16pt early.
        .padding(.horizontal, -16)
        // With the tall 3D zone, flat faces have slack at the top — the
        // road info overlays there (matching the scene face's own HUD
        // position) instead of occupying outside layout, so swiping
        // faces never reflows the screen. Hidden on the scene face,
        // which draws its own.
        .overlay(alignment: .top) {
            if styles.contains(.rainbowRoad) {
                roadSection
                    .opacity(selectedFace == OdometerStyle.rainbowRoad.rawValue ? 0 : 1)
            }
        }
        .onAppear {
            if selectedFace.isEmpty { selectedFace = styles.first?.rawValue ?? "" }
        }
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

    /// A fixed-height slot: empty until the road is known (no "looking
    /// up…" chatter), and appearing content never reflows the layout —
    /// the odometer and Start Drive button stay exactly where they are.
    private var roadSection: some View {
        HStack(spacing: 12) {
            if let road = session.context.road {
                Text(road.displayName ?? "Unnamed road")
                    .font(.headline)
                if let limit = road.speedLimit {
                    SpeedLimitSign(limitMph: DriveFormatting.milesPerHour(fromMetersPerSecond: limit))
                }
            }
        }
        .frame(height: 36)
    }

    @AppStorage("showGPSDetails") private var showGPSDetails = false
    @AppStorage("showHeading") private var showHeading = false

    /// Coordinates, GPS accuracy, and altitude are developer telemetry,
    /// not driver info — absent unless the flag is on, and a FIXED-height
    /// slot when it is, so the first GPS fix never reflows the dashboard.
    /// (The "waiting for GPS" state lives in the trip bar, which is always
    /// present — nothing here may appear or vanish with driving state.)
    @ViewBuilder
    private var positionSection: some View {
        if showGPSDetails {
            VStack(spacing: 2) {
                if let coordinate = session.context.coordinate {
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
            }
            .frame(height: 42)
        }
    }

    /// Always present — zeros while parked — so starting a drive never
    /// reflows the layout and the Start Drive button stays put.
    private var tripSection: some View {
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
                    if session.context.coordinate == nil {
                        Label("GPS…", systemImage: "antenna.radiowaves.left.and.right")
                    } else if session.isPaused {
                        // Still recording — the drive resumes by itself when
                        // the car moves, so say "paused", never "ended".
                        Label("Paused", systemImage: "pause.circle")
                            .foregroundStyle(.orange)
                    } else {
                        Label(
                            session.isStationary ? "Stationary" : "Moving",
                            systemImage: session.isStationary ? "parkingsign" : "car.fill"
                        )
                    }
                }
            }
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
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

    /// Hands-free mode replaces the idle Start Drive button with a status
    /// line of the same footprint — no layout shift, and no chore. A live
    /// drive still gets its Stop button, so ending one early never depends
    /// on detection working.
    private var handsFreeIdle: Bool {
        handsFree && autoStartMode == AutoDriveMonitor.Mode.automatic.rawValue && !session.isDriving
    }

    @ViewBuilder
    private var driveButton: some View {
        if handsFreeIdle {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text("Watching for drives")
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.4), in: Capsule())
        } else {
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

#Preview {
    DashboardView(session: DriveSessionManager())
}
