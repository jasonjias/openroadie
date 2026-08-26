import SwiftData
import SwiftUI

/// A vehicle thumbnail, loaded straight from its bundled PNG —
/// name-based Image lookup misses loose bundle resources on device.
struct VehicleThumbnail: View {
    let vehicle: Vehicle

    var body: some View {
        if let path = Bundle.main.path(forResource: vehicle.thumbnailName, ofType: "png"),
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "car.fill")
                .foregroundStyle(.secondary)
        }
    }
}

/// The garage: every vehicle with its pre-rendered hero thumbnail.
struct VehiclePickerView: View {
    @AppStorage(Vehicle.defaultsKey) private var sceneVehicle = Vehicle.classic.id

    var body: some View {
        List {
            ForEach(Vehicle.all) { vehicle in
                Button {
                    guard vehicle.isAvailable else { return }
                    sceneVehicle = vehicle.id
                } label: {
                    HStack(spacing: 12) {
                        VehicleThumbnail(vehicle: vehicle)
                            .frame(width: 64, height: 48)
                        Text(vehicle.isAvailable ? vehicle.title : "\(vehicle.title) — soon")
                        Spacer()
                        if sceneVehicle == vehicle.id {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                                .foregroundStyle(.tint)
                        }
                    }
                    // The whole row is the tap target — without an explicit
                    // shape, only the opaque content (image, text) is.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Vehicle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lifetime driving history, straight from the stored trips.
struct DrivingHistoryView: View {
    @Query private var trips: [Trip]

    var body: some View {
        let history = DrivingHistory.compute(trips: trips)

        List {
            Section("Totals") {
                row("Drives", "\(history.drives)", icon: "car.2")
                row("Days driven", "\(history.daysDriven)", icon: "calendar")
                row("Drive time", DriveFormatting.duration(history.totalSeconds), icon: "clock")
                row("Distance", String(format: "%.1f mi", history.totalMiles), icon: "road.lanes")
                row(
                    "Average speed",
                    history.averageMph.map { String(format: "%.0f mph", $0) } ?? "—",
                    icon: "speedometer"
                )
            }

            Section("Per driving day") {
                row("Time", DriveFormatting.duration(history.averageSecondsPerDay), icon: "clock.arrow.circlepath")
                row("Distance", String(format: "%.1f mi", history.averageMilesPerDay), icon: "point.topleft.down.to.point.bottomright.curvepath")
            }

            Section {
                row(
                    "Top speed",
                    history.maxSpeedMps.map { "\(DriveFormatting.milesPerHour(fromMetersPerSecond: $0)) mph" } ?? "—",
                    icon: "gauge.high"
                )
                row("Longest drive", String(format: "%.1f mi", history.longestMiles), icon: "map")
                row("Longest time", DriveFormatting.duration(history.longestSeconds), icon: "hourglass")
                row(
                    "Slowest pace",
                    history.slowestPaceSecondsPerMile.map { String(format: "%.1f min/mi", $0 / 60) } ?? "—",
                    icon: "car.rear.and.tire.marks"
                )
                row(
                    "Earliest departure",
                    history.earliestStartMinute.map { DrivingHistory.timeLabel(minute: $0) } ?? "—",
                    icon: "sunrise"
                )
                row(
                    "Latest arrival",
                    history.latestEndMinute.map { DrivingHistory.timeLabel(minute: $0) } ?? "—",
                    icon: "moon.stars"
                )
            } header: {
                Text("Records")
            } footer: {
                Text("Slowest pace is the most time a mile has ever taken you (drives of a mile or more) — a rough traffic gauge. All figures come from the drives stored on this device.")
            }
        }
        .navigationTitle("Driving History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
