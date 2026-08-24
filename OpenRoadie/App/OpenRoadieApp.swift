import SwiftUI

@main
struct OpenRoadieApp: App {
    private let store: TripStore
    @State private var session: DriveSessionManager
    @State private var agent: RoadieAgent
    @State private var speaker: SpeechSpeaker
    @State private var wake: WakeWordCoordinator

    init() {
        // Fall back to in-memory storage rather than crash if the store can't
        // open — the live dashboard should work even if history can't persist.
        let store = (try? TripStore.persistent()) ?? (try! TripStore.inMemory())
        store.closeDanglingTrips()
        self.store = store
        let session = DriveSessionManager(store: store)
        let agent = RoadieAgent(driveSession: session, store: store)
        let speaker = SpeechSpeaker()
        _session = State(initialValue: session)
        _agent = State(initialValue: agent)
        _speaker = State(initialValue: speaker)
        _wake = State(initialValue: WakeWordCoordinator(drive: session, agent: agent, speaker: speaker))
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, agent: agent, speaker: speaker, wake: wake)
                .modelContainer(store.container)
        }
    }
}
