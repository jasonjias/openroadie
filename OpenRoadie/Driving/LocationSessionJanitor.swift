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
enum LocationSessionJanitor {
    /// Set while this process holds live location sessions (a drive or a
    /// detection probe). Still `true` at launch = the last incarnation died
    /// holding sessions, and the system may be preserving them.
    static let sessionsOpenKey = "clLiveSessionsOpen"

    private static let log = Logger(subsystem: "com.openroadie", category: "janitor")

    static func markSessionsOpen() {
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
    static func shouldReconcile(flag: Bool?, isDriving: Bool, authorizationDetermined: Bool) -> Bool {
        guard !isDriving, authorizationDetermined else { return false }
        return flag ?? true
    }

    /// Call once at launch, after the drive session had its chance to start.
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
        // timeout, for indoors-with-no-fix) is enough to conclude it.
        let consume = Task {
            do {
                for try await _ in CLLocationUpdate.liveUpdates() { break }
            } catch {
                // Cancelled or unavailable — either way there is nothing
                // left to conclude.
            }
        }
        Task {
            try? await Task.sleep(for: .seconds(8))
            consume.cancel()
        }
        _ = await consume.result

        markSessionsClosed()
        log.info("location session reconciliation complete")
    }
}
