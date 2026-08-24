import SwiftUI

@main
struct OpenRoadieApp: App {
    private let store: TripStore
    @State private var session: DriveSessionManager
    @State private var agent: RoadieAgent

    init() {
        // Fall back to in-memory storage rather than crash if the store can't
        // open — the live dashboard should work even if history can't persist.
        let store = (try? TripStore.persistent()) ?? (try! TripStore.inMemory())
        store.closeDanglingTrips()
        self.store = store
        let session = DriveSessionManager(store: store)
        _session = State(initialValue: session)
        _agent = State(initialValue: RoadieAgent(driveSession: session, store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, agent: agent)
                .modelContainer(store.container)
        }
    }
}
