import Foundation

enum AgentResume {
    static func reasoningArguments(profile: LaunchProfile, effort: String) throws -> [String] {
        if effort.isEmpty { return [] }
        guard profile == .codex else { throw AgentResumeFailure.unavailable(profile.title) }
        guard effort.utf8.count <= 32, effort.utf8.allSatisfy({ (97...122).contains($0) }) else {
            throw AgentResumeFailure.invalidModel
        }
        // The picker uses the model's advertised levels; keep config values literal.
        return ["-c", "model_reasoning_effort=\"" + effort + "\""]
    }

    static func modelArguments(profile: LaunchProfile, model: String) throws -> [String] {
        if model.isEmpty { return [] }
        guard [.codex, .opencode, .claude, .gemini].contains(profile) else { throw AgentResumeFailure.unavailable(profile.title) }
        guard model.utf8.count <= 256, !model.hasPrefix("-"),
              !model.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || CharacterSet.whitespacesAndNewlines.contains($0) }) else {
            throw AgentResumeFailure.invalidModel
        }
        return ["--model", model]
    }

    static func arguments(profile: LaunchProfile, sessionID: String) throws -> [String] {
        try validateHistoryID(sessionID)
        switch profile {
        case .codex:
            return ["resume", sessionID]
        case .opencode:
            return ["--session", sessionID]
        default:
            throw AgentResumeFailure.unavailable(profile.title)
        }
    }

    static func validateHistoryID(_ sessionID: String) throws {
        guard (1...512).contains(sessionID.utf8.count),
              !sessionID.hasPrefix("-"),
              !sessionID.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw AgentResumeFailure.invalidID }
    }
}

enum AgentResumeFailure: LocalizedError, Equatable {
    case invalidModel
    case invalidID
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidModel:
            "Enter a model identifier under 256 bytes without whitespace or control characters."
        case .invalidID:
            "Enter a non-option history ID without control characters."
        case .unavailable(let profile):
            "Resume history is unavailable for \(profile)."
        }
    }
}
