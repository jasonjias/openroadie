import MapKit
import SwiftData
import SwiftUI

/// The full-screen interactive trip map, backed by MKMapView instead of
/// SwiftUI's Map for exactly one reason: the system balloon marker plays
/// a springy bounce on selection, and the only way to disable it is a
/// UIKit-level MKMarkerAnnotationView override. Same colored route, same
/// pins — tap one and the selection flows out through `selectedPin`.
struct TripMapView: UIViewRepresentable {
    let route: [TripPoint]
    let mode: RouteColorMode
    let events: [DriveEvent]
    let notes: [DriveNote]
    @Binding var selectedPin: TripMapPin?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.register(
            StillMarkerView.self,
            forAnnotationViewWithReuseIdentifier: StillMarkerView.reuseID
        )

        map.addOverlays(makeOverlays())
        map.addAnnotations(makeAnnotations())

        let union = map.overlays.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
        if !union.isNull {
            map.setVisibleMapRect(
                union,
                edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
                animated: false
            )
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        // The x on the popup clears the binding — mirror that back into
        // the map's selection state.
        if selectedPin == nil {
            for annotation in map.selectedAnnotations {
                map.deselectAnnotation(annotation, animated: false)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func makeOverlays() -> [BandPolyline] {
        let coordinates = route.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        return RouteColoring.runs(for: route, mode: mode).map { run in
            let slice = Array(coordinates[run.pointIndices])
            let polyline = BandPolyline(coordinates: slice, count: slice.count)
            polyline.color = UIColor(RouteColoring.color(forBand: run.bandIndex, mode: mode))
            return polyline
        }
    }

    private func makeAnnotations() -> [PinAnnotation] {
        var pins: [PinAnnotation] = []
        let coordinates = route.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        if let start = coordinates.first {
            pins.append(PinAnnotation(
                coordinate: start, title: "Start", glyph: "flag.fill", tint: .systemGreen, pin: nil
            ))
        }
        if let end = coordinates.last, coordinates.count >= 2 {
            pins.append(PinAnnotation(
                coordinate: end, title: "End", glyph: "flag.checkered", tint: .systemRed, pin: nil
            ))
        }
        for event in events.filter(\.isMapWorthy) {
            if let anchor = event.coordinate {
                pins.append(PinAnnotation(
                    coordinate: CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude),
                    title: event.markerTitle,
                    glyph: event.displayIcon,
                    tint: UIColor(event.displayColor),
                    pin: .event(event.persistentModelID)
                ))
            }
        }
        for note in notes {
            if let anchor = note.coordinate {
                pins.append(PinAnnotation(
                    coordinate: CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude),
                    title: note.text,
                    glyph: "quote.bubble.fill",
                    tint: .systemIndigo,
                    pin: .note(note.persistentModelID)
                ))
            }
        }
        return pins
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TripMapView

        init(parent: TripMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? BandPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = polyline.color
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: StillMarkerView.reuseID, for: pin
            ) as! StillMarkerView
            view.markerTintColor = pin.tint
            view.glyphImage = UIImage(systemName: pin.glyph)
            view.displayPriority = .required
            view.canShowCallout = false
            view.animatesWhenAdded = false
            // Start/End are informational; only event/note pins select.
            view.isEnabled = pin.pin != nil
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Kill the marker's selection wobble. MapKit's PRIVATE selection
            // path adds explicit spring/sway CAAnimations to the balloon's
            // internal layers, ignoring setSelected(_:animated:) overrides,
            // CATransaction.setDisableActions, and performWithoutAnimation.
            // didSelect fires synchronously before those animations commit,
            // so removing them here means no bounce frame ever renders.
            Self.stripAnimations(view)
            parent.selectedPin = (view.annotation as? PinAnnotation)?.pin
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            Self.stripAnimations(view)
            parent.selectedPin = nil
        }

        private static func stripAnimations(_ view: UIView) {
            var stack: [CALayer] = [view.layer]
            while let layer = stack.popLast() {
                layer.removeAllAnimations()
                stack.append(contentsOf: layer.sublayers ?? [])
            }
        }
    }
}

/// Plain system balloon marker; the anti-wobble work happens in the
/// coordinator's didSelect/didDeselect (see stripAnimations).
private final class StillMarkerView: MKMarkerAnnotationView {
    static let reuseID = "stillMarker"
}

/// A polyline that knows the band color it should render with.
private final class BandPolyline: MKPolyline {
    var color: UIColor = .systemBlue
}

/// One pin on the trip map; `pin` is nil for the untappable Start/End flags.
private final class PinAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let glyph: String
    let tint: UIColor
    let pin: TripMapPin?

    init(coordinate: CLLocationCoordinate2D, title: String, glyph: String, tint: UIColor, pin: TripMapPin?) {
        self.coordinate = coordinate
        self.title = title
        self.glyph = glyph
        self.tint = tint
        self.pin = pin
    }
}
