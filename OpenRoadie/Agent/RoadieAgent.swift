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

    private let toolbox: RoadieToolbox
    private var provider: (any RoadieModelProvider)?
    private var providerChoice: ModelProviderChoice = .apple

    init(driveSession: DriveSessionManager, store: TripStore?) {
        toolbox = RoadieToolbox(drive: driveSession, store: store)
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
    - Any other kind of place — pharmacies, boba, ATMs, parks, or a specific \
    business name: call searchPlaces with the query, then name the results.
    - Questions about past drives: call tripHistory.
    - "Remember this spot", "note that down", "remember that idea": call \
    rememberNote with the note text. "What did I note here / what were my \
    notes": call recallNotes with scope "here" or "recent".
    - Requests to create, change, or check speed alerts ("warn me if I go 10 \
    over", "never let me go over 80", "turn off my speed alerts", "what are \
    my alerts?"): call configureSpeedAlerts with ONLY the fields being \
    changed, then confirm the resulting settings back. "Never let me go over \
    X" means maxSpeedMph = X. You cannot create other kinds of rules yet — \
    say so honestly if asked.

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

    /// Prepares the selected model provider. Safe to call repeatedly (e.g.
    /// re-check after the on-device model finishes downloading).
    func start() {
        providerChoice = ModelProviderChoice.current
        switch providerChoice {
        case .apple:
            switch SystemLanguageModel.default.availability {
            case .available:
                if provider == nil || !(provider is AppleFoundationProvider) {
                    provider = AppleFoundationProvider(toolbox: toolbox, instructions: Self.instructions)
                }
                state = .ready
            case .unavailable(let reason):
                provider = nil
                state = .unavailable(Self.explanation(for: reason))
            }
        case .custom:
            if let configuration = OpenAICompatibleProvider.Configuration.fromSettings() {
                if provider == nil || !(provider is OpenAICompatibleProvider) {
                    provider = OpenAICompatibleProvider(
                        configuration: configuration,
                        toolbox: toolbox,
                        instructions: Self.instructions
                    )
                }
                state = .ready
            } else {
                provider = nil
                state = .unavailable("Set the custom endpoint's URL and model name in Settings first.")
            }
        }
    }

    /// The model choice changed in Settings: rebuild from scratch.
    func reconfigure() {
        provider = nil
        state = .checking
        start()
    }

    /// Asks Roadie a question; returns the reply so callers can also speak it.
    @discardableResult
    func ask(_ question: String) async -> String? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let provider, !trimmed.isEmpty, !isThinking else { return nil }

        messages.append(Message(role: .user, text: trimmed))
        isThinking = true
        defer { isThinking = false }

        do {
            let response = try await provider.respond(to: trimmed)
            messages.append(Message(role: .roadie, text: response))
            return response
        } catch {
            // Most failures are cured by a fresh session; keep the app
            // usable and say honestly what happened.
            Logger(subsystem: "com.openroadie", category: "agent")
                .error("Roadie respond failed: \(String(describing: error), privacy: .public)")
            self.provider = nil
            start()
            let explanation = Self.explanation(for: error)
            messages.append(Message(role: .roadie, text: explanation))
            return explanation
        }
    }

    private static func explanation(for error: any Error) -> String {
        if let providerError = error as? OpenAICompatibleProvider.ProviderError {
            return "The custom model endpoint failed: \(providerError.localizedDescription)"
        }
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
