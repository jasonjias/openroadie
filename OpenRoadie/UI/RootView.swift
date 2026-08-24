import SwiftUI

struct RootView: View {
    let session: DriveSessionManager
    let agent: RoadieAgent
    let speaker: SpeechSpeaker
    let wake: WakeWordCoordinator

    @AppStorage(WakeWordCoordinator.enabledKey) private var heyRoadieEnabled = false

    var body: some View {
        TabView {
            Tab("Drive", systemImage: "car.fill") {
                DashboardView(session: session, wake: wake)
            }
            Tab("Roadie", systemImage: "sparkles") {
                AskView(agent: agent, speaker: speaker, wake: wake)
            }
            Tab("Nearby", systemImage: "mappin.and.ellipse") {
                NearbyView(session: session)
            }
            Tab("Trips", systemImage: "map") {
                TripsListView()
            }
        }
        .task { wake.refresh() }
        .onChange(of: session.isDriving) { _, _ in wake.refresh() }
        .onChange(of: heyRoadieEnabled) { _, _ in wake.refresh() }
    }
}
