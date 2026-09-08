import CoreFoundation
import Foundation

struct AgentTokenBudget: Sendable {
    let limit: Int?
    private(set) var reportedTokens = 0
    private(set) var unreportedRequests = 0

    var remaining: Int? { limit.map { max(0, $0 - reportedTokens) } }

    mutating func record(_ usage: AgentModelUsage?) {
        guard let input = usage?.inputTokens, let output = usage?.outputTokens,
              input >= 0, output >= 0 else { unreportedRequests += 1; return }
        // Cached input and reasoning are subsets, not additional tokens to charge twice.
        let sample = input.addingReportingOverflow(output)
        let total = reportedTokens.addingReportingOverflow(sample.partialValue)
        reportedTokens = sample.overflow || total.overflow ? Int.max : total.partialValue
    }

    func checkBeforeRequest() throws {
        guard let limit else { return }
        guard unreportedRequests == 0 else { throw Failure.usageUnavailable }
        guard reportedTokens < limit else { throw Failure.exhausted }
    }

    var context: String {
        let spent = "\(reportedTokens) reported input + output tokens used"
        let unknown = unreportedRequests == 0 ? "" : "; \(unreportedRequests) requests have unknown usage"
        guard let limit else { return spent + unknown + "; no total token limit." }
        return "Token allowance \(limit); " + spent + unknown + "; \(remaining ?? 0) remaining. "
            + "Finish within the remaining allowance. Usage arrives after a response; this is not a prepaid spending cap."
    }

    enum Failure: LocalizedError, Equatable {
        case usageUnavailable, exhausted
        var errorDescription: String? {
            switch self {
            case .usageUnavailable: "The provider did not report complete token usage. Further requests are stopped because this task has a token limit."
            case .exhausted: "The task reached its token limit. No further model requests will be sent."
            }
        }
    }
}

struct AgentModelUsage: Equatable, Sendable {
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    var cachedInputTokens: Int? = nil
    var reasoningTokens: Int? = nil

    static func parse(_ response: [String: Any], api: DirectAPI) -> Self? {
        guard let usage = response["usage"] as? [String: Any] else { return nil }
        let input = counter(usage[api == .responses ? "input_tokens" : "prompt_tokens"])
        let output = counter(usage[api == .responses ? "output_tokens" : "completion_tokens"])
        let inputDetails = usage[api == .responses ? "input_tokens_details" : "prompt_tokens_details"] as? [String: Any]
        let outputDetails = usage[api == .responses ? "output_tokens_details" : "completion_tokens_details"] as? [String: Any]
        let nestedCache = counter(inputDetails?["cached_tokens"])
        let deepSeekCache = api == .chatCompletions ? counter(usage["prompt_cache_hit_tokens"]) : nil
        var cached = nestedCache ?? deepSeekCache
        if let nestedCache, let deepSeekCache, nestedCache != deepSeekCache { cached = nil }
        if let input, let value = cached, value > input { cached = nil }
        var reasoning = counter(outputDetails?["reasoning_tokens"])
        if let output, let value = reasoning, value > output { reasoning = nil }
        guard input != nil || output != nil || cached != nil || reasoning != nil else { return nil }
        return Self(inputTokens: input, outputTokens: output, cachedInputTokens: cached, reasoningTokens: reasoning)
    }

    private static func counter(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let count = Int(number.stringValue), count >= 0 else { return nil }
        return count
    }
}

enum AgentContextBudget {
    struct Compaction {
        let history: [[String: Any]]
        let omittedTurns: Int
        let bytesBefore: Int
        let bytesAfter: Int
    }

    enum Failure: LocalizedError, Equatable {
        case invalidHistory, newestTurnTooLarge
        var errorDescription: String? {
            switch self {
            case .invalidHistory: "The conversation has an incomplete or invalid tool history. Start a new conversation."
            case .newestTurnTooLarge: "The current turn and instructions exceed this agent's context budget. Shorten the context or start a new conversation."
            }
        }
    }

    static func byteCount(_ history: [[String: Any]]) throws -> Int {
        guard JSONSerialization.isValidJSONObject(history) else { throw Failure.invalidHistory }
        return try JSONSerialization.data(withJSONObject: history, options: [.sortedKeys]).count
    }

