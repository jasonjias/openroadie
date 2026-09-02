import ActivityKit
import Foundation
import os

/// Owns the drive's Live Activity: started with the drive, updated as
/// telemetry moves, ended when the drive ends. This is the *deliberate*
/// Dynamic Island presence — a glanceable drive, not a mystery arrow.
@MainActor
final class DriveActivityController {
    /// Settings toggle; on by default (the system has its own per-app
    /// Live Activities switch as well).
    static let enabledKey = "liveActivityEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// ActivityKit's async methods are documented-safe from any context,
    /// but `Activity` itself isn't Sendable — the box carries it across
    /// into fire-and-forget Tasks under Swift 6 without a false positive.
    private struct Box: @unchecked Sendable {
        let value: Activity<DriveActivityAttributes>
    }

    private var activity: Activity<DriveActivityAttributes>?
    private var lastState: DriveActivityAttributes.ContentState?
    private var lastUpdateAt = Date.distantPast
    private let log = Logger(subsystem: "com.openroadie", category: "liveactivity")

    func start(startDate: Date) {
        guard Self.isEnabled, activity == nil,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Any activity left over from a dead incarnation ends first.
        for stale in Activity<DriveActivityAttributes>.activities {
            let box = Box(value: stale)
            Task { await box.value.end(nil, dismissalPolicy: .immediate) }
        }
        let initial = DriveActivityAttributes.ContentState(
            speedMph: nil, distanceMeters: 0, isPaused: false, roadName: nil
        )
        do {
            activity = try Activity.request(
                attributes: DriveActivityAttributes(startDate: startDate),
                content: .init(state: initial, staleDate: nil)
            )
            lastState = initial
            lastUpdateAt = .now
        } catch {
            log.error("live activity refused: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Throttled: the island doesn't need 1 Hz updates, and the system
    /// quietly punishes apps that send them.
    func update(speedMph: Int?, distanceMeters: Double, isPaused: Bool, roadName: String?) {
        guard let activity else { return }
        let state = DriveActivityAttributes.ContentState(
            speedMph: speedMph, distanceMeters: distanceMeters,
            isPaused: isPaused, roadName: roadName
        )
        let significant = lastState.map { previous in
            previous.isPaused != state.isPaused
                || previous.roadName != state.roadName
                || abs((previous.speedMph ?? 0) - (state.speedMph ?? 0)) >= 3
                || abs(previous.distanceMeters - state.distanceMeters) >= 400
        } ?? true
        guard significant, Date.now.timeIntervalSince(lastUpdateAt) >= 5 else { return }
        lastState = state
        lastUpdateAt = .now
        let box = Box(value: activity)
        Task { await box.value.update(.init(state: state, staleDate: nil)) }
    }

    func end(distanceMeters: Double) {
        guard let activity else { return }
        self.activity = nil
        let final = DriveActivityAttributes.ContentState(
            speedMph: nil, distanceMeters: distanceMeters, isPaused: false, roadName: nil
        )
        let box = Box(value: activity)
        Task {
            // Linger briefly on the Lock Screen with the final numbers.
            await box.value.end(
                .init(state: final, staleDate: nil),
                dismissalPolicy: .after(.now + 4 * 60)
            )
        }
    }
}
