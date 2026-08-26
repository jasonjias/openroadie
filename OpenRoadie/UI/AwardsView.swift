import SwiftData
import SwiftUI

/// The garage: every vehicle with its pre-rendered thumbnail. Free ones
/// select instantly; earnable ones show their award and unlock the
/// moment the driving record clears the bar.
struct VehiclePickerView: View {
    @AppStorage(Vehicle.defaultsKey) private var sceneVehicle = Vehicle.classic.id
    @Query private var trips: [Trip]
    @Query private var events: [DriveEvent]

    var body: some View {
        let aggregates = Awards.aggregates(trips: trips, events: events)
        List {
            ForEach(Vehicle.all) { vehicle in
                let unlocked = Awards.isUnlocked(vehicle.id, aggregates: aggregates)
                Button {
                    guard unlocked, vehicle.isAvailable else { return }
                    sceneVehicle = vehicle.id
                } label: {
                    HStack(spacing: 12) {
                        Image(vehicle.thumbnailName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 48)
                            .grayscale(unlocked ? 0 : 1)
                            .opacity(unlocked ? 1 : 0.5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vehicle.isAvailable ? vehicle.title : "\(vehicle.title) — soon")
                                .foregroundStyle(unlocked ? .primary : .secondary)
                            if !unlocked, let award = Awards.unlock(for: vehicle.id) {
                                Label(Awards.requirementText(award), systemImage: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
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

/// Every award with live progress — nothing is granted or stored, the
/// driving record IS the trophy case.
struct AwardsView: View {
    @Query private var trips: [Trip]
    @Query private var events: [DriveEvent]

    var body: some View {
        let progress = Awards.progress(for: Awards.aggregates(trips: trips, events: events))
        List {
            Section {
                ForEach(progress) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.award.icon)
                            .font(.title3)
                            .frame(width: 34)
                            .foregroundStyle(item.earned ? Color.yellow : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.award.title)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if item.earned {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.yellow)
                                } else {
                                    Text(progressLabel(item))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ProgressView(value: item.fraction)
                                .tint(item.earned ? .yellow : .accentColor)
                            if let vehicleId = item.award.unlocksVehicle {
                                Text(item.earned
                                     ? "Unlocked: \(Vehicle.find(vehicleId).title)"
                                     : "Unlocks: \(Vehicle.find(vehicleId).title)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Awards come straight from your driving record on this device — earn them by driving, keep them by nothing at all.")
            }
        }
        .navigationTitle("Awards")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func progressLabel(_ item: Awards.Progress) -> String {
        "\(Int(item.value)) / \(Int(item.award.goal))"
    }
}
