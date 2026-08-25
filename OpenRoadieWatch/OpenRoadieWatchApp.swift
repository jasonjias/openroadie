import SwiftUI

@main
struct OpenRoadieWatchApp: App {
    @State private var model = WatchSessionModel()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView(model: model)
        }
    }
}
