import Foundation

@main enum AgentContextBudgetCheck {
    static func main() throws {
        var tokens = AgentTokenBudget(limit: 120)
        try tokens.checkBeforeRequest()
        tokens.record(.init(inputTokens: 100, outputTokens: 20, cachedInputTokens: 80, reasoningTokens: 10))
        assert(tokens.reportedTokens == 120 && tokens.remaining == 0)
        do { try tokens.checkBeforeRequest(); assertionFailure("Budget must stop the next request") }
        catch { assert(error as? AgentTokenBudget.Failure == .exhausted) }
        var missing = AgentTokenBudget(limit: 1_024)
        missing.record(.init(inputTokens: 50))
        do { try missing.checkBeforeRequest(); assertionFailure("Missing usage cannot become free tokens") }
        catch { assert(error as? AgentTokenBudget.Failure == .usageUnavailable) }
        var unlimited = AgentTokenBudget(limit: nil)
        unlimited.record(nil)
        try unlimited.checkBeforeRequest()
        var overflow = AgentTokenBudget(limit: 1_024)
        overflow.record(.init(inputTokens: Int.max, outputTokens: Int.max))
        assert(overflow.remaining == 0)
        func usage(_ json: String, api: DirectAPI = .responses) throws -> AgentModelUsage? {
            AgentModelUsage.parse(try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any], api: api)
        }
        let responses = try usage(#"{"usage":{"input_tokens":100,"output_tokens":20,"input_tokens_details":{"cached_tokens":60},"output_tokens_details":{"reasoning_tokens":8}}}"#)
        assert(responses == AgentModelUsage(inputTokens: 100, outputTokens: 20, cachedInputTokens: 60, reasoningTokens: 8))
        let chat = try usage(#"{"usage":{"prompt_tokens":200,"completion_tokens":40,"prompt_tokens_details":{"cached_tokens":128},"completion_tokens_details":{"reasoning_tokens":12}}}"#, api: .chatCompletions)
        assert(chat == AgentModelUsage(inputTokens: 200, outputTokens: 40, cachedInputTokens: 128, reasoningTokens: 12))
        let deepSeek = try usage(#"{"usage":{"prompt_tokens":200,"completion_tokens":40,"prompt_cache_hit_tokens":128}}"#, api: .chatCompletions)
        assert(deepSeek?.cachedInputTokens == 128)
        let zero = try usage(#"{"usage":{"input_tokens":0,"output_tokens":0,"input_tokens_details":{"cached_tokens":0}}}"#)
        assert(zero?.inputTokens == 0 && zero?.cachedInputTokens == 0)
        for json in ["{}", #"{"usage":null}"#, #"{"usage":{}}"#,
                     #"{"usage":{"input_tokens":true,"output_tokens":-1,"input_tokens_details":{"cached_tokens":1.5},"output_tokens_details":{"reasoning_tokens":"20"}}}"#,
                     #"{"usage":{"input_tokens":18446744073709551615}}"#] {
            let missing = try usage(json)
            assert(missing == nil, "Missing or invalid usage must stay unknown")
        }
        let invalidDetails = try usage(#"{"usage":{"input_tokens":10,"output_tokens":3,"input_tokens_details":{"cached_tokens":11},"output_tokens_details":{"reasoning_tokens":4}}}"#)
        assert(invalidDetails == AgentModelUsage(inputTokens: 10, outputTokens: 3))
        let conflict = try usage(#"{"usage":{"prompt_tokens":200,"prompt_tokens_details":{"cached_tokens":100},"prompt_cache_hit_tokens":90}}"#, api: .chatCompletions)
        assert(conflict?.inputTokens == 200 && conflict?.cachedInputTokens == nil)
        let partial = try usage(#"{"usage":{"output_tokens":9}}"#)
        assert(partial == AgentModelUsage(outputTokens: 9), "Do not carry prior-request usage into missing fields")

        for api in DirectAPI.allCases {
            func message(_ role: String, _ text: String) -> [String: Any] {
                if api == .responses { return ["role": role, "content": [["type": role == "assistant" ? "output_text" : "input_text", "text": text]]] }
                return ["role": role, "content": text]
            }
            func call(_ id: String) -> [String: Any] {
                if api == .responses { return ["type": "function_call", "call_id": id, "name": "read_file", "arguments": #"{"path":"file.swift"}"#] }
                return ["role": "assistant", "content": NSNull(), "tool_calls": [["id": id, "type": "function", "function": ["name": "read_file", "arguments": #"{"path":"file.swift"}"#]]]]
            }
            func result(_ id: String) -> [String: Any] {
                if api == .responses { return ["type": "function_call_output", "call_id": id, "output": "Current file contents"] }
                return ["role": "tool", "tool_call_id": id, "content": "Current file contents"]
            }
            let prefix = [message("system", "Stable policy"), message("developer", "Stable constraints")]
            var newest = [message("user", "Read the file"), call("one"), result("one"), call("two"), result("two")]
            if api == .responses { newest.insert(["type": "reasoning", "encrypted_content": "retained-exactly", "summary": []], at: 1) }
            let history = prefix + [message("user", String(repeating: "old ", count: 1_000)), message("assistant", "Old reply")] + newest
            let parallelCalls: [[String: Any]]
            if api == .responses { parallelCalls = [call("one"), call("two")] }
            else {
                parallelCalls = [["role": "assistant", "tool_calls": (call("one")["tool_calls"] as! [[String: Any]]) + (call("two")["tool_calls"] as! [[String: Any]])]]
            }
            let parallel = prefix + [message("user", "Read two files")] + parallelCalls + [result("two"), result("one")]
            let complete = try AgentContextBudget.compact(parallel, api: api, maximumBytes: 2_000)
            assert(complete.omittedTurns == 0 && NSArray(array: complete.history).isEqual(to: parallel))
            let compacted = try AgentContextBudget.compact(history, api: api, maximumBytes: 2_000)
            assert(compacted.omittedTurns == 1 && compacted.bytesBefore > compacted.bytesAfter && compacted.bytesAfter <= 2_000)
            assert(NSArray(array: Array(compacted.history.prefix(2))).isEqual(to: prefix))
            assert(NSArray(array: Array(compacted.history.suffix(newest.count))).isEqual(to: newest), "Keep latest arguments, reasoning and call/results intact")
            assert(compacted.history[2]["role"] as? String == "system")
            let notice = try JSONSerialization.data(withJSONObject: compacted.history[2], options: .sortedKeys)
            assert(String(decoding: notice, as: UTF8.self).contains("not summarized"))
            let again = try AgentContextBudget.compact(compacted.history, api: api, maximumBytes: 2_000)
            assert(again.omittedTurns == 0 && NSArray(array: again.history).isEqual(to: compacted.history))
            let later = compacted.history + [message("assistant", String(repeating: "long ", count: 500)), message("user", "Next task")]
            let repeated = try AgentContextBudget.compact(later, api: api, maximumBytes: 2_000)
            assert(repeated.omittedTurns == 1 && repeated.history.count == 4, "Repeated compaction keeps one notice and the original policy")

            for broken in [prefix + [message("user", "Read"), result("missing")],
                           prefix + [message("user", "Read"), call("one")],
                           prefix + [message("user", "Read"), call("one"), result("one"), result("one")],
                           prefix + [message("user", "Read"), call("one"), message("user", "New turn"), result("one")]] {
                expect(.invalidHistory) { _ = try AgentContextBudget.compact(broken, api: api, maximumBytes: 10_000) }
            }
            expect(.newestTurnTooLarge) { _ = try AgentContextBudget.compact(history, api: api, maximumBytes: 100) }
            expect(.newestTurnTooLarge) { _ = try AgentContextBudget.compact([message("system", String(repeating: "policy ", count: 500)), message("user", "Current task")], api: api, maximumBytes: 500) }
            let fresh = try AgentContextBudget.compact(prefix + [message("user", "Newly read contents")], api: api, maximumBytes: 2_000)
            assert(NSArray(array: fresh.history.suffix(1).map { $0 }).isEqual(to: [message("user", "Newly read contents")]), "Fresh input must not reuse earlier retained context")
        }

        let unicode = String(repeating: "🙂é漢字e\u{301}", count: 100)
        for limit in 0...160 {
            let bounded = AgentContextBudget.boundedToolOutput(unicode, maximumBytes: limit)
            assert(bounded.utf8.count <= limit && !bounded.contains("�"))
            if limit >= 60 { assert(bounded.contains("truncated")) }
            let prefix = AgentContextBudget.utf8Prefix(unicode, maximumBytes: limit)
            assert(prefix.utf8.count <= limit && unicode.utf8.starts(with: prefix.utf8) && !prefix.contains("�"))
        }
        assert(AgentContextBudget.boundedToolOutput("fresh contents", maximumBytes: 100) == "fresh contents")
        assert(AgentContextBudget.boundedToolOutput("changed contents", maximumBytes: 100) == "changed contents")
        expect(.invalidHistory) { _ = try AgentContextBudget.byteCount([["content": Date()]]) }

        let configuration = DirectModelConfiguration(baseURL: "https://example.com/v1", model: "fixture", api: .responses, maxOutputTokens: 100)
        let first: [String: Any] = ["input": [["role": "system", "content": "policy"]], "tools": [["name": "read", "parameters": ["type": "object", "properties": ["z": ["type": "string"], "a": ["type": "string"]]]]]]
        let second: [String: Any] = ["tools": [["parameters": ["properties": ["a": ["type": "string"], "z": ["type": "string"]], "type": "object"], "name": "read"]], "input": [["content": "policy", "role": "system"]]]
        let expected = try DirectModelClient.makeRequest(configuration: configuration, apiKey: "fixture", body: first).httpBody
        assert(expected == Data(#"{"input":[{"content":"policy","role":"system"}],"model":"fixture","tools":[{"name":"read","parameters":{"properties":{"a":{"type":"string"},"z":{"type":"string"}},"type":"object"}}]}"#.utf8))
        for _ in 0..<20 {
            let actual = try DirectModelClient.makeRequest(configuration: configuration, apiKey: "fixture", body: second).httpBody
            assert(actual == expected, "Policy and schema serialization must not depend on dictionary insertion order")
        }
        print("context turn/tool integrity, stable request bytes, UTF-8 bounds and observed provider usage checks passed")
    }

    private static func expect(_ expected: AgentContextBudget.Failure, _ action: () throws -> Void) {
        do { try action(); fatalError("Expected \(expected)") }
        catch let error as AgentContextBudget.Failure { assert(error == expected) }
        catch { fatalError("Unexpected error: \(error)") }
    }
}
