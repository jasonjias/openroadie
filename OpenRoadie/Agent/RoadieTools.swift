import Foundation
import FoundationModels

/// The agent's window into live telemetry. Reads `DrivingContext` — it can
/// only ever report what the deterministic layer actually knows.
struct CurrentDriveTool: Tool {
    let name = "currentDrive"
    let description = """
    Get the driver's live status: position, speed, heading, current road and \
    its speed limit, and the active trip's elapsed time and distance.
    """

    private let session: DriveSessionManager

    init(session: DriveSessionManager) {
        self.session = session
    }

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let text = await MainActor.run {
            RoadieToolFormatting.describeDrive(session.context, isDriving: session.isDriving)
        }
        return text
    }
}

/// Nearby search over OpenStreetMap, reusing the same PlaceService the
/// Nearby tab uses.
struct FindNearbyTool: Tool {
    let name = "findNearby"
    let description = """
    Find nearby places by category. Valid categories: food, coffee, gas, \
    charger, landmark. Optionally filter by a brand or name like "Tesla", \
    "Chipotle", or "Shell". Returns the closest matches with distance and \
    compass direction from the driver.
    """

    private let session: DriveSessionManager
    private let places: PlaceService

    init(session: DriveSessionManager, places: PlaceService) {
        self.session = session
        self.places = places
    }

    @Generable
    struct Arguments {
        @Guide(description: "One of: food, coffee, gas, charger, landmark")
        var category: String

        @Guide(description: "Optional brand or place name to filter by, like Tesla, Chipotle, or Starbucks. Omit to get everything.")
        var brandOrName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let category = PlaceCategory(rawValue: arguments.category.lowercased()) ?? .food

        var origin = await MainActor.run { session.context.coordinate }
        if origin == nil {
            origin = await LocationService.currentFix()
        }
        guard let origin else {
            return "The driver's location is unavailable right now."
        }

        do {
            let found = try await places.places(near: origin, category: category)
            let sorted = PlaceGeometry.sortedByDistance(found, from: origin)

            if let keyword = arguments.brandOrName?.trimmingCharacters(in: .whitespaces), !keyword.isEmpty {
                let matching = sorted.filter { $0.place.matches(keyword: keyword) }
                if matching.isEmpty {
                    // Honest miss, but still useful: offer what IS around.
                    return "No \(category.singular) matching \"\(keyword)\" nearby. "
                        + RoadieToolFormatting.describePlaces(sorted, category: category, origin: origin)
                }
                return RoadieToolFormatting.describePlaces(matching, category: category, origin: origin)
            }
            return RoadieToolFormatting.describePlaces(sorted, category: category, origin: origin)
        } catch {
            return "The place search didn't respond — possibly offline. Suggest trying again."
        }
    }
}

/// The agent's view of local trip history.
struct TripHistoryTool: Tool {
    let name = "tripHistory"
    let description = """
    Get the driver's recent recorded trips: when each happened, distance, \
    duration, and top speed.
    """

    private let store: TripStore

    init(store: TripStore) {
        self.store = store
    }

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        // Trips are SwiftData models; read and render them on the main actor.
        let text = await MainActor.run {
            RoadieToolFormatting.describeTrips(store.recentTrips(limit: 5))
        }
        return text
    }
}
