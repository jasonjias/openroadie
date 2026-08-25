import MapKit
import SwiftUI

/// Nearby points of interest — gas, food, coffee, chargers, landmarks —
/// from OpenStreetMap, centered on the drive (or a one-shot fix when parked).
struct NearbyView: View {
    let session: DriveSessionManager

    @State private var category: PlaceCategory = .food
    @State private var results: [(place: Place, distance: Double)] = []
    @State private var origin: Coordinate?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var service = PlaceService()
    @State private var camera: MapCameraPosition = .automatic
    @State private var searchText = ""
    @State private var searchResults: [(place: FoundPlace, distance: Double)]?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                categoryPicker
                list
            }
            .navigationTitle("Nearby")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search anything — boba, pharmacy…")
            .onSubmit(of: .search) {
                Task { await runSearch() }
            }
            .onChange(of: searchText) { _, text in
                if text.isEmpty { searchResults = nil; camera = .automatic }
            }
        }
        .task(id: category) { await load() }
        .refreshable { await load(force: true) }
    }

    /// The standard tap pattern: hand off to the navigation app. OpenRoadie
    /// informs; Apple Maps navigates.
    private func openDirections(name: String, to coordinate: Coordinate) {
        let placemark = MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: coordinate.latitude, longitude: coordinate.longitude
        ))
        let item = MKMapItem(placemark: placemark)
        item.name = name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving,
        ])
    }

    private func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        errorText = nil
        isLoading = true
        defer { isLoading = false }

        let coordinate: Coordinate?
        if let driving = session.context.coordinate {
            coordinate = driving
        } else {
            coordinate = await LocationService.currentFix()
        }
        guard let coordinate else {
            errorText = "Location unavailable. Check location permission in Settings."
            return
        }
        origin = coordinate
        do {
            let found = try await PlaceSearch.search(query, near: coordinate)
            searchResults = PlaceSearch.sortedByDistance(found, from: coordinate)
            camera = .automatic
        } catch {
            errorText = "Search didn't respond. Try again in a moment."
            searchResults = []
        }
    }

    private var map: some View {
        Map(position: $camera) {
            if let origin {
                Annotation("You", coordinate: CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)) {
                    ZStack {
                        Circle().fill(.blue.opacity(0.25)).frame(width: 22, height: 22)
                        Circle().fill(.blue).frame(width: 10, height: 10)
                    }
                }
            }
            if let searchResults {
                ForEach(searchResults.prefix(25), id: \.place.id) { result in
                    Marker(
                        result.place.name,
                        systemImage: "magnifyingglass",
                        coordinate: CLLocationCoordinate2D(
                            latitude: result.place.coordinate.latitude,
                            longitude: result.place.coordinate.longitude
                        )
                    )
                    .tint(.purple)
                }
            } else {
                ForEach(results.prefix(25), id: \.place.id) { result in
                    Marker(
                        result.place.displayName,
                        systemImage: category.systemImage,
                        coordinate: CLLocationCoordinate2D(
                            latitude: result.place.coordinate.latitude,
                            longitude: result.place.coordinate.longitude
                        )
                    )
                    .tint(.orange)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(height: 280)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlaceCategory.allCases) { candidate in
                    Button {
                        category = candidate
                    } label: {
                        Label(candidate.title, systemImage: candidate.systemImage)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(candidate == category ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary))
                            )
                            .foregroundStyle(candidate == category ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var list: some View {
        if let searchResults {
            if searchResults.isEmpty && !isLoading {
                Spacer()
                ContentUnavailableView.search(text: searchText)
                Spacer()
            } else {
                List(searchResults.prefix(40), id: \.place.id) { result in
                    Button {
                        openDirections(name: result.place.name, to: result.place.coordinate)
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.purple)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.place.name)
                                    .font(.body.weight(.medium))
                                if let origin {
                                    Text("\(DriveFormatting.shortDistance(fromMeters: result.distance)) \(DriveFormatting.cardinal(fromCourse: PlaceGeometry.bearing(from: origin, to: result.place.coordinate)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let address = result.place.address {
                                    Text(address)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.triangle.turn.up.right.circle")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        } else if isLoading && results.isEmpty {
            Spacer()
            ProgressView("Searching OpenStreetMap…")
            Spacer()
        } else if let errorText {
            Spacer()
            ContentUnavailableView("Couldn't search", systemImage: "wifi.slash", description: Text(errorText))
            Spacer()
        } else if results.isEmpty {
            Spacer()
            ContentUnavailableView(
                "Nothing mapped nearby",
                systemImage: category.systemImage,
                description: Text("No \(category.title.lowercased()) within ~\(Int((category.searchRadius / 1609.344).rounded())) miles in OpenStreetMap.")
            )
            Spacer()
        } else {
            List(results.prefix(40), id: \.place.id) { result in
                Button {
                    openDirections(name: result.place.displayName, to: result.place.coordinate)
                } label: {
                    HStack {
                        Image(systemName: category.systemImage)
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.place.displayName)
                                .font(.body.weight(.medium))
                            HStack(spacing: 6) {
                                if let origin {
                                    Text("\(DriveFormatting.shortDistance(fromMeters: result.distance)) \(DriveFormatting.cardinal(fromCourse: PlaceGeometry.bearing(from: origin, to: result.place.coordinate)))")
                                }
                                if let address = result.place.address {
                                    Text(address).lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.triangle.turn.up.right.circle")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func load(force: Bool = false) async {
        errorText = nil
        isLoading = true
        defer { isLoading = false }

        // Prefer the live drive position; fall back to a one-shot fix.
        let coordinate: Coordinate?
        if let driving = session.context.coordinate {
            coordinate = driving
        } else {
            coordinate = await LocationService.currentFix()
        }
        guard let coordinate else {
            errorText = "Location unavailable. Check location permission in Settings."
            results = []
            return
        }
        origin = coordinate

        do {
            let places = try await service.places(near: coordinate, category: category, forceRefresh: force)
            results = PlaceGeometry.sortedByDistance(places, from: coordinate)
            camera = .automatic // re-frame the map around the fresh pins
        } catch {
            errorText = "OpenStreetMap didn't answer. Try again in a moment."
            results = []
        }
    }
}
