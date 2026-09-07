import Foundation

@main
struct DirectModelCheck {
    static func main() throws {
        let responses = DirectModelConfiguration(baseURL: "https://api.openai.com/v1", model: "gpt-test", api: .responses, maxOutputTokens: 64)
        let request = try DirectModelClient.makeRequest(configuration: responses, apiKey: "fixture-key", prompt: "hello")
        precondition(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        precondition(body["stream"] as? Bool == false && body["store"] as? Bool == false)
        precondition((body["tools"] as? [Any])?.isEmpty == true && body["max_output_tokens"] as? Int == 64)

        let chat = DirectModelConfiguration(baseURL: "http://127.0.0.1:11434/v1/", model: "local", api: .chatCompletions, maxOutputTokens: 32)
        let chatRequest = try DirectModelClient.makeRequest(configuration: chat, apiKey: "local", prompt: "hello")
        precondition(chatRequest.url?.absoluteString == "http://127.0.0.1:11434/v1/chat/completions")
        precondition(DirectModelClient.redirectedRequest(URLRequest(url: URL(string: "https://elsewhere.invalid")!)) == nil)
        let chatBody = try JSONSerialization.jsonObject(with: chatRequest.httpBody!) as! [String: Any]
        precondition(chatBody["max_completion_tokens"] as? Int == 32)

        precondition(body["reasoning"] == nil && body["reasoning_effort"] == nil)
        precondition(chatBody["reasoning"] == nil && chatBody["reasoning_effort"] == nil)
        let legacy = Data(#"{"baseURL":"https://example.com/v1","model":"legacy","api":"responses","maxOutputTokens":64}"#.utf8)
        let decoded = try JSONDecoder().decode(DirectModelConfiguration.self, from: legacy)
        precondition(decoded.reasoningEffort == nil)
        for api in DirectAPI.allCases {
            var configuration = responses
            configuration.api = api
            for effort in DirectModelConfiguration.reasoningEfforts {
                configuration.reasoningEffort = effort
                let request = try DirectModelClient.makeRequest(configuration: configuration, apiKey: "fixture",
                    body: ["reasoning": ["effort": "invalid"], "reasoning_effort": "invalid"])
                let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                if api == .responses {
                    precondition((payload["reasoning"] as? [String: String]) == ["effort": effort] && payload["reasoning_effort"] == nil)
                } else {
                    precondition(payload["reasoning_effort"] as? String == effort && payload["reasoning"] == nil)
                }
            }
            for invalid in ["", "LOW", "low ", "ultra", "unexpected", "low\n"] {
                configuration.reasoningEffort = invalid
                expect(.invalidReasoningEffort) { try DirectModelClient.makeRequest(configuration: configuration, apiKey: "fixture", prompt: "hello") }
            }
        }

        let responseJSON = Data(#"{"status":"completed","error":null,"incomplete_details":null,"output":[{"type":"message","content":[{"type":"output_text","text":"ready"}]}]}"#.utf8)
        let parsedResponse = try DirectModelClient.parseResponse(responseJSON, api: .responses)
        precondition(parsedResponse == "ready")
        let chatJSON = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"done","refusal":null}}]}"#.utf8)
        let parsedChat = try DirectModelClient.parseResponse(chatJSON, api: .chatCompletions)
        precondition(parsedChat == "done")

        let responseSSE = Data("""
        data: {"type":"response.output_text.delta","delta":"not "}

        data: {"type":"response.completed","response":{"status":"completed","error":null,"incomplete_details":null,"output":[{"content":[{"type":"output_text","text":"not duplicated"}]}]}}

        """.utf8)
        let parsedResponseSSE = try DirectModelClient.parseResponse(responseSSE, api: .responses)
        precondition(parsedResponseSSE == "not duplicated")
        let chatSSE = Data("""
        data: {"choices":[{"delta":{"content":"stream"},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """.utf8)
        let parsedChatSSE = try DirectModelClient.parseResponse(chatSSE, api: .chatCompletions)
        precondition(parsedChatSSE == "stream")

