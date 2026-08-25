import Foundation

/// BYO model: any OpenAI-compatible chat-completions endpoint — OpenAI,
/// Anthropic's compatibility API, Gemini's compat endpoint, Groq, or a local
/// Ollama server. Runs the same tool loop the on-device model gets, against
/// the same RoadieToolbox, so a cloud model is grounded identically.
///
/// Privacy note (also stated in Settings): choosing a custom endpoint sends
/// your questions and the tool results they trigger to that server.
@MainActor
final class OpenAICompatibleProvider: RoadieModelProvider {
    struct Configuration {
        var baseURL: URL
        var model: String
        var apiKey: String?

        /// nil when the user hasn't filled in enough to work.
        static func fromSettings() -> Configuration? {
            let defaults = UserDefaults.standard
            guard let urlString = defaults.string(forKey: ModelProviderChoice.customURLKey),
                  let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
                  url.scheme?.hasPrefix("http") == true,
                  let model = defaults.string(forKey: ModelProviderChoice.customModelKey)?
                      .trimmingCharacters(in: .whitespaces),
                  !model.isEmpty
            else { return nil }
            return Configuration(
                baseURL: url,
                model: model,
                apiKey: KeychainStore.get(ModelProviderChoice.customAPIKeyKeychainKey)
            )
        }
    }

    enum ProviderError: LocalizedError {
        case badResponse(status: Int, body: String)
        case emptyReply

        var errorDescription: String? {
            switch self {
            case .badResponse(let status, let body):
                "The endpoint answered \(status): \(String(body.prefix(120)))"
            case .emptyReply:
                "The endpoint returned no message."
            }
        }
    }

    private let configuration: Configuration
    private let toolbox: RoadieToolbox
    private var messages: [[String: Any]]
    private static let maxToolRounds = 5

    init(configuration: Configuration, toolbox: RoadieToolbox, instructions: String) {
        self.configuration = configuration
        self.toolbox = toolbox
        messages = [["role": "system", "content": instructions]]
    }

    func respond(to question: String) async throws -> String {
        messages.append(["role": "user", "content": question])

        for _ in 0..<Self.maxToolRounds {
            let reply = try await complete()
            messages.append(reply.rawMessage)

            if reply.toolCalls.isEmpty {
                guard let content = reply.content, !content.isEmpty else {
                    throw ProviderError.emptyReply
                }
                return content
            }
            for call in reply.toolCalls {
                let result = await dispatch(name: call.name, argumentsJSON: call.argumentsJSON)
                messages.append([
                    "role": "tool",
                    "tool_call_id": call.id,
                    "content": result,
                ])
            }
        }
        throw ProviderError.emptyReply
    }

    // MARK: - HTTP

    private func complete() async throws -> ParsedReply {
        let url = configuration.baseURL.appending(path: "chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = configuration.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30
        request.httpBody = try Self.requestBody(
            model: configuration.model,
            messages: messages,
            tools: Self.toolSpecs
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ProviderError.badResponse(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return try Self.parseReply(data)
    }

    // MARK: - Wire format (static and testable)

    struct ParsedReply {
        var content: String?
        var toolCalls: [(id: String, name: String, argumentsJSON: String)]
        var rawMessage: [String: Any]
    }

    static func requestBody(model: String, messages: [[String: Any]], tools: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": messages,
            "tools": tools,
        ] as [String: Any])
    }

    static func parseReply(_ data: Data) throws -> ParsedReply {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = root?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any]
        else { throw ProviderError.emptyReply }

        var calls: [(id: String, name: String, argumentsJSON: String)] = []
        for call in message["tool_calls"] as? [[String: Any]] ?? [] {
            guard let id = call["id"] as? String,
                  let function = call["function"] as? [String: Any],
                  let name = function["name"] as? String
            else { continue }
            calls.append((id, name, function["arguments"] as? String ?? "{}"))
        }
        return ParsedReply(
            content: message["content"] as? String,
            toolCalls: calls,
            rawMessage: message
        )
    }

    // MARK: - Tool dispatch

