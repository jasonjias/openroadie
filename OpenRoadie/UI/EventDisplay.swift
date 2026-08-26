import MapKit
import SwiftData
import SwiftUI

/// One vocabulary for drive events everywhere they appear — the safety
/// sheet, trip rows, trip detail, and map markers all use these.
extension DriveEvent {
    var displayIcon: String {
        switch kind {
        case "hardBraking", "hardAcceleration": "exclamationmark.triangle.fill"
        case "harshCornering": "arrow.turn.up.right"
        case "phoneUse": "iphone.radiowaves.left.and.right"
        default: "gauge.high"
        }
    }

    var displayColor: Color {
        switch kind {
        case "hardBraking": .red
        case "hardAcceleration": .orange
        case "wellOverLimit": .red
        case "harshCornering": .orange
        case "phoneUse": .purple
        default: .yellow
        }
    }

    var displayLabel: String {
        switch kind {
        case "hardBraking": "Hard braking"
        case "hardAcceleration": "Hard acceleration"
        case "overLimit": "Crossed the posted limit"
        case "wellOverLimit": "More than 5 over the limit"
        case "harshCornering": "Harsh cornering"
        case "phoneUse": "Phone handled while driving"
        default: kind
        }
    }

    /// Short marker title ("Hard brake"), for map pins where the full
    /// sentence label would crowd the map.
    var markerTitle: String {
        switch kind {
        case "hardBraking": "Hard brake"
        case "hardAcceleration": "Hard accel"
        case "wellOverLimit": "Well over limit"
        case "harshCornering": "Harsh corner"
        case "phoneUse": "Phone use"
        default: displayLabel
        }
    }

    var displayDetail: String {
        var parts = [timestamp.formatted(.dateTime.hour().minute())]
        if let speed = speedMph {
            parts.append("\(Int(speed.rounded())) mph")
        }
        if peakG > 0 {
            // phoneUse stores the handling duration in the peakG slot.
            parts.append(kind == "phoneUse"
                ? String(format: "%.1fs in hand", peakG)
                : String(format: "%.2f g", peakG))
        }
        return parts.joined(separator: " · ")
    }

    /// The score-affecting mistakes worth a pin on the map. Plain
    /// limit crossings (chime tier) stay off — the vs-limit route
    /// coloring already tells that story.
    var isMapWorthy: Bool {
        ["hardBraking", "hardAcceleration", "harshCornering", "phoneUse", "wellOverLimit"].contains(kind)
    }
}

/// A compact icon + label + detail row for one drive event.
struct EventRow: View {
    let event: DriveEvent
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.displayIcon)
                .font(compact ? .caption : .body)
                .foregroundStyle(event.displayColor)
                .frame(width: compact ? 18 : 24)
            if compact {
                Text(event.displayLabel)
                    .font(.caption.weight(.medium))
                Spacer(minLength: 4)
                Text(event.displayDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.displayLabel)
                        .font(.subheadline.weight(.medium))
                    Text(event.displayDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// What a tapped map pin refers to — resolved back to the model by ID.
enum TripMapPin: Hashable {
    case event(PersistentIdentifier)
    case note(PersistentIdentifier)
}

/// Map pins for the mistakes that have a recorded location. Tagged for
/// selection — inert on maps without a selection binding.
///
/// Custom Annotation badges, not system Markers: MapKit's balloon marker
/// bounces on selection with no way to opt out.
struct EventMarkers: MapContent {
    let events: [DriveEvent]

    var body: some MapContent {
        ForEach(events.filter(\.isMapWorthy)) { event in
            if let anchor = event.coordinate {
                Annotation(
                    event.markerTitle,
                    coordinate: CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude)
                ) {
                    MapPinBadge(systemImage: event.displayIcon, color: event.displayColor)
                }
                .tag(TripMapPin.event(event.persistentModelID))
            }
        }
    }
}

/// A small round pin: colored disc, white glyph, hairline border. Static —
/// tapping selects without any animation of its own.
struct MapPinBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(color.gradient, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}
