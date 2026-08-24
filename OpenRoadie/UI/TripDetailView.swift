import MapKit
import SwiftUI

/// One past drive: the recorded route drawn on a map, with trip stats.
/// MapKit renders the tiles; the route itself never leaves the device.
struct TripDetailView: View {
    let trip: Trip

    var body: some View {
        let coordinates = trip.route.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }

        VStack(spacing: 0) {
            Map(initialPosition: .automatic) {
                if coordinates.count >= 2 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let start = coordinates.first {
                    Marker("Start", systemImage: "flag.fill", coordinate: start)
                        .tint(.green)
                }
                if let end = coordinates.last, coordinates.count >= 2 {
                    Marker("End", systemImage: "flag.checkered", coordinate: end)
                        .tint(.red)
                }
            }
            .mapStyle(.standard(elevation: .flat))

            statsGrid
        }
        .navigationTitle(trip.startDate.formatted(.dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statsGrid: some View {
        Grid(horizontalSpacing: 24, verticalSpacing: 12) {
            GridRow {
                stat("Distance", DriveFormatting.miles(fromMeters: trip.distance))
                stat("Duration", trip.duration.map(DriveFormatting.duration) ?? "—")
            }
            GridRow {
                stat("Avg speed", trip.averageSpeed.map { "\(DriveFormatting.milesPerHour(fromMetersPerSecond: $0)) mph" } ?? "—")
                stat("Max speed", trip.maxSpeed.map { "\(DriveFormatting.milesPerHour(fromMetersPerSecond: $0)) mph" } ?? "—")
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.bar)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
