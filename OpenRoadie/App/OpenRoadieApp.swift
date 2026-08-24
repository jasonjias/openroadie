import SwiftUI

@main
struct OpenRoadieApp: App {
    @State private var session = DriveSessionManager()

    var body: some Scene {
        WindowGroup {
            DashboardView(session: session)
        }
    }
}
