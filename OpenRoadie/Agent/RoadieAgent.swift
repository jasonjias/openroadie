import Foundation
import FoundationModels
import Observation
import os

/// Roadie: the conversational layer over everything OpenRoadie knows.
///
/// Runs entirely on Apple's on-device Foundation Model — no cloud, no key,
/// no data leaving the phone. Deterministic layers (telemetry, roads, places,
/// history) stay authoritative: the model answers by calling their tools,
/// never by guessing.
@MainActor
@Observable
final class RoadieAgent {
    struct Message: Identifiable, Equatable {
        enum Role {
            case user
            case roadie
        }

        let id = UUID()
        var role: Role
        var text: String
    }

    enum State: Equatable {
        case checking
        case ready
        case unavailable(String)
    }

    private(set) var state: State = .checking
    private(set) var messages: [Message] = []
    private(set) var isThinking = false

    private let driveSession: DriveSessionManager
    private let store: TripStore?
    private let placeService = PlaceService()
    private var session: LanguageModelSession?

    init(driveSession: DriveSessionManager, store: TripStore?) {
        self.driveSession = driveSession
        self.store = store
    }

    static let instructions = """
    You are Roadie, the driving copilot inside OpenRoadie. You answer by \
    calling tools — never from memory, because the drive changes constantly.

    Rules for tools:
    - Any question about speed, location, position, road, speed limit, \
    heading, or the current trip: ALWAYS call currentDrive first, even if \
    you answered recently.
    - Any question about food, restaurants, coffee, gas, chargers, or \
    landmarks: ALWAYS call findNearby, then repeat the place names to the \
    user. Example good answer: "Closest food: Chipotle 0.2 mi NW, Sweetgreen \
    0.3 mi N, Osteria 0.4 mi E." A count alone, like "there are 5 \
    restaurants", is a useless answer — always give names. If the user names \
    a brand or place ("Tesla charger", "Chipotle"), pass it as brandOrName.
    - Questions about the speed limit of a SPECIFIC named road or highway \
    ("what's the limit on 101?"): call speedLimitFor with that road name.
    - Questions about past drives: call tripHistory.

    Style: short and glanceable, one to three plain sentences. No markdown, \
    no emoji. US units (mph, miles, feet). If a tool says something is \
    unknown, say so plainly. Never invent roads, places, or numbers. \
    Tools are your ONLY source of facts about the world. You do not know \
    addresses, opening hours, or anything about a place beyond what \
    findNearby returned — if asked for a detail the tool didn't provide, \
    say you don't have it. Inventing an address or place is the worst \
    possible failure. You cannot control the vehicle or navigation; you \
    only inform.
    """

    /// Checks on-device model availability and prepares a session. Safe to
    /// call repeatedly (e.g. re-check after the model finishes downloading).
    func start() {
        switch SystemLanguageModel.default.availability {
        case .available:
            if session == nil { resetSession() }
            state = .ready
        case .unavailable(let reason):
            state = .unavailable(Self.explanation(for: reason))
        }
    }

    /// Asks Roadie a question; returns the reply so callers can also speak it.
    @discardableResult
    func ask(_ question: String) async -> String? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let session, !trimmed.isEmpty, !isThinking else { return nil }

        messages.append(Message(role: .user, text: trimmed))
        isThinking = true
        defer { isThinking = false }

        do {
            let response = try await session.respond(to: trimmed)
            messages.append(Message(role: .roadie, text: response.content))
            return response.content
        } catch {
            // Most failures are cured by a fresh session; keep the app
            // usable and say honestly what happened.
            Logger(subsystem: "com.openroadie", category: "agent")
                .error("Roadie respond failed: \(String(describing: error), privacy: .public)")
            resetSession()
            let explanation = Self.explanation(for: error)
            messages.append(Message(role: .roadie, text: explanation))
            return explanation
        }
    }

    private func resetSession() {
        var tools: [any Tool] = [
            CurrentDriveTool(session: driveSession),
            FindNearbyTool(session: driveSession, places: placeService),
            RoadLimitTool(session: driveSession),
        ]
        if let store {
            tools.append(TripHistoryTool(store: store))
        }
        session = LanguageModelSession(tools: tools, instructions: Self.instructions)
    }

    private static func explanation(for error: any Error) -> String {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return "Something went wrong answering that. Try again."
        }
        switch generationError {
        case .exceededContextWindowSize:
            return "That conversation got too long for me — I've started fresh. Ask again."
        case .guardrailViolation:
            return "I can't help with that one while you're on the road."
        case .assetsUnavailable:
            return "Parts of the on-device model aren't available in this environment. On an iPhone with Apple Intelligence enabled this should work."
        case .rateLimited:
            return "I'm being asked too much too fast. Give me a moment and try again."
        case .concurrentRequests:
            return "One question at a time — I'm still working on the last one."
        default:
            return "I hit a snag answering that. Ask me again in a fresh way."
        }
    }

    private static func explanation(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This device doesn't support Apple Intelligence, which Roadie's on-device model needs."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri, then come back."
        case .modelNotReady:
            "The on-device model is still getting ready — it downloads in the background. Try again shortly."
        @unknown default:
            "The on-device model isn't available right now."
        }
    }
}
