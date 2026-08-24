import SwiftUI

struct RootView: View {
    let session: DriveSessionManager
    let agent: RoadieAgent

    var body: some View {
        TabView {
            Tab("Drive", systemImage: "car.fill") {
                DashboardView(session: session)
            }
            Tab("Roadie", systemImage: "sparkles") {
                AskView(agent: agent)
            }
            Tab("Nearby", systemImage: "mappin.and.ellipse") {
                NearbyView(session: session)
            }
            Tab("Trips", systemImage: "map") {
                TripsListView()
            }
        }
    }
}
