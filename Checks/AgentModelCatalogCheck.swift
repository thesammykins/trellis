import Darwin
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
        try await checkCapturedExecutable()
        print("PASS exact model IDs, reasoning, parser bounds, selected executable and saved-argument discovery suppression")

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

    private static func checkCapturedExecutable() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Trellis-CatalogRoute-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"]
        defer {
            if let inheritedPath { setenv("PATH", inheritedPath, 1) }
            else { unsetenv("PATH") }
        }
        setenv("PATH", root.path, 1)
        func fixture(_ name: String, model: String) throws -> URL {
            let file = root.appendingPathComponent(name)
            let script = """
            #!/bin/sh
            printf '%s\\n' "$@" >> "$0.invocations"
            [ "$#" = 2 ] && [ "$1" = models ] && [ "$2" = --verbose ] || exit 9
            printf '%s\\n' '{"id":"\(model)","providerID":"fixture","name":"\(model)"}'
            """
            try Data(script.utf8).write(to: file)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            return file
        }
        let pathExecutable = try fixture("opencode", model: "path-model")
        let selected = try fixture("saved gateway ' 空間", model: "selected-model")
        let selectedModels = try await AgentModelCatalog.load(profile: .opencode, directory: root,
                                                              executable: selected.path)
        precondition(selectedModels.map(\.id) == ["fixture/selected-model"])
        precondition(!manager.fileExists(atPath: pathExecutable.path + ".invocations"), "Selected discovery ran the PATH executable")
        let marker = URL(fileURLWithPath: selected.path + ".invocations")
        let before = try Data(contentsOf: marker)
        precondition(String(decoding: before, as: UTF8.self) == "models\n--verbose\n")
        do {
            _ = try await AgentModelCatalog.load(profile: .opencode, directory: root,
                executable: selected.path, launchArguments: ["--config", "literal $(unchanged) profile"])
            preconditionFailure("A launcher with saved arguments performed model discovery")
        } catch AgentModelCatalog.CatalogError.savedArguments {}
        let after = try Data(contentsOf: marker)
        precondition(after == before && !manager.fileExists(atPath: pathExecutable.path + ".invocations"))
        do {
            _ = try await AgentModelCatalog.load(profile: .opencode, directory: root,
                                                 executable: root.appendingPathComponent("missing").path)
            preconditionFailure("An unavailable selected executable fell back to PATH")
        } catch AgentModelCatalog.CatalogError.commandFailed {}
        precondition(!manager.fileExists(atPath: pathExecutable.path + ".invocations"))
        let defaults = try await AgentModelCatalog.load(profile: .opencode, directory: root)
        precondition(defaults.map(\.id) == ["fixture/path-model"], "Default callers must retain PATH discovery")
    }

    private static func expectFailure(_ operation: () throws -> Any) {
        do {
            _ = try operation()
            preconditionFailure("Expected failure")
        } catch {}
    }
}
