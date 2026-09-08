import Foundation

@main
struct DirectModelCheck {
    static func main() throws {
        try checkProviderRequests()
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
        let responseDelta = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"streamed 👋\"}\n\n"
        expect(.incomplete) {
            try DirectModelClient.parseResponse(Data((responseDelta + "data: [DONE]\n\n").utf8), api: .responses)
        }
        for output in ["", ",\"output\":[]"] {
            let sparse = responseDelta + "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"\(output)}}\n\n"
            let text = try DirectModelClient.parseResponse(Data(sparse.utf8), api: .responses)
            precondition(text == "streamed 👋", "Sparse completion must retain streamed text")
        }
        for (output, error) in [("\"malformed\"", DirectModelError.invalidResponse),
                                ("[{\"content\":[{\"type\":\"refusal\"}]}]", .refused)] {
            let invalid = responseDelta + "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":\(output)}}\n\n"
            expect(error) { try DirectModelClient.parseResponse(Data(invalid.utf8), api: .responses) }
        }
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

    private static func checkProviderRequests() throws {
        let history: [[String: Any]] = [["role": "assistant", "content": NSNull(),
            "reasoning_content": "opaque replay", "tool_calls": [["id": "fixture", "type": "function"]]]]
        let native: [String: Any] = ["messages": history, "max_completion_tokens": 19, "stream": true,
            "store": false, "parallel_tool_calls": false, "tool_choice": "auto",
            "stream_options": ["include_usage": true],
            "tools": [["type": "function", "function": ["name": "read_file", "strict": true]]]]
        func body(_ base: String, _ api: DirectAPI = .chatCompletions, _ effort: String? = nil,
                  supplied: [String: Any] = native) throws -> [String: Any] {
            let request = try DirectModelClient.makeRequest(configuration: .init(baseURL: base, model: "advertised-fixture",
                api: api, maxOutputTokens: 100, reasoningEffort: effort), apiKey: "fixture-only", body: supplied)
            precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only")
            return try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        }
        let deepSeek = try body("https://api.deepseek.com", .chatCompletions, "high")
        precondition(deepSeek["max_tokens"] as? Int == 19 && deepSeek["max_completion_tokens"] == nil)
        precondition(deepSeek["store"] == nil && deepSeek["parallel_tool_calls"] == nil && deepSeek["tool_choice"] == nil)
        precondition(deepSeek["reasoning_effort"] as? String == "high")
        let stableTool = (deepSeek["tools"] as! [[String: Any]])[0]["function"] as! [String: Any]
        precondition(stableTool["name"] as? String == "read_file" && stableTool["strict"] == nil)
        let beta = try body("https://api.deepseek.com/beta", .chatCompletions, "high")
        let betaTool = (beta["tools"] as! [[String: Any]])[0]["function"] as! [String: Any]
        precondition(betaTool["strict"] as? Bool == true)
        var restricted = native
        restricted["tool_choice"] = "none"
        let restrictedBody = try body("https://api.deepseek.com", supplied: restricted)
        precondition(restrictedBody["tool_choice"] as? String == "none")
        let retained = (deepSeek["messages"] as! [[String: Any]])[0]
        precondition(retained["content"] as? String == "" && retained["reasoning_content"] as? String == "opaque replay")
        let disabled = try body("https://api.deepseek.com", .chatCompletions, "none")
        precondition(disabled["reasoning_effort"] == nil && (disabled["thinking"] as? [String: String])?["type"] == "disabled")
        let responses = try body("https://api.deepseek.com", .responses, "low", supplied: ["max_output_tokens": 17,
            "store": false, "include": ["reasoning.encrypted_content"], "parallel_tool_calls": false])
        precondition(responses["max_output_tokens"] as? Int == 17 && responses["include"] == nil && responses["store"] == nil)
        precondition((responses["reasoning"] as? [String: String])?["effort"] == "low")
        let google = try body("https://generativelanguage.googleapis.com/v1beta/openai/", .chatCompletions, "medium")
        precondition(google["store"] == nil && google["parallel_tool_calls"] == nil)
        precondition(google["max_completion_tokens"] as? Int == 19 && google["tool_choice"] as? String == "auto")
        let router = try body("https://openrouter.ai/api/v1", .chatCompletions, "high")
        precondition(router["max_completion_tokens"] as? Int == 19 && router["store"] == nil)
        precondition(router["reasoning_effort"] == nil && (router["reasoning"] as? [String: String])?["effort"] == "high")
        for endpoint in ["https://example.com/v1", "https://api.deepseek.com.example.com", "https://openrouter.ai/other"] {
            let custom = try body(endpoint, .chatCompletions, "max")
            precondition(custom["max_completion_tokens"] as? Int == 19 && custom["store"] as? Bool == false)
            precondition(custom["reasoning_effort"] as? String == "max")
        }
        expect(.invalidReasoningEffort) { try body("https://api.deepseek.com", .chatCompletions, "minimal") }
        expect(.invalidReasoningEffort) { try body("https://generativelanguage.googleapis.com/v1beta/openai", .chatCompletions, "xhigh") }
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
