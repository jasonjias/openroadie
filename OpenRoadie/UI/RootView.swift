import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
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
            // The Roadie chat tab is retired — a text UI invites texting
            // while driving. The agent lives on behind "Hey Roadie"; its
            // AskView is kept in the codebase for a future, better home.
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
        // Backgrounding releases the mic (and with it the system-wide
        // volume dip) unless a drive is actually recording.
        .onChange(of: scenePhase) { _, phase in
            wake.setAppActive(phase == .active)
        }
        .onChange(of: modelProvider) { _, _ in agent.reconfigure() }
        .onChange(of: customModelURL) { _, _ in agent.reconfigure() }
        .onChange(of: customModelName) { _, _ in agent.reconfigure() }
    }
}
