import SwiftUI

/// Developer/prototype dashboard: everything OpenRoadie currently knows about
/// the drive, biased toward observability over polish.
struct DashboardView: View {
    let session: DriveSessionManager

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 24) {
            Text("OPENROADIE")
                .font(.caption.weight(.bold))
                .tracking(4)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Spacer()

            speedSection
            headingSection
            positionSection

            Spacer()

            tripSection
            statusBanner
            driveButton
        }
        .padding()
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

    private var speedUnitLine: String {
        if let accuracy = session.context.speedAccuracy {
            let mph = max(1, DriveFormatting.milesPerHour(fromMetersPerSecond: accuracy))
            return "mph  ± \(mph)"
        }
        return "mph"
    }

    private var headingSection: some View {
        HStack(spacing: 10) {
            if let course = session.context.course {
                CompassNeedle(course: course)
                Text("\(DriveFormatting.cardinal(fromCourse: course)) · \(Int(course.rounded()))°")
            } else {
                Text("heading —")
            }
        }
        .font(.title3.weight(.medium))
        .foregroundStyle(.secondary)
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
private struct CompassNeedle: View {
    let course: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tertiary, lineWidth: 1.5)
            Image(systemName: "location.north.fill")
                .font(.system(size: 13))
                .rotationEffect(.degrees(course))
                .animation(.smooth(duration: 0.5), value: course)
        }
        .frame(width: 28, height: 28)
    }
}

#Preview {
    DashboardView(session: DriveSessionManager())
}