        expect(.invalidConfiguration) { try DirectModelClient.makeRequest(configuration: .init(baseURL: "http://example.com/v1", model: "x", api: .responses, maxOutputTokens: 1), apiKey: "x", prompt: "x") }
        expect(.invalidConfiguration) { try DirectModelClient.makeRequest(configuration: .init(baseURL: "https://user:pass@example.com/v1", model: "x", api: .responses, maxOutputTokens: 1), apiKey: "x", prompt: "x") }
        expect(.invalidConfiguration) { try DirectModelClient.makeRequest(configuration: .init(baseURL: "https://example.com/v1?redirect=https://elsewhere", model: "x", api: .responses, maxOutputTokens: 1), apiKey: "x", prompt: "x") }
        expect(.invalidConfiguration) { try DirectModelClient.makeRequest(configuration: .init(baseURL: "https://example.com/v1", model: "x", api: .responses, maxOutputTokens: 0), apiKey: "x", prompt: "x") }
        expect(.missingAPIKey) { try DirectModelClient.makeRequest(configuration: responses, apiKey: "", prompt: "x") }
        expect(.invalidAPIKey) { try DirectModelClient.makeRequest(configuration: responses, apiKey: "header\ninjection", prompt: "x") }
        expect(.invalidAPIKey) { try DirectModelClient.makeRequest(configuration: responses, apiKey: "header\rinjection", prompt: "x") }
        expect(.invalidAPIKey) { try DirectModelClient.makeRequest(configuration: responses, apiKey: "header\0injection", prompt: "x") }
        expect(.invalidAPIKey) { try DirectModelClient.makeRequest(configuration: responses, apiKey: String(repeating: "x", count: 16 * 1024 + 1), prompt: "x") }
        expect(.invalidModel) { try DirectModelClient.makeRequest(configuration: .init(baseURL: "https://example.com/v1", model: "bad\0model", api: .responses, maxOutputTokens: 1), apiKey: "x", prompt: "x") }
        expect(.invalidModel) { try DirectModelClient.makeRequest(configuration: .init(baseURL: "https://example.com/v1", model: String(repeating: "m", count: 257), api: .responses, maxOutputTokens: 1), apiKey: "x", prompt: "x") }
        expect(.invalidPrompt) { try DirectModelClient.makeRequest(configuration: responses, apiKey: "x", prompt: "bad\0prompt") }
        expect(.inputTooLarge) { try DirectModelClient.makeRequest(configuration: responses, apiKey: "x", prompt: String(repeating: "x", count: 128 * 1024 + 1)) }
        expect(.responseTooLarge) { try DirectModelClient.parseResponse(Data(repeating: 0, count: 2 * 1024 * 1024 + 1), api: .responses) }
        expect(.incomplete) { try DirectModelClient.parseResponse(Data(#"{"status":"incomplete","output":[]}"#.utf8), api: .responses) }
        expect(.refused) { try DirectModelClient.parseResponse(Data(#"{"choices":[{"finish_reason":"stop","message":{"content":null,"refusal":"no"}}]}"#.utf8), api: .chatCompletions) }
        expect(.incomplete) { try DirectModelClient.parseResponse(Data("data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n".utf8), api: .responses) }
        precondition(DirectModelError.missingAPIKey.errorDescription == "Add an API key for this model route.")
        precondition(DirectModelError.requestFailed(429).errorDescription?.contains("429") == true)
        precondition(DirectModelError.requestFailed(401).errorDescription?.contains("saved API key") == true)
        precondition(DirectModelError.requestFailed(403).errorDescription?.contains("permissions") == true)
        precondition(DirectModelError.requestFailed(404).errorDescription?.contains("model") == true)

        print("Direct model request and parser checks passed")
    }

    private static func expect<T>(_ expected: DirectModelError, _ operation: () throws -> T) {
        do {
            _ = try operation()
            preconditionFailure("Expected \(expected)")
        } catch let error as DirectModelError {
            precondition(error == expected)
        } catch {
            preconditionFailure("Unexpected error type")
        }
    }
}
