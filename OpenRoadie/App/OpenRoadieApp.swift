import SwiftUI
import UIKit

@main
struct OpenRoadieApp: App {
    private let store: TripStore
    @State private var session: DriveSessionManager
    @State private var agent: RoadieAgent
    @State private var speaker: SpeechSpeaker
    @State private var wake: WakeWordCoordinator
    @State private var autoDrive: AutoDriveMonitor
    @State private var backgroundWatcher = BackgroundDriveWatcher()

    init() {
        // Fall back to in-memory storage rather than crash if the store can't
        // open — the live dashboard should work even if history can't persist.
        let store = (try? TripStore.persistent()) ?? (try! TripStore.inMemory())
        store.closeDanglingTrips()
        self.store = store
        let session = DriveSessionManager(store: store)
        let agent = RoadieAgent(driveSession: session, store: store)
        let speaker = SpeechSpeaker()
        let wake = WakeWordCoordinator(drive: session, agent: agent, speaker: speaker)
        // Coaching nudges speak through the shared voice pipeline.
        session.speakCoaching = { [weak wake] text in
            wake?.announce(text)
        }
        _session = State(initialValue: session)
        _agent = State(initialValue: agent)
        _speaker = State(initialValue: speaker)
        _wake = State(initialValue: wake)
        _autoDrive = State(initialValue: AutoDriveMonitor(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView(session: session, agent: agent, speaker: speaker, wake: wake, autoDrive: autoDrive)
                .modelContainer(store.container)
                .task {
                    // Arm detection FIRST. On a background relaunch this
                    // closure is the whole reason we woke up, and the window
                    // before iOS suspends us is measured in seconds — the
                    // janitor's 8-second cleanup must never come first.
                    let launchedInBackground = UIApplication.shared.applicationState == .background
                    backgroundWatcher.refresh { [weak session] coordinate, accuracy in
                        // A wake means the app is alive again — start the
                        // continuous spine, which drops breadcrumbs and
                        // promotes itself to a drive on road speed. No more
                        // fragile probe handoff.
                        if let coordinate, accuracy >= 0, session?.isDriving != true {
                            store.saveCrumb(coordinate, accuracy: accuracy)
                        }
                        session?.ensureContinuousRecording()
                    }
                    // Start the spine on this launch too (foreground or a
                    // background relaunch).
                    session.ensureContinuousRecording()
                    // Everything below is housekeeping — skipped entirely
                    // on a background wake, where the only job is catching
                    // the drive.
                    guard !launchedInBackground else { return }
                    // Conclude sessions preserved from an incarnation that
                    // died holding them (one liveUpdates stream per process,
                    // so this must not race a drive's).
                    await LocationSessionJanitor.reconcileIfNeeded(isDriving: session.isDriving)
                    store.pruneCrumbs(olderThan: .now.addingTimeInterval(-8 * 86_400))
                    // Old trips gain weather a few at a time (Open-Meteo's
                    // archive), newest first. No-op once caught up.
                    await WeatherBackfill.run(store: store)
                }
        }
    }
}
