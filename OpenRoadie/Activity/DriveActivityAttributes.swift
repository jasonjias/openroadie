import ActivityKit
import Foundation

/// The live drive as the system sees it — Lock Screen banner and Dynamic
/// Island. Compiled into both the app (which starts and feeds it) and the
/// widget extension (which renders it), so it stays framework-free beyond
/// ActivityKit itself.
struct DriveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Current speed, rounded; nil while GPS doesn't know.
        var speedMph: Int?
        /// Trip distance so far, meters.
        var distanceMeters: Double
        /// True while the drive is paused at a stop.
        var isPaused: Bool
        /// Road being driven, when road awareness knows it.
        var roadName: String?
    }

    /// When the drive began — the island runs its timer off this.
    var startDate: Date
}
