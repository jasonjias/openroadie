import SwiftUI

struct RootView: View {
    let session: DriveSessionManager
    let agent: RoadieAgent
    let speaker: SpeechSpeaker
    let wake: WakeWordCoordinator
    let autoDrive: AutoDriveMonitor

    @AppStorage(WakeWordCoordinator.modeKey) private var heyRoadieMode = WakeWordCoordinator.Mode.off.rawValue
    @AppStorage(ModelProviderChoice.defaultsKey) private var modelProvider = ModelProviderChoice.apple.rawValue
    @AppStorage(ModelProviderChoice.customURLKey) private var customModelURL = ""
    @AppStorage(ModelProviderChoice.customModelKey) private var customModelName = ""

    var body: some View {
        TabView {
            Tab("Drive", systemImage: "car.fill") {
                DashboardView(session: session, wake: wake)
            }
            Tab("Roadie", systemImage: "sparkles") {
                AskView(agent: agent, speaker: speaker, wake: wake, drive: session)
            }
            Tab("Nearby", systemImage: "mappin.and.ellipse") {
                NearbyView(session: session)
            }
            Tab("Trips", systemImage: "map") {
                TripsListView()
            }
        }
        .task {
            wake.refresh()
            autoDrive.refresh()
            autoDrive.checkRecentActivity()
        }
        .onChange(of: session.isDriving) { _, _ in
            wake.refresh()
            autoDrive.refresh()
        }
        .onChange(of: heyRoadieMode) { _, _ in wake.refresh() }
        .onChange(of: modelProvider) { _, _ in agent.reconfigure() }
        .onChange(of: customModelURL) { _, _ in agent.reconfigure() }
        .onChange(of: customModelName) { _, _ in agent.reconfigure() }
    }
}
