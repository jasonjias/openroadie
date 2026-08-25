import Charts
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
    @State private var showsFullMap = false

    var body: some View {
        let route = trip.route
        let runs = RouteColoring.runs(for: route, mode: colorMode)

        ScrollView {
            VStack(spacing: 0) {
                // A non-interactive map preview, so the page scrolls freely
                // past it — tap to open the full interactive map.
                Map(initialPosition: .automatic, interactionModes: []) {
                    routeContent
                }
                .mapStyle(.standard(elevation: .flat))
                .frame(height: 300)
                .overlay(alignment: .bottomTrailing) {
                    Label("Tap to explore", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                        .padding(10)
                }
                .contentShape(Rectangle())
                .onTapGesture { showsFullMap = true }

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
                speedChart(route: route)
                eventsSection
                statsGrid
            }
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
        .fullScreenCover(isPresented: $showsFullMap) {
            fullMap
        }
    }

    /// Everything drawn on the map — shared by the inline preview and the
    /// full-screen interactive version so they always match.
    @MapContentBuilder
    private var routeContent: some MapContent {
        let route = trip.route
        let coordinates = route.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        ColoredRoute(route: route, mode: colorMode)
        if let start = coordinates.first {
            Marker("Start", systemImage: "flag.fill", coordinate: start)
                .tint(.green)
        }
        if let end = coordinates.last, coordinates.count >= 2 {
            Marker("End", systemImage: "flag.checkered", coordinate: end)
                .tint(.red)
        }
        // Every score-affecting mistake with a recorded location.
        EventMarkers(events: tripEvents)
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

    /// The tapped-open interactive map: same content, full screen, pannable.
    private var fullMap: some View {
        NavigationStack {
            Map(initialPosition: .automatic) {
                routeContent
            }
            .mapStyle(.standard(elevation: .flat))
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(trip.startDate.formatted(.dateTime.month().day().hour().minute()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showsFullMap = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// What happened on this drive, in order — same rows as the day's
    /// safety sheet, scoped to just this trip.
    @ViewBuilder
    private var eventsSection: some View {
        let events = tripEvents.sorted { $0.timestamp < $1.timestamp }
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Events")
                    .font(.headline)
                ForEach(events) { event in
                    EventRow(event: event)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    /// Speed over the drive, with the posted limit as a dashed line —
    /// drawn entirely from the route points we already store.
    @ViewBuilder
    private func speedChart(route: [TripPoint]) -> some View {
        let start = trip.startDate
        let samples = route.compactMap { point -> (minutes: Double, mph: Double, limit: Double?)? in
            guard let speed = point.speed else { return nil }
            return (
                minutes: point.timestamp.timeIntervalSince(start) / 60,
                mph: speed * 2.236936,
                limit: point.speedLimit.map { $0 * 2.236936 }
            )
        }
        if samples.count >= 5 {
            Chart {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    LineMark(
                        x: .value("Time", sample.minutes),
                        y: .value("Speed", sample.mph),
                        series: .value("Series", "Speed")
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
                }
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    if let limit = sample.limit {
                        LineMark(
                            x: .value("Time", sample.minutes),
                            y: .value("Limit", limit),
                            series: .value("Series", "Limit")
                        )
                        .foregroundStyle(.red.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                }
            }
            .chartXAxisLabel("minutes", alignment: .trailing)
            .chartYAxisLabel("mph")
            .frame(height: 130)
            .padding(.horizontal)
            .padding(.top, 8)
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
