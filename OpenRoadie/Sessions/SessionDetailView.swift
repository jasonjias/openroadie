import MapKit
import SwiftData
import SwiftUI

/// Detail for a non-drive session card: the card's facts at full size,
/// the exact time range, and — for a stop — where it happened.
struct SessionDetailView: View {
    let item: SessionItem
    let accent: Color

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

                Text(item.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(item.metric)
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Grid(horizontalSpacing: 28, verticalSpacing: 12) {
                    GridRow {
                        fact("Started", item.start.formatted(.dateTime.hour().minute()))
                        fact("Ended", item.end.formatted(.dateTime.hour().minute()))
                        fact("Total", DriveFormatting.compactDuration(item.duration))
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal)

                if let coordinate = item.coordinate {
                    Map(initialPosition: .camera(MapCamera(
                        centerCoordinate: CLLocationCoordinate2D(
                            latitude: coordinate.latitude, longitude: coordinate.longitude
                        ),
                        distance: 1_200
                    )), interactionModes: []) {
                        Marker(item.title, systemImage: item.symbol, coordinate: CLLocationCoordinate2D(
                            latitude: coordinate.latitude, longitude: coordinate.longitude
                        ))
                        .tint(accent)
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal)
                }
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
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
    let accent: Color

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationLink {
            if item.kind == .drive, let tripID = item.tripID,
               let trip = modelContext.model(for: tripID) as? Trip {
                TripDetailView(trip: trip)
            } else {
                SessionDetailView(item: item, accent: accent)
            }
        } label: {
            SessionCard(item: item, accent: accent)
        }
        .buttonStyle(.plain)
    }
}
