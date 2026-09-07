import Foundation

@main
enum AgentResumeCheck {
    static func main() throws {
        let identifier = "019c6e27-e55b-73d1-87d8-4e01f1f75043"
        let codex = try AgentResume.arguments(profile: .codex, sessionID: identifier)
        let opencode = try AgentResume.arguments(profile: .opencode, sessionID: identifier)
        precondition(codex == ["resume", identifier])
        precondition(opencode == ["--session", identifier])
        let named = try AgentResume.arguments(profile: .codex, sessionID: "named history")
        precondition(named == ["resume", "named history"])

        for invalid in ["", "-last", "--session", "bad\nid", "bad\u{0000}id", String(repeating: "a", count: 513)] {
            expect(.invalidID) { try AgentResume.arguments(profile: .codex, sessionID: invalid) }
        }
        expect(.unavailable("Shell")) { try AgentResume.arguments(profile: .shell, sessionID: identifier) }
        expect(.unavailable("Pi")) { try AgentResume.arguments(profile: .pi, sessionID: identifier) }
        let reasoning = try AgentResume.reasoningArguments(profile: .codex, effort: "max")
        precondition(reasoning == ["-c", "model_reasoning_effort=\"max\""])
        expect(.invalidModel) { try AgentResume.reasoningArguments(profile: .codex, effort: "max\nother=true") }
        let model = try AgentResume.modelArguments(profile: .codex, model: "chosen-model")
        precondition(model + codex == ["--model", "chosen-model", "resume", identifier])
        let claudeModel = try AgentResume.modelArguments(profile: .claude, model: "sonnet")
        precondition(claudeModel == ["--model", "sonnet"])
        let geminiModel = try AgentResume.modelArguments(profile: .gemini, model: "selected-model")
        precondition(geminiModel == ["--model", "selected-model"])
        let openModel = try AgentResume.modelArguments(profile: .opencode, model: "provider/model")
        precondition(openModel == ["--model", "provider/model"])
        for invalid in ["--help", "bad model", "bad\u{0007}", String(repeating: "x", count: 257)] {
            expect(.invalidModel) { try AgentResume.modelArguments(profile: .codex, model: invalid) }
        }
        print("PASS exact Codex/OpenCode resume argv and bounded history IDs")
    }

    private static func expect(_ expected: AgentResumeFailure, _ operation: () throws -> [String]) {
        do {
            _ = try operation()
            preconditionFailure("Expected \(expected)")
        } catch let error as AgentResumeFailure {
            precondition(error == expected)
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }
}
