import CoreLocation

/// Thin wrapper around CoreLocation's modern session-based APIs.
///
/// This class owns the objects that express intent to the OS:
/// - `CLServiceSession` holds the When-In-Use authorization for the duration
///   of a drive and triggers the permission prompt when needed.
/// - `CLBackgroundActivitySession` tells iOS the user is actively using
///   location, which keeps updates flowing (with the status-bar indicator)
///   while another app is foregrounded or the phone is locked.
///
/// Interpretation of the resulting fixes lives in `TripTracker`; this class
/// knows nothing about trips, and nothing above it touches CoreLocation
/// session objects.
@MainActor
final class LocationService {
    private var serviceSession: CLServiceSession?
    private var backgroundActivity: CLBackgroundActivitySession?

    var isRunning: Bool { serviceSession != nil }

    /// Expresses intent to use location, prompting for When-In-Use permission
    /// if it hasn't been granted yet.
    func begin() {
        guard serviceSession == nil else { return }
        backgroundActivity = CLBackgroundActivitySession()
        // Always when granted. A drive the detector starts from a background
        // wake-up has no foreground to borrow When-In-Use from, and a
        // when-in-use session created there yields no fixes at all — the
        // field symptom was an auto-started drive that recorded nothing and
        // was then discarded for having under two points.
        serviceSession = CLLocationManager().authorizationStatus == .authorizedAlways
            ? CLServiceSession(authorization: .always)
            : CLServiceSession(authorization: .whenInUse)
        // If this process dies before end(), the flag survives it and the
        // next launch concludes whatever the system preserved.
        LocationSessionJanitor.markSessionsOpen()
    }

    func end() {
        serviceSession?.invalidate()
        serviceSession = nil
        backgroundActivity?.invalidate()
        backgroundActivity = nil
        LocationSessionJanitor.markSessionsClosed()
    }

    /// Live GPS updates tuned for driving. The stream also carries diagnostic
    /// flags (authorization denied, updates paused, and so on).
    nonisolated func updates() -> CLLocationUpdate.Updates {
        CLLocationUpdate.liveUpdates(.automotiveNavigation)
    }

    /// One-shot position fix for features used while parked (e.g. Nearby).
    /// Prompts for When-In-Use permission if needed; `nil` when denied or
    /// no fix arrives promptly.
    static func currentFix() async -> Coordinate? {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        var attempts = 0
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    return Coordinate(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    )
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
                attempts += 1
                if attempts > 15 { return nil }
            }
        } catch {
            return nil
        }
        return nil
    }
}
