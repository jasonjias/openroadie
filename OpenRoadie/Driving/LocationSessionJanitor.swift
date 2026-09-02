import CoreLocation
import Foundation
import os

/// Concludes CoreLocation sessions left over from a dead incarnation.
///
/// The modern CoreLocation API *preserves* sessions that are in flight when
/// an app terminates: the location pill stays in the Dynamic Island and the
/// system waits for the app to come back and resume them. That's the right
/// behavior for a navigation app killed mid-route — and exactly wrong for
/// us, because OpenRoadie never resumes a dead incarnation's drive
/// (`closeDanglingTrips` closes it in storage instead). Field symptom: swipe
/// the app away during a drive or a detection probe and the tappable
/// location arrow lives on indefinitely, relaunching the app on tap.
///
/// The remedy is Apple's own: recreate the equivalent sessions and end them
/// — invalidate the session objects, and briefly resume the update stream
/// then break out, which tells CoreLocation the stream is finished.
@MainActor
enum LocationSessionJanitor {
    /// Set while this process holds live location sessions (a drive or a
    /// detection probe). Still `true` at launch = the last incarnation died
    /// holding sessions, and the system may be preserving them.
    static let sessionsOpenKey = "clLiveSessionsOpen"

    private static let log = Logger(subsystem: "com.openroadie", category: "janitor")

    /// CoreLocation supports ONE liveUpdates stream per process. The
    /// janitor's conclude-the-preserved-stream consume must never coexist
    /// with the drive's or the detection probe's own stream — a second
    /// stream opening and closing can starve the first. Field cost of
    /// getting this wrong: a 15-mile drive that persisted two route points.
    private(set) static var locationActiveThisProcess = false
    private static var consumeTask: Task<Void, Never>?

    static func markSessionsOpen() {
        locationActiveThisProcess = true
        // Real location work trumps cleanup: a consume in flight ends now.
        consumeTask?.cancel()
        UserDefaults.standard.set(true, forKey: sessionsOpenKey)
    }

    static func markSessionsClosed() {
        UserDefaults.standard.set(false, forKey: sessionsOpenKey)
    }

    /// Pure decision, unit-tested: reconcile when the last incarnation died
    /// holding sessions — or when the flag has never been written (an
    /// upgrade from a build that didn't track it, which is exactly the
    /// population with pills already stuck). Never while a drive is live,
    /// and never when it would trigger a permission prompt.
    nonisolated static func shouldReconcile(flag: Bool?, isDriving: Bool, authorizationDetermined: Bool) -> Bool {
        guard !isDriving, authorizationDetermined else { return false }
        return flag ?? true
    }

    /// Call once at launch, BEFORE drive detection arms — the caller
    /// sequences this so nothing else can be opening location streams yet.
    static func reconcileIfNeeded(isDriving: Bool) async {
        let flag = UserDefaults.standard.object(forKey: sessionsOpenKey) as? Bool
        let determined = CLLocationManager().authorizationStatus != .notDetermined
        guard shouldReconcile(flag: flag, isDriving: isDriving, authorizationDetermined: determined) else { return }
        log.info("reconciling possibly-preserved location sessions")

        // Claim and end any preserved sessions of both kinds.
        CLServiceSession(authorization: .whenInUse).invalidate()
        CLBackgroundActivitySession().invalidate()

        // A preserved liveUpdates stream ends only when the relaunched app
        // resumes consuming it and then stops — one update (or a short
        // timeout, for indoors-with-no-fix) is enough to conclude it. Only
        // safe while this process runs no stream of its own, and it yields
        // instantly if one starts.
        guard !locationActiveThisProcess else {
            // The live stream supersedes the preserved one anyway.
            markSessionsClosed()
            return
        }
        let consume = Task {
            do {
                for try await _ in CLLocationUpdate.liveUpdates() { break }
            } catch {
                // Cancelled or unavailable — either way there is nothing
                // left to conclude.
            }
        }
        consumeTask = consume
        Task {
            try? await Task.sleep(for: .seconds(8))
            consume.cancel()
        }
        _ = await consume.result
        consumeTask = nil

        // A drive may have begun mid-consume; only its own end may clear
        // the flag then.
        if !locationActiveThisProcess {
            markSessionsClosed()
        }
        log.info("location session reconciliation complete")
    }
}