    /// Drops whole older user turns; never trims policy, function arguments, or a call/result group.
    static func compact(_ history: [[String: Any]], api: DirectAPI, maximumBytes: Int) throws -> Compaction {
        let before = try byteCount(history)
        let prefixEnd = history.firstIndex { !["system", "developer"].contains($0["role"] as? String ?? "") } ?? history.endIndex
        let starts = history.indices.filter { $0 >= prefixEnd && history[$0]["role"] as? String == "user" }
        guard starts.first == prefixEnd, !starts.isEmpty else { throw Failure.invalidHistory }
        for (offset, start) in starts.enumerated() {
            let end = offset + 1 < starts.count ? starts[offset + 1] : history.endIndex
            try validateToolGroups(history[start..<end], api: api)
        }
        if before <= maximumBytes { return Compaction(history: history, omittedTurns: 0, bytesBefore: before, bytesAfter: before) }
        let noticeText = "[Earlier conversation turns were omitted to fit the context budget. They were not summarized. Do not assume their contents; request needed context again.]"
        let notice: [String: Any] = ["role": "system", "content": api == .responses ? [["type": "input_text", "text": noticeText]] : noticeText]
        // Keep one stable notice so repeated compaction neither grows nor changes the policy prefix.
        let prefix = history[..<prefixEnd].filter { !NSDictionary(dictionary: $0).isEqual(to: notice) }
        for omitted in 1..<starts.count {
            let candidate = prefix + [notice] + Array(history[starts[omitted]...])
            let after = try byteCount(candidate)
            if after <= maximumBytes {
                return Compaction(history: candidate, omittedTurns: omitted, bytesBefore: before, bytesAfter: after)
            }
        }
        throw Failure.newestTurnTooLarge
    }

    static func boundedToolOutput(_ text: String, maximumBytes: Int) -> String {
        guard maximumBytes > 0 else { return "" }
        guard text.utf8.count > maximumBytes else { return text }
        let notice = "\n[Tool output truncated to fit the context budget.]"
        guard maximumBytes >= notice.utf8.count else { return utf8Prefix("[truncated]", maximumBytes: maximumBytes) }
        return utf8Prefix(text, maximumBytes: maximumBytes - notice.utf8.count) + notice
    }

    static func utf8Prefix(_ text: String, maximumBytes: Int) -> String {
        guard maximumBytes > 0 else { return "" }
        var data = Data(text.utf8.prefix(maximumBytes))
        while String(data: data, encoding: .utf8) == nil { data.removeLast() }
        return String(decoding: data, as: UTF8.self)
    }

    private static func validateToolGroups(_ turn: ArraySlice<[String: Any]>, api: DirectAPI) throws {
        var pending = Set<String>(), seen = Set<String>()
        for item in turn {
            let calls: [String]
            let resultID: String?
            switch api {
            case .responses:
                if item["type"] as? String == "function_call" {
                    guard let id = item["call_id"] as? String else { throw Failure.invalidHistory }
                    calls = [id]
                } else { calls = [] }
                if item["type"] as? String == "function_call_output" {
                    guard let id = item["call_id"] as? String, item["output"] is String else { throw Failure.invalidHistory }
                    resultID = id
                } else { resultID = nil }
            case .chatCompletions:
                if let toolCalls = item["tool_calls"] {
                    guard item["role"] as? String == "assistant", let entries = toolCalls as? [[String: Any]], pending.isEmpty else { throw Failure.invalidHistory }
                    calls = try entries.map {
                        guard let id = $0["id"] as? String else { throw Failure.invalidHistory }
                        return id
                    }
                } else { calls = [] }
                if item["role"] as? String == "tool" {
                    guard let id = item["tool_call_id"] as? String, item["content"] is String else { throw Failure.invalidHistory }
                    resultID = id
                } else { resultID = nil }
            }
            for id in calls {
                guard !id.isEmpty, id.utf8.count <= 512, !id.utf8.contains(0), seen.insert(id).inserted else { throw Failure.invalidHistory }
                pending.insert(id)
            }
            if let resultID, pending.remove(resultID) == nil { throw Failure.invalidHistory }
        }
        guard pending.isEmpty else { throw Failure.invalidHistory }
    }
}
