import MapKit
import SwiftData
import SwiftUI

/// Detail for a non-drive session card: the card's facts at full size,
/// the exact time range, and — for a stop — where it happened.
struct SessionDetailView: View {
    let item: SessionItem

    private var accent: Color { item.kind.tint }

    @State private var route: [Coordinate] = []
    @State private var health = HealthSessions()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(accent.opacity(0.16))
                    Image(systemName: item.symbol)
                        .font(.system(size: 40))
                        .foregroundStyle(accent)
                }
                .frame(width: 104, height: 104)
                .padding(.top, 24)

                Text(item.placeName ?? item.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(item.metric)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Grid(horizontalSpacing: 28, verticalSpacing: 12) {
                    GridRow {
                        fact("Started", item.start.formatted(.dateTime.hour().minute()))
                        fact("Ended", item.end.formatted(.dateTime.hour().minute()))
                        fact("Total", DriveFormatting.compactDuration(item.duration))
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal)

                if let weather = item.weather {
                    WeatherCard(weather: weather, usAqi: item.usAqi, placeName: item.placeName)
                        .padding(.horizontal)
                }

                if let coordinate = item.coordinate, item.route == nil {
                    let center = CLLocationCoordinate2D(
                        latitude: coordinate.latitude, longitude: coordinate.longitude
                    )
                    // A walk's location is inferred (nearest parked fix), so
                    // it draws as an AREA around the anchor — never a fake
                    // route. Stops pin their exact spot.
                    let roaming = item.kind == .walk
                        ? max(150, (item.meters ?? 300) * 0.5)
                        : 0
                    Map(initialPosition: .camera(MapCamera(
                        centerCoordinate: center,
                        distance: max(1_200, roaming * 6)
                    )), interactionModes: []) {
                        if roaming > 0 {
                            MapCircle(center: center, radius: roaming)
                                .foregroundStyle(accent.opacity(0.15))
                                .stroke(accent.opacity(0.6), lineWidth: 2)
                        }
                        Marker(item.placeName?.components(separatedBy: " · ").first ?? item.title,
                               systemImage: item.symbol, coordinate: center)
                            .tint(accent)
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal)
                    if item.kind == .walk {
                        Text("Approximate — anchored to where the phone last had a fix (usually where you parked). Walks recorded as watch workouts carry their exact route.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                }

                // The GPS trail the watch recorded with an outdoor workout.
                if route.count >= 2 {
                    let coordinates = route.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                    Map(initialPosition: .automatic, interactionModes: []) {
                        MapPolyline(coordinates: coordinates)
                            .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        if let start = coordinates.first {
                            Marker("Start", systemImage: "flag.fill", coordinate: start).tint(.green)
                        }
                        if let end = coordinates.last {
                            Marker("End", systemImage: "flag.checkered", coordinate: end).tint(.red)
                        }
                    }
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal)
                }

                if item.kind == .walk, item.routeIsCoarse, !route.isEmpty {
                    Text("Coarse trail — one point per ~500 m, from Always-on wake-ups. Walks recorded as watch workouts carry an exact route.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                if item.kind == .walk, item.coordinate == nil, item.route == nil {
                    Text("No location for this walk — it comes from the motion coprocessor's history, which records activity but not position, and no drive pinned the phone nearby. Walks recorded as watch workouts carry their exact route.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }
        }
        .task {
            if let trail = item.route {
                route = HealthSessions.thin(trail, to: 300)
            } else if let uuid = item.workoutUUID {
                route = await health.route(forWorkoutWith: uuid)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.start.formatted(.dateTime.month().day()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Shared routing for a tapped session card: drives open the full trip
/// detail (same as the Drives list), everything else the session detail.
struct SessionCardLink: View {
    let item: SessionItem

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationLink {
            if item.kind == .drive, let tripID = item.tripID,
               let trip = modelContext.model(for: tripID) as? Trip {
                TripDetailView(trip: trip)
            } else {
                SessionDetailView(item: item)
            }
        } label: {
            SessionCard(item: item)
        }
        .buttonStyle(.plain)
    }
}
