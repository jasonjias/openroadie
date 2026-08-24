import MapKit
import SwiftUI

/// One past drive: the recorded route drawn on a map, with trip stats.
/// MapKit renders the tiles; the route itself never leaves the device.
struct TripDetailView: View {
    let trip: Trip

    var body: some View {
        let route = trip.route
        let coordinates = route.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        // Activity-style speed coloring: one polyline per contiguous speed band.
        let runs = RouteColoring.runs(forSpeeds: route.map(\.speed))

        VStack(spacing: 0) {
            Map(initialPosition: .automatic) {
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    MapPolyline(coordinates: Array(coordinates[run.pointIndices]))
                        .stroke(
                            RouteColoring.bands[run.bandIndex].color,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
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

            speedLegend
            statsGrid
        }
        .navigationTitle(trip.startDate.formatted(.dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var speedLegend: some View {
        HStack(spacing: 10) {
            legendEntry(.teal, "<15")
            legendEntry(.green, "15–30")
            legendEntry(.yellow, "30–45")
            legendEntry(.orange, "45–60")
            legendEntry(.red, "60+ mph")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }

    private func legendEntry(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(label)
        }
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
