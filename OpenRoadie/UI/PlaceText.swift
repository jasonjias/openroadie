import SwiftUI

/// Async place name for a coordinate — renders nothing until (unless) the
/// geocoder answers, so layouts never wait on the network.
struct PlaceText: View {
    let coordinate: Coordinate
    var prefix: String = ""

    @State private var name: String?

    var body: some View {
        if let name {
            Text("\(prefix)\(name)")
        } else {
            // Zero-size placeholder; appears in place when resolved.
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: PlaceNamer.cacheKey(for: coordinate)) {
                    name = await PlaceNamer.shared.name(for: coordinate)
                }
        }
    }
}
