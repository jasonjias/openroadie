import MapKit
import SwiftData
import SwiftUI

/// One past drive: the recorded route drawn on a map, with trip stats and
/// any notes spoken during the drive as speech bubbles along the route.
/// MapKit renders the tiles; the route itself never leaves the device.
struct TripDetailView: View {
    let trip: Trip

    @Query private var tripNotes: [DriveNote]
    @Query private var tripEvents: [DriveEvent]

    init(trip: Trip) {
        self.trip = trip
        let start = trip.startDate
        let end = trip.endDate ?? .distantFuture
        _tripNotes = Query(filter: #Predicate<DriveNote> {
            $0.timestamp >= start && $0.timestamp <= end
        })
        _tripEvents = Query(filter: #Predicate<DriveEvent> {
            $0.timestamp >= start && $0.timestamp <= end
        })
    }

    @State private var colorMode: RouteColorMode = .speed
    @State private var shareURL: URL?

    var body: some View {
        let route = trip.route
        let coordinates = route.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let runs = RouteColoring.runs(for: route, mode: colorMode)

        VStack(spacing: 0) {
            Map(initialPosition: .automatic) {
                ColoredRoute(route: route, mode: colorMode)
                if let start = coordinates.first {
                    Marker("Start", systemImage: "flag.fill", coordinate: start)
                        .tint(.green)
                }
                if let end = coordinates.last, coordinates.count >= 2 {
                    Marker("End", systemImage: "flag.checkered", coordinate: end)
                        .tint(.red)
                }
                // Hard braking / acceleration moments along the route.
                // (Overspeed crossings color the route itself in vs-Limit mode.)
                ForEach(tripEvents.filter { $0.kind == "hardBraking" || $0.kind == "hardAcceleration" }) { event in
                    if let anchor = event.coordinate {
                        Marker(
                            event.kind == "hardBraking" ? "Hard brake" : "Hard accel",
                            systemImage: "exclamationmark.triangle.fill",
                            coordinate: CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude)
                        )
                        .tint(event.kind == "hardBraking" ? .red : .orange)
                    }
                }
                // Notes spoken during this drive, as speech bubbles.
                ForEach(tripNotes) { note in
                    if let anchor = note.coordinate {
                        Marker(
                            note.text,
                            systemImage: "quote.bubble.fill",
                            coordinate: CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude)
                        )
                        .tint(.indigo)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))

            Picker("Coloring", selection: $colorMode) {
                ForEach(RouteColorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            RouteLegend(runs: runs, mode: colorMode)
                .padding(.top, 6)
            statsGrid
        }
        .navigationTitle(trip.startDate.formatted(.dateTime.month().day().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    // A speed-colored route card — the shape of the drive,
                    // no map tiles, no street names.
                    ShareLink(item: shareURL, preview: SharePreview("OpenRoadie Trip", image: Image(uiImage: UIImage(contentsOfFile: shareURL.path) ?? UIImage())))
                }
            }
        }
        .task {
            shareURL = TripShareRenderer.pngURL(for: trip)
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
