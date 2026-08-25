import Foundation
import FoundationModels

// FoundationModels-facing tool wrappers. All real capability lives in
// RoadieToolbox, which remote model providers share.

/// The agent's window into live telemetry.
struct CurrentDriveTool: Tool {
    let name = "currentDrive"
    let description = """
    Get the driver's live status: position, speed, heading, current road and \
    its speed limit, and the active trip's elapsed time and distance.
    """

    private let toolbox: RoadieToolbox

    init(toolbox: RoadieToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await toolbox.currentDrive()
    }
}

/// Nearby search over OpenStreetMap by category, optionally brand-filtered.
struct FindNearbyTool: Tool {
    let name = "findNearby"
    let description = """
    Find nearby places by category. Valid categories: food, coffee, gas, \
    charger, landmark. Optionally filter by a brand or name like "Tesla", \
    "Chipotle", or "Shell". Returns the closest matches with distance and \
    compass direction from the driver.
    """

    private let toolbox: RoadieToolbox

    init(toolbox: RoadieToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        @Guide(description: "One of: food, coffee, gas, charger, landmark")
        var category: String

        @Guide(description: "Optional brand or place name to filter by, like Tesla, Chipotle, or Starbucks. Omit to get everything.")
        var brandOrName: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.findNearby(category: arguments.category, brandOrName: arguments.brandOrName)
    }
}

/// Speed limit of a NAMED road near the driver ("what's the limit on 101?").
struct RoadLimitTool: Tool {
    let name = "speedLimitFor"
    let description = """
    Get the posted speed limit of a specific named road or highway near the \
    driver, like "101", "I-280", or "El Camino Real". For the road the driver \
    is currently on, use currentDrive instead.
    """

    private let toolbox: RoadieToolbox

    init(toolbox: RoadieToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        @Guide(description: "The road name or highway number, e.g. 101, I-280, El Camino Real")
        var road: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.speedLimitFor(road: arguments.road)
    }

    /// "I-280" → "280", "US 101" → "101"; names pass through. OSM refs are
    /// written like "I 280"/"US 101", so the bare number matches best.
    static func searchTerm(from input: String) -> String {
        let digits = input.filter(\.isNumber)
        if !digits.isEmpty, digits.count >= 1, input.count <= digits.count + 5 {
            return digits
        }
        return input.trimmingCharacters(in: .whitespaces)
    }
}

/// Free-text search for anything the fixed categories don't cover.
struct SearchPlacesTool: Tool {
    let name = "searchPlaces"
    let description = """
    Search for any kind of place near the driver by free text — pharmacies, \
    boba, ATMs, car washes, parks, specific business names. Use findNearby \
    instead for the plain categories food, coffee, gas, charger, landmark.
    """

    private let toolbox: RoadieToolbox

    init(toolbox: RoadieToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        @Guide(description: "What to search for, e.g. pharmacy, boba, Trader Joe's")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.searchPlaces(query: arguments.query)
    }
}

/// Driving memory: save a geo-anchored note for the driver.
struct RememberTool: Tool {
    let name = "rememberNote"
    let description = """
    Save a note for the driver, pinned to the current location — a spot to \
    come back to, an idea they had, something they saw. Use when the driver \
    says things like "remember this spot" or "note that down".
    """

    private let toolbox: RoadieToolbox

    init(toolbox: RoadieToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        @Guide(description: "The note text to save, in the driver's words")
        var note: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.remember(note: arguments.note)
    }
}

/// Driving memory: recall saved notes, nearby or recent.
struct RecallNotesTool: Tool {
    let name = "recallNotes"
    let description = """
    Get the driver's saved notes. Scope "here" returns notes pinned within \
    about a kilometer of the current position; scope "recent" returns the \
    latest notes anywhere.
    """

    private let toolbox: RoadieToolbox

    init(toolbox: RoadieToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {
        @Guide(description: "Either \"here\" (notes near the current spot) or \"recent\" (latest notes)")
        var scope: String
    }

    func call(arguments: Arguments) async throws -> String {
        await toolbox.recallNotes(scope: arguments.scope)
    }
}

/// The agent's view of local trip history.
struct TripHistoryTool: Tool {
    let name = "tripHistory"
    let description = """
    Get the driver's recent recorded trips: when each happened, distance, \
    duration, and top speed.
    """

    private let toolbox: RoadieToolbox

    init(toolbox: RoadieToolbox) {
        self.toolbox = toolbox
    }

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await toolbox.tripHistory()
    }
}