    private func dispatch(name: String, argumentsJSON: String) async -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)) as? [String: Any]) ?? [:]

        switch name {
        case "currentDrive":
            return toolbox.currentDrive()
        case "findNearby":
            return await toolbox.findNearby(
                category: args["category"] as? String ?? "food",
                brandOrName: args["brandOrName"] as? String
            )
        case "speedLimitFor":
            return await toolbox.speedLimitFor(road: args["road"] as? String ?? "")
        case "searchPlaces":
            return await toolbox.searchPlaces(query: args["query"] as? String ?? "")
        case "tripHistory":
            return toolbox.tripHistory()
        case "rememberNote":
            return await toolbox.remember(note: args["note"] as? String ?? "")
        case "recallNotes":
            return await toolbox.recallNotes(scope: args["scope"] as? String ?? "recent")
        case "controlMusic":
            return await toolbox.controlMusic(
                action: args["action"] as? String ?? "nowplaying",
                query: args["query"] as? String
            )
        case "configureSpeedAlerts":
            return toolbox.configureAlerts(
                alertOverPostedLimit: args["alertOverPostedLimit"] as? Bool,
                extraAlertMphOverLimit: args["extraAlertMphOverLimit"] as? Int,
                maxSpeedMph: args["maxSpeedMph"] as? Int,
                autoEndDriveWhenParked: args["autoEndDriveWhenParked"] as? Bool
            )
        default:
            return "Unknown tool: \(name)"
        }
    }

    /// The same tools the on-device model gets, described in OpenAI function
    /// format.
    static let toolSpecs: [[String: Any]] = [
        functionSpec(
            name: "currentDrive",
            description: "Get the driver's live status: position, speed, heading, current road and its speed limit, and the active trip's elapsed time and distance.",
            properties: [:], required: []
        ),
        functionSpec(
            name: "findNearby",
            description: "Find nearby places by category (food, coffee, gas, charger, supercharger, landmark), optionally filtered by brand or name.",
            properties: [
                "category": ["type": "string", "description": "One of: food, coffee, gas, charger, supercharger, landmark"],
                "brandOrName": ["type": "string", "description": "Optional brand or name filter, like Tesla or Chipotle"],
            ],
            required: ["category"]
        ),
        functionSpec(
            name: "speedLimitFor",
            description: "Get the posted speed limit of a specific named road or highway near the driver.",
            properties: ["road": ["type": "string", "description": "Road name or highway number, e.g. 101, I-280"]],
            required: ["road"]
        ),
        functionSpec(
            name: "searchPlaces",
            description: "Free-text search for any kind of place near the driver (pharmacy, boba, specific business names). Use findNearby for the plain categories.",
            properties: ["query": ["type": "string", "description": "What to search for"]],
            required: ["query"]
        ),
        functionSpec(
            name: "tripHistory",
            description: "Get the driver's recent recorded trips.",
            properties: [:], required: []
        ),
        functionSpec(
            name: "rememberNote",
            description: "Save a note for the driver, pinned to the current location.",
            properties: ["note": ["type": "string", "description": "The note text"]],
            required: ["note"]
        ),
        functionSpec(
            name: "recallNotes",
            description: "Get the driver's saved notes: scope \"here\" for notes near the current spot, \"recent\" for the latest anywhere.",
            properties: ["scope": ["type": "string", "description": "here or recent"]],
            required: ["scope"]
        ),
        functionSpec(
            name: "controlMusic",
            description: "Control the Music app: play, pause, next, previous, nowplaying; play accepts an optional library search query.",
            properties: [
                "action": ["type": "string", "description": "play, pause, next, previous, or nowplaying"],
                "query": ["type": "string", "description": "Optional song/artist/album to search the library for"],
            ],
            required: ["action"]
        ),
        functionSpec(
            name: "configureSpeedAlerts",
            description: "Read or change the driver's speed alert rules; pass only the fields to change, or none to read.",
            properties: [
                "alertOverPostedLimit": ["type": "boolean", "description": "Alert when crossing the posted limit"],
                "extraAlertMphOverLimit": ["type": "integer", "description": "Extra alert this many mph over the limit; 0 disables"],
                "maxSpeedMph": ["type": "integer", "description": "Driver's personal max speed; 0 disables"],
                "autoEndDriveWhenParked": ["type": "boolean", "description": "Auto-end the drive after 10 minutes parked"],
            ],
            required: []
        ),
    ]

    static func functionSpec(name: String, description: String, properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ] as [String: Any],
            ] as [String: Any],
        ]
    }
}
