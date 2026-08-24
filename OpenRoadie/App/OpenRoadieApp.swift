import SwiftUI

@main
struct OpenRoadieApp: App {
    private let store: TripStore
    @State private var session: DriveSessionManager

    init() {
        // Fall back to in-memory storage rather than crash if the store can't
        // open — the live dashboard should work even if history can't persist.
        let store = (try? TripStore.persistent()) ?? (try! TripStore.inMemory())
        store.closeDanglingTrips()
        self.store = store
        _session = State(initialValue: DriveSessionManager(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .modelContainer(store.container)
        }
    }
}
