import Foundation

@main enum AgentModelCatalogCheck {
    static func main() async throws {
        let codex = Data(#"{"id":2,"result":{"data":[{"id":"picker-example","model":"gpt-example","displayName":"GPT Example","supportedReasoningEfforts":[{"reasoningEffort":"low"},{"reasoningEffort":"high"}],"defaultReasoningEffort":"low"}],"nextCursor":"page-2"}}"#.utf8)
        let page = try AgentModelCatalog.parseCodexResponse(codex)
        precondition(page.models == [AgentModel(id: "gpt-example", displayName: "GPT Example",
                                               reasoningEfforts: ["low", "high"], defaultReasoningEffort: "low")])
        precondition(page.nextCursor == "page-2")
        precondition(AgentModelPicker.reasoningAfterSuccessfulCatalog(
            profile: .codex, modelID: "manual", reasoning: "max", models: page.models
        ) == "max", "manual models retain explicit reasoning")
        precondition(AgentModelPicker.reasoningAfterSuccessfulCatalog(
            profile: .codex, modelID: "gpt-example", reasoning: "high", models: page.models
        ) == "high", "advertised support retains reasoning")
        precondition(AgentModelPicker.reasoningAfterSuccessfulCatalog(
            profile: .codex, modelID: "gpt-example", reasoning: "max", models: page.models
        ).isEmpty, "confirmed incompatibility clears reasoning")
        precondition(AgentModelPicker.reasoningAfterSuccessfulCatalog(
            profile: .codex, modelID: "manual", reasoning: "max", models: []
        ) == "max", "empty catalogues retain reasoning")

        let openCode = Data("""
        provider/model
        {"id":"model","providerID":"provider","name":"Model Name","variants":{"deep":{"reasoningEffort":"high"},"low":{"reasoningEffort":"low"}}}
        provider/plain
        {"id":"plain","providerID":"provider","name":"Plain","variants":{}}
        """.utf8)
        let parsed = try AgentModelCatalog.parseOpenCodeOutput(openCode)
        precondition(parsed[0] == AgentModel(id: "provider/model", displayName: "Model Name",
                                            reasoningEfforts: [], defaultReasoningEffort: nil))
        precondition(parsed[1].reasoningEfforts.isEmpty)

        expectFailure { try AgentModelCatalog.parseCodexResponse(Data("{}".utf8)) }
        expectFailure { try AgentModelCatalog.parseCodexResponse(Data(#"{"result":{"data":[{"id":"x","model":"x","displayName":"X","supportedReasoningEfforts":[],"defaultReasoningEffort":"low"}]}}"#.utf8)) }
        expectFailure { try AgentModelCatalog.parseCodexResponse(Data(#"{"result":{"data":[{"id":"a","model":"same","displayName":"A","supportedReasoningEfforts":[],"defaultReasoningEffort":null},{"id":"b","model":"same","displayName":"B","supportedReasoningEfforts":[],"defaultReasoningEffort":null}]}}"#.utf8)) }
        let excessiveEfforts = (0...16).map { #"{"reasoningEffort":"e\#($0)"}"# }.joined(separator: ",")
        expectFailure {
            try AgentModelCatalog.parseCodexResponse(Data(#"{"result":{"data":[{"id":"x","model":"x","displayName":"X","supportedReasoningEfforts":[\#(excessiveEfforts)],"defaultReasoningEffort":"e0"}]}}"#.utf8))
        }
        expectFailure { try AgentModelCatalog.parseOpenCodeOutput(Data("provider/x\n{\"id\":\"x\"".utf8)) }
        expectFailure { try AgentModelCatalog.parseOpenCodeOutput(Data(repeating: 0x20, count: 4 * 1_024 * 1_024 + 1)) }
        do {
            _ = try await AgentModelCatalog.load(profile: .codex,
                                                 directory: URL(fileURLWithPath: "/path/that/does/not/exist"))
            preconditionFailure("Expected invalid directory")
        } catch AgentModelCatalog.CatalogError.invalidDirectory {}
        print("PASS exact Codex/OpenCode model IDs, advertised reasoning, malformed data, and output bound")

        if CommandLine.arguments.contains("--live") {
            let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            for profile in [LaunchProfile.codex, .opencode] {
                let models = try await AgentModelCatalog.load(profile: profile, directory: directory)
                precondition(!models.isEmpty)
                precondition(Set(models.map(\.id)).count == models.count)
                print("PASS live \(profile.title) catalog: \(models.count) models")
            }
            let cancelled = Task { try await AgentModelCatalog.load(profile: .codex, directory: directory) }
            cancelled.cancel()
            do {
                _ = try await cancelled.value
                preconditionFailure("Cancelled discovery completed")
            } catch is CancellationError {
                print("PASS cancellation reaches catalog worker")
            }
        }
    }

    private static func expectFailure(_ operation: () throws -> Any) {
        do {
            _ = try operation()
            preconditionFailure("Expected failure")
        } catch {}
    }
}
