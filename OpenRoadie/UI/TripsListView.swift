import MapKit
import SwiftData
import SwiftUI

/// Local driving history. Everything shown here lives only on this device.
struct TripsListView: View {
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @Query(sort: \DriveNote.timestamp, order: .reverse) private var notes: [DriveNote]
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
                        Section {
                            AllDrivesMap(trips: trips)
                                .frame(height: 220)
                                .listRowInsets(EdgeInsets())
                        }
                        Section {
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
                        if !notes.isEmpty {
                            Section("Notes") {
                                ForEach(notes) { note in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Label(note.text, systemImage: "quote.bubble")
                                            .font(.subheadline)
                                        Text(note.timestamp, format: .dateTime.month().day().hour().minute())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .onDelete(perform: deleteNotes)
                            }
                        }
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

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(notes[index])
        }
    }
}

/// Every recorded drive overlaid on one map — the "everywhere I've driven" view.
private struct AllDrivesMap: View {
    let trips: [Trip]

    /// Cap the overlay work for very large histories; newest drives win.
    private static let maxTrips = 50

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(trips.prefix(Self.maxTrips)) { trip in
                let coordinates = trip.route.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                }
                if coordinates.count >= 2 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(
                            .blue.opacity(0.65),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .allowsHitTesting(false)
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
