import SwiftData
import SwiftUI

/// Local driving history. Everything shown here lives only on this device.
struct TripsListView: View {
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView(
                        "No trips yet",
                        systemImage: "car",
                        description: Text("Drives you record will show up here. Everything stays on this device.")
                    )
                } else {
                    List {
                        ForEach(trips) { trip in
                            if trip.endDate == nil {
                                TripRow(trip: trip)
                            } else {
                                NavigationLink(value: trip.persistentModelID) {
                                    TripRow(trip: trip)
                                }
                            }
                        }
                        .onDelete(perform: deleteTrips)
                    }
                    .navigationDestination(for: PersistentIdentifier.self) { id in
                        if let trip = modelContext.model(for: id) as? Trip {
                            TripDetailView(trip: trip)
                        }
                    }
                }
            }
            .navigationTitle("Trips")
        }
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(trips[index])
        }
    }
}

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.startDate, format: .dateTime.weekday(.wide).month().day().hour().minute())
                .font(.headline)
            HStack(spacing: 12) {
                if let duration = trip.duration {
                    Label(DriveFormatting.duration(duration), systemImage: "clock")
                    Label(DriveFormatting.miles(fromMeters: trip.distance), systemImage: "road.lanes")
                    if let maxSpeed = trip.maxSpeed {
                        Label("\(DriveFormatting.milesPerHour(fromMetersPerSecond: maxSpeed)) mph max", systemImage: "gauge.high")
                    }
                } else {
                    Label("Recording…", systemImage: "record.circle")
                        .foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    TripsListView()
        .modelContainer(try! TripStore.inMemory().container)
}
