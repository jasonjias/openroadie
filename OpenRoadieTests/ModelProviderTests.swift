import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct OpenAIWireFormatTests {
    @Test func parsesPlainReply() throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"You're going 65 mph."}}]}
        """
        let reply = try OpenAICompatibleProvider.parseReply(Data(json.utf8))
        #expect(reply.content == "You're going 65 mph.")
        #expect(reply.toolCalls.isEmpty)
    }

    @Test func parsesToolCalls() throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[
          {"id":"call_1","type":"function","function":{"name":"findNearby","arguments":"{\\"category\\":\\"charger\\",\\"brandOrName\\":\\"Tesla\\"}"}}
        ]}}]}
        """
        let reply = try OpenAICompatibleProvider.parseReply(Data(json.utf8))
        #expect(reply.content == nil)
        #expect(reply.toolCalls.count == 1)
        #expect(reply.toolCalls[0].id == "call_1")
        #expect(reply.toolCalls[0].name == "findNearby")
        #expect(reply.toolCalls[0].argumentsJSON.contains("Tesla"))
    }

    @Test func garbageThrowsInsteadOfGuessing() {
        #expect(throws: (any Error).self) {
            _ = try OpenAICompatibleProvider.parseReply(Data("not json".utf8))
        }
    }

    @Test func requestBodyCarriesModelMessagesAndTools() throws {
        let body = try OpenAICompatibleProvider.requestBody(
            model: "gpt-test",
            messages: [["role": "system", "content": "hi"]],
            tools: OpenAICompatibleProvider.toolSpecs
        )
        let decoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(decoded?["model"] as? String == "gpt-test")
        let tools = decoded?["tools"] as? [[String: Any]]
        #expect(tools?.count == OpenAICompatibleProvider.toolSpecs.count)
        // Every spec must be a well-formed function declaration.
        for tool in tools ?? [] {
            #expect(tool["type"] as? String == "function")
            let function = tool["function"] as? [String: Any]
            #expect((function?["name"] as? String)?.isEmpty == false)
            #expect(function?["parameters"] != nil)
        }
    }

    @Test func configurationRequiresURLAndModel() {
        let defaults = UserDefaults.standard
        let savedURL = defaults.string(forKey: ModelProviderChoice.customURLKey)
        let savedModel = defaults.string(forKey: ModelProviderChoice.customModelKey)
        defer {
            defaults.set(savedURL, forKey: ModelProviderChoice.customURLKey)
            defaults.set(savedModel, forKey: ModelProviderChoice.customModelKey)
        }

        defaults.set("not a url", forKey: ModelProviderChoice.customURLKey)
        defaults.set("some-model", forKey: ModelProviderChoice.customModelKey)
        #expect(OpenAICompatibleProvider.Configuration.fromSettings() == nil)

        defaults.set("https://api.openai.com/v1", forKey: ModelProviderChoice.customURLKey)
        defaults.set("", forKey: ModelProviderChoice.customModelKey)
        #expect(OpenAICompatibleProvider.Configuration.fromSettings() == nil)

        defaults.set("gpt-4o-mini", forKey: ModelProviderChoice.customModelKey)
        let config = OpenAICompatibleProvider.Configuration.fromSettings()
        #expect(config?.model == "gpt-4o-mini")
        #expect(config?.baseURL.absoluteString == "https://api.openai.com/v1")
    }
}
