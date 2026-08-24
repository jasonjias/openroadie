import CoreLocation
import Foundation
import Observation

/// Owns the drive session lifecycle: Start Drive → consume GPS updates →
/// keep `DrivingContext` current → Stop Drive.
///
/// This is the single object the UI observes. It glues `LocationService`
/// (where fixes come from) to `TripTracker` (what they mean) without either
/// knowing about the other.
@MainActor
@Observable
final class DriveSessionManager {
    enum AuthorizationState {
        case unknown
        case requesting
        case authorized
        case denied
    }

    private(set) var context = DrivingContext()
    private(set) var isDriving = false
    private(set) var authorization: AuthorizationState = .unknown
    /// True when iOS reports the device hasn't moved meaningfully.
    private(set) var isStationary = false
    private(set) var lastErrorDescription: String?

    private let locationService = LocationService()
    private var tracker = TripTracker()
    private var updatesTask: Task<Void, Never>?

    func startDrive() {
        guard !isDriving else { return }
        lastErrorDescription = nil
        isStationary = false
        tracker.start()
        context = tracker.context
        isDriving = true
        locationService.begin()

        updatesTask = Task { [weak self] in
            guard let service = self?.locationService else { return }
            do {
                for try await update in service.updates() {
                    guard let self, self.isDriving else { break }
                    self.handle(update)
                }
            } catch {
                guard let self, self.isDriving else { return }
                self.lastErrorDescription = error.localizedDescription
                self.stopDrive()
            }
        }
    }

    func stopDrive() {
        guard isDriving else { return }
        isDriving = false
        updatesTask?.cancel()
        updatesTask = nil
        locationService.end()
        tracker.stop()
        context = tracker.context
    }

    private func handle(_ update: CLLocationUpdate) {
        if update.authorizationRequestInProgress {
            authorization = .requesting
        }
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            authorization = .denied
            return
        }

        isStationary = update.stationary

        if let location = update.location {
            authorization = .authorized
            tracker.process(LocationSample(location))
            context = tracker.context
        }
    }
}
