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
    /// if it hasn't been granted yet. Must be called while the app is in the
    /// foreground — which Start Drive guarantees.
    func begin() {
        guard serviceSession == nil else { return }
        backgroundActivity = CLBackgroundActivitySession()
        serviceSession = CLServiceSession(authorization: .whenInUse)
    }

    func end() {
        serviceSession?.invalidate()
        serviceSession = nil
        backgroundActivity?.invalidate()
        backgroundActivity = nil
    }

    /// Live GPS updates tuned for driving. The stream also carries diagnostic
    /// flags (authorization denied, updates paused, and so on).
    nonisolated func updates() -> CLLocationUpdate.Updates {
        CLLocationUpdate.liveUpdates(.automotiveNavigation)
    }
}
