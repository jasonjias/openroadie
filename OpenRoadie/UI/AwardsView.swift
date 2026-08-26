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
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Vehicle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Lifetime driving records, straight from the stored trips — total
/// time behind the wheel, total distance, the all-time top speed, and
/// the overall average pace.
struct DrivingRecordsView: View {
    @Query private var trips: [Trip]

    var body: some View {
        let finished = trips.filter { $0.endDate != nil }
        let totalSeconds = finished.reduce(0.0) { $0 + ($1.duration ?? 0) }
        let totalMiles = finished.reduce(0.0) { $0 + $1.distance } / 1609.344
        let maxSpeed = finished.compactMap(\.maxSpeed).max()
        let averageMph = totalSeconds > 0 ? totalMiles / (totalSeconds / 3600) : nil

        List {
            Section {
                record("Drives", "\(finished.count)", icon: "car.2")
                record("Total drive time", DriveFormatting.duration(totalSeconds), icon: "clock")
                record("Total distance", String(format: "%.1f mi", totalMiles), icon: "road.lanes")
                record(
                    "Top speed",
                    maxSpeed.map { "\(DriveFormatting.milesPerHour(fromMetersPerSecond: $0)) mph" } ?? "—",
                    icon: "gauge.high"
                )
                record(
                    "Average speed",
                    averageMph.map { String(format: "%.0f mph", $0) } ?? "—",
                    icon: "speedometer"
                )
            } footer: {
                Text("All-time totals from every drive stored on this device.")
            }
        }
        .navigationTitle("Driving Records")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func record(_ label: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
