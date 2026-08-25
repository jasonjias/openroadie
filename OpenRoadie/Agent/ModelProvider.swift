import Foundation
import FoundationModels

/// A language model Roadie can think with. The provider owns conversation
/// state; all real-world capability stays in the shared RoadieToolbox, so
/// every provider is grounded by the same deterministic tools.
@MainActor
protocol RoadieModelProvider: AnyObject {
    func respond(to question: String) async throws -> String
}

/// Which model the user chose in Settings.
enum ModelProviderChoice: String, CaseIterable, Identifiable {
    case apple
    case custom

    static let defaultsKey = "modelProvider"
    static let customURLKey = "customModelBaseURL"
    static let customModelKey = "customModelName"
    /// Keychain key — API keys never touch UserDefaults.
    static let customAPIKeyKeychainKey = "customModelAPIKey"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "On-device (Apple)"
        case .custom: "Custom endpoint"
        }
    }

    static var current: ModelProviderChoice {
        ModelProviderChoice(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .apple
    }
}

/// Apple's on-device Foundation Model — the default: private, free, offline.
@MainActor
final class AppleFoundationProvider: RoadieModelProvider {
    private let session: LanguageModelSession

    init(toolbox: RoadieToolbox, instructions: String) {
        let tools: [any Tool] = [
            CurrentDriveTool(toolbox: toolbox),
            FindNearbyTool(toolbox: toolbox),
            RoadLimitTool(toolbox: toolbox),
            SearchPlacesTool(toolbox: toolbox),
            TripHistoryTool(toolbox: toolbox),
            RememberTool(toolbox: toolbox),
            RecallNotesTool(toolbox: toolbox),
            ConfigureAlertsTool(toolbox: toolbox),
        ]
        session = LanguageModelSession(tools: tools, instructions: instructions)
    }

    func respond(to question: String) async throws -> String {
        try await session.respond(to: question).content
    }
}
