import SwiftUI

struct RootView: View {
    let session: DriveSessionManager
    let agent: RoadieAgent
    let speaker: SpeechSpeaker
    let wake: WakeWordCoordinator

    @AppStorage(WakeWordCoordinator.modeKey) private var heyRoadieMode = WakeWordCoordinator.Mode.off.rawValue

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
        .onChange(of: heyRoadieMode) { _, _ in wake.refresh() }
    }
}
