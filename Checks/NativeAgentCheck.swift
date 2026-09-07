import Darwin
import Foundation

@main
enum NativeAgentCheck {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: root.appendingPathComponent("note.txt"))

        try await checkResponses(root)
        try await checkChat(root)
        try await checkTools(root)
        try await checkExitedParentCleanup(root)
        try await checkRejectedCommand(root)
        try await checkStaleApproval(root)
        try await checkMalformedTool(root)
        try await checkRestartRace(root)
        try await checkFollowUpHistoryBound(root)
        try await checkMemoryAndSkillTools(root)
        print("native agent checks passed")
    }

    @MainActor
    private static func checkResponses(_ root: URL) async throws {
        let fixture = FixtureTransport([
            #"{"status":"completed","error":null,"output":[{"type":"function_call","id":"fc_1","call_id":"call_1","name":"list_directory","arguments":"{\"path\":\".\"}","status":"completed"}]}"#,
            #"{"status":"completed","error":null,"output":[{"type":"message","id":"msg_1","role":"assistant","status":"completed","content":[{"type":"output_text","text":"done","annotations":[]}]}]}"#,
            #"{"status":"completed","error":null,"output":[{"type":"message","id":"msg_2","role":"assistant","status":"completed","content":[{"type":"output_text","text":"followed up","annotations":[]}]}]}"#,
        ])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                                             transport: { request in try await fixture.send(request) })
        runtime.start(prompt: "inspect")
        assert(!runtime.followUp(prompt: "must not interrupt") && runtime.state == .working)
        await wait { runtime.state == NativeAgentRunState.waitingApproval }
        assert(runtime.pendingApproval?.phase == NativeAgentApproval.Phase.execute)
        let firstRequestCount = await fixture.count
        assert(firstRequestCount == 1)
        runtime.approvePendingTool(runtime.pendingApproval!.id)
        await wait { runtime.pendingApproval?.phase == NativeAgentApproval.Phase.sendOutput }
        assert(runtime.receipts.first?.output.contains("note.txt") == true)
        let preOutputRequestCount = await fixture.count
        assert(preOutputRequestCount == 1)
        runtime.approvePendingTool(runtime.pendingApproval!.id, outputForModel: "[reviewed listing]")
        await wait { runtime.state == NativeAgentRunState.completed }
        assert(runtime.messages.last?.text == "done")
        let request = await fixture.request(at: 1)
        let body = try jsonBody(request)
        let input = body["input"] as? [[String: Any]]
        assert(input?.contains { $0["type"] as? String == "function_call" && $0["call_id"] as? String == "call_1" } == true)
        assert(input?.contains { $0["type"] as? String == "function_call_output"
            && $0["call_id"] as? String == "call_1" && $0["output"] as? String == "[reviewed listing]" } == true)
        assert(body["parallel_tool_calls"] as? Bool == false)
        let toolNames = (body["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        assert(!toolNames.contains("memory_search") && !toolNames.contains("read_skill"))
        assert(!runtime.followUp(prompt: "") && runtime.state == .completed)
        assert(runtime.followUp(prompt: "what next?") && runtime.state == .working)
        await wait { runtime.state == .completed }
        assert(runtime.messages.map(\.text) == ["inspect", "done", "what next?", "followed up"])
        assert(runtime.receipts.count == 1 && runtime.receipts.first?.sentToModel == "[reviewed listing]")
        let followUpBody = try jsonBody(await fixture.request(at: 2))
        let followUpInput = followUpBody["input"] as! [[String: Any]]
        assert(followUpInput.contains { $0["role"] as? String == "user"
            && (($0["content"] as? [[String: Any]])?.first?["text"] as? String) == "what next?" })
        assert(followUpInput.contains { $0["type"] as? String == "function_call_output"
            && $0["call_id"] as? String == "call_1" })
    }

    @MainActor
    private static func checkChat(_ root: URL) async throws {
        let fixture = FixtureTransport([
            #"{"choices":[{"finish_reason":"tool_calls","message":{"role":"assistant","content":null,"tool_calls":[{"id":"chat_1","type":"function","function":{"name":"run_command","arguments":"{\"executable\":\"/usr/bin/printf\",\"arguments\":[\"%s\",\"semi; $(never)\"],\"directory\":\".\"}"}}]}}]}"#,
            #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"read it"}}]}"#,
        ])
        let runtime = try NativeAgentRuntime(configuration: configuration(.chatCompletions), apiKey: "fixture", directory: root,
                                             transport: { request in try await fixture.send(request) })
        runtime.start(prompt: "read")
        await wait { runtime.pendingApproval?.phase == NativeAgentApproval.Phase.execute }
        runtime.approvePendingTool(runtime.pendingApproval!.id)
        await wait { runtime.pendingApproval?.phase == NativeAgentApproval.Phase.sendOutput }
        assert(runtime.receipts.first?.output == "semi; $(never)")
        runtime.approvePendingTool(runtime.pendingApproval!.id)
        await wait { runtime.state == NativeAgentRunState.completed }
        let body = try jsonBody(await fixture.request(at: 1))
        let messages = body["messages"] as? [[String: Any]]
        assert(messages?.contains { ($0["tool_calls"] as? [[String: Any]])?.first?["id"] as? String == "chat_1" } == true)
        assert(messages?.contains { $0["role"] as? String == "tool" && $0["tool_call_id"] as? String == "chat_1"
            && ($0["content"] as? String)?.contains("semi; $(never)\n\n[exit code: 0]") == true } == true)
        let definitions = body["tools"] as? [[String: Any]]
        let function = definitions?.first?["function"] as? [String: Any]
        assert(function?["type"] == nil && definitions?.first?["type"] as? String == "function")
    }

    private static func checkTools(_ root: URL) async throws {
        let tools = try NativeAgentTools(directory: root)
        let literal = root.appendingPathComponent("literal.txt")
        let command = NativeToolRequest(id: UUID(), callID: "literal", name: "run_command",
            invocation: .runCommand(executable: "/usr/bin/printf", arguments: ["%s", "$(touch escaped); two words"], directory: "."))
        let result = try await tools.execute(command)
        assert(result.output == "$(touch escaped); two words" && !FileManager.default.fileExists(atPath: literal.path))

        let highVolume = NativeToolRequest(id: UUID(), callID: "volume", name: "run_command",
            invocation: .runCommand(executable: "/usr/bin/seq", arguments: ["1", "100000"], directory: "."))
        let capped = try await tools.execute(highVolume)
        assert(capped.truncated && capped.output.utf8.count == NativeAgentTools.maximumOutputBytes)

        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("outside".utf8).write(to: outside)
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        await assertThrows { try await tools.execute(.init(id: UUID(), callID: "x", name: "read_file", invocation: .readFile(path: "escape"))) }

        let pidFile = root.appendingPathComponent("child.pid")
        let script = "sleep 30 & echo $! > \(pidFile.path); wait"
        let long = NativeToolRequest(id: UUID(), callID: "cancel", name: "run_command",
            invocation: .runCommand(executable: "/bin/sh", arguments: ["-c", script], directory: "."))
        let running = Task { try await tools.execute(long) }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: pidFile.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        running.cancel()
        await assertThrows { try await running.value }
        let pid = Int32((try String(contentsOf: pidFile, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines))!
        try await Task.sleep(for: .milliseconds(100))
        assert(kill(pid, 0) == -1 && errno == ESRCH)

        for _ in 0..<10 {
            let race = Task { try await tools.execute(.init(id: UUID(), callID: "race", name: "run_command",
                invocation: .runCommand(executable: "/bin/sleep", arguments: ["5"], directory: "."))) }
            race.cancel()
            await assertThrows { try await race.value }
        }
    }

    private static func checkExitedParentCleanup(_ root: URL) async throws {
        let tools = try NativeAgentTools(directory: root)
        let pidFile = root.appendingPathComponent("background.pid")
        let request = NativeToolRequest(id: UUID(), callID: "background", name: "run_command",
            invocation: .runCommand(executable: "/bin/sh",
                                    arguments: ["-c", "sleep 30 & echo $! > \(pidFile.path)"], directory: "."))
        _ = try await tools.execute(request)
        let pid = Int32((try String(contentsOf: pidFile, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines))!
        try await Task.sleep(for: .milliseconds(100))
        assert(kill(pid, 0) == -1 && errno == ESRCH)
    }

    @MainActor
    private static func checkRejectedCommand(_ root: URL) async throws {
        let marker = root.appendingPathComponent("must-not-exist").path
        let arguments = "{\"executable\":\"/usr/bin/touch\",\"arguments\":[\"\(marker)\"],\"directory\":\".\"}"
            .replacingOccurrences(of: "\"", with: "\\\"")
        let fixture = FixtureTransport([
            "{\"status\":\"completed\",\"error\":null,\"output\":[{\"type\":\"function_call\",\"id\":\"fc\",\"call_id\":\"reject\",\"name\":\"run_command\",\"arguments\":\"\(arguments)\",\"status\":\"completed\"}]}",
            #"{"status":"completed","error":null,"output":[{"type":"message","id":"msg","role":"assistant","status":"completed","content":[{"type":"output_text","text":"understood","annotations":[]}]}]}"#,
        ])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                                             transport: { request in try await fixture.send(request) })
        runtime.start(prompt: "touch it")
        await wait { runtime.pendingApproval?.phase == NativeAgentApproval.Phase.execute }
        assert(!FileManager.default.fileExists(atPath: marker))
        runtime.rejectPendingTool(runtime.pendingApproval!.id, reason: "No changes")
        await wait { runtime.state == NativeAgentRunState.completed }
        assert(!FileManager.default.fileExists(atPath: marker))
        assert(runtime.receipts.first?.sentToModel?.contains("not executed") == true)
    }

    @MainActor
    private static func checkStaleApproval(_ root: URL) async throws {
        let fixture = FixtureTransport([
            #"{"status":"completed","error":null,"output":[{"type":"function_call","id":"fc1","call_id":"one","name":"list_directory","arguments":"{\"path\":\".\"}","status":"completed"},{"type":"function_call","id":"fc2","call_id":"two","name":"list_directory","arguments":"{\"path\":\".\"}","status":"completed"}]}"#,
            #"{"status":"completed","error":null,"output":[{"type":"message","id":"msg","role":"assistant","status":"completed","content":[{"type":"output_text","text":"done","annotations":[]}]}]}"#,
        ])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                                             transport: { request in try await fixture.send(request) })
        runtime.start(prompt: "two calls")
        await wait { runtime.pendingApproval?.phase == NativeAgentApproval.Phase.execute }
        let staleID = runtime.pendingApproval!.id
        runtime.rejectPendingTool(staleID)
        let currentID = runtime.pendingApproval!.id
        assert(currentID != staleID)
        runtime.rejectPendingTool(staleID)
        assert(runtime.pendingApproval?.id == currentID)
        runtime.rejectPendingTool(currentID)
        await wait { runtime.state == NativeAgentRunState.completed }
    }

    @MainActor
    private static func checkRestartRace(_ root: URL) async throws {
        let fixture = RaceTransport()
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                                             transport: { request in try await fixture.send(request) })
        runtime.start(prompt: "old")
        for _ in 0..<100 where await !fixture.oldStarted { try await Task.sleep(for: .milliseconds(5)) }
        runtime.start(prompt: "new")
        await wait { runtime.state == NativeAgentRunState.completed }
        try await Task.sleep(for: .milliseconds(150))
        assert(runtime.state == .completed && runtime.messages.last?.text == "new answer")
    }

    @MainActor
    private static func checkMalformedTool(_ root: URL) async throws {
        let fixture = FixtureTransport([
            #"{"status":"completed","error":null,"output":[{"type":"function_call","id":"fc","call_id":"call","name":"delete_everything","arguments":"{}","status":"completed"}]}"#,
        ])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                                             transport: { request in try await fixture.send(request) })
        runtime.start(prompt: "bad")
        await wait { if case .failed = runtime.state { true } else { false } }
        assert(runtime.pendingApproval == nil && runtime.receipts.isEmpty)
    }

    @MainActor
    private static func checkFollowUpHistoryBound(_ root: URL) async throws {
        let fixture = FixtureTransport(Array(repeating: responseText("ok"), count: 10))
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                                             transport: { request in try await fixture.send(request) })
        assert(!runtime.start(prompt: String(repeating: "z", count: 100 * 1024)))
        assert(runtime.messages.isEmpty)
        let rejectedRequestCount = await fixture.count
        assert(rejectedRequestCount == 0)
        let largePrompt = String(repeating: "x", count: 12 * 1024)
        assert(runtime.start(prompt: largePrompt))
        await wait { runtime.state == .completed }
        var accepted = 0
        while runtime.followUp(prompt: largePrompt) {
            accepted += 1
            await wait { runtime.state == .completed }
        }
        assert(accepted > 0 && accepted < 9)
        assert(runtime.state == .completed && runtime.messages.last?.text.contains("Start a new chat") == true)
        let retainedCount = runtime.messages.count
        assert(!runtime.followUp(prompt: " \n") && runtime.messages.count == retainedCount && runtime.state == .completed)
    }

    private static func configuration(_ api: DirectAPI) -> DirectModelConfiguration {
        .init(baseURL: "http://127.0.0.1:9999/v1", model: "fixture", api: api, maxOutputTokens: 128)
    }

    @MainActor
    private static func checkMemoryAndSkillTools(_ root: URL) async throws {
        let memoryRoot = root.appendingPathComponent("native-memory")
        let store = try MemoryStore(root: memoryRoot, projectID: "fixture-project")
        let seed = try await store.propose(title: "Approval boundary", body: "Never apply a proposal without review.",
                                           kind: "constraint", source: "fixture")
        try await store.approve(seed.id)

        let skillDirectory = root.appendingPathComponent(".agents/skills/fixture-skill")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try Data("---\nname: fixture-skill\ndescription: A reviewed fixture skill.\n---\n\nSkill body marker.\n".utf8)
            .write(to: skillDirectory.appendingPathComponent("SKILL.md"))
        let reference = skillDirectory.appendingPathComponent("references/guide.md")
        try FileManager.default.createDirectory(at: reference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("Reviewed reference marker".utf8).write(to: reference)
        let snapshot = try AgentInstructions.discover(project: root, home: root.appendingPathComponent("empty-home"))
        let skillID = snapshot.skills.first { $0.name == "fixture-skill" }!.id

        let searchFixture = FixtureTransport([
            try responseCall(id: "memory-search", name: "memory_search", arguments: ["query": "approval"]),
            try responseCall(id: "memory-read", name: "memory_read", arguments: ["id": seed.pageID.uuidString]),
            responseText("searched"),
        ])
        let searchRuntime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            memoryStore: store, instructionContext: "Prefer concise answers.", agentName: "Fixture Agent",
            instructionSnapshot: snapshot, transport: { request in try await searchFixture.send(request) })
        searchRuntime.start(prompt: "find the boundary")
        try await approveOneTool(searchRuntime)
        await wait { searchRuntime.pendingApproval?.phase == .execute }
        try await approveOneTool(searchRuntime)
        await wait { searchRuntime.state == .completed }
        assert(searchRuntime.receipts.first?.output.contains(seed.pageID.uuidString.lowercased()) == true)
        assert(searchRuntime.receipts.last?.output.contains("Never apply a proposal without review.") == true)
        let firstBody = try jsonBody(await searchFixture.request(at: 0))
        let schemas = (firstBody["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        assert(schemas.contains("memory_search") && schemas.contains("memory_read") && schemas.contains("propose_recipe") && schemas.contains("read_skill"))
        let input = firstBody["input"] as! [[String: Any]]
        let systemText = (input[0]["content"] as! [[String: Any]])[0]["text"] as! String
        assert(systemText.contains("current direct request takes precedence") && systemText.contains(skillID)
               && systemText.contains("metadata only") && !systemText.contains("Skill body marker"))
        let reloaded = try MemoryStore(root: memoryRoot, projectID: "fixture-project")
        let reloadedReceipts = try await reloaded.receipts()
        assert(reloadedReceipts.first?.mechanism == "native")

        let readFixture = FixtureTransport([
            try responseCall(id: "skill-read", name: "read_skill", arguments: ["id": skillID]),
            try responseCall(id: "skill-reference", name: "read_skill", arguments: ["id": skillID, "path": "references/guide.md"]),
            try responseCall(id: "skill-null", name: "read_skill", arguments: ["id": skillID, "path": NSNull()]),
            responseText("read"),
        ])
        let readRuntime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            instructionSnapshot: snapshot, transport: { request in try await readFixture.send(request) })
        readRuntime.start(prompt: "read selected skill")
        for _ in 0..<3 { try await approveOneTool(readRuntime) }
        await wait { readRuntime.state == .completed }
        assert(readRuntime.receipts.first?.output.contains("Skill body marker") == true)
        assert(readRuntime.receipts.first?.output.contains("Resolved source: " + snapshot.skills.first { $0.id == skillID }!.resolvedPath) == true)

        assert(readRuntime.receipts[1].output.contains("Reviewed reference marker"))
        assert(readRuntime.receipts[1].request.reviewText.contains("references/guide.md"))
        assert(readRuntime.receipts[2].output.contains("Skill body marker"))
        let escapingFixture = FixtureTransport([
            try responseCall(id: "skill-escape", name: "read_skill", arguments: ["id": skillID, "path": "../outside"]),
        ])
        let escapingRuntime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            instructionSnapshot: snapshot, transport: { request in try await escapingFixture.send(request) })
        escapingRuntime.start(prompt: "invalid reference")
        await wait { if case .failed = escapingRuntime.state { true } else { false } }
        assert(escapingRuntime.pendingApproval == nil && escapingRuntime.receipts.isEmpty)

        let proposalFixture = FixtureTransport([
            try responseCall(id: "recipe", name: "propose_recipe", arguments: ["title": "Review safely", "body": "Keep the two phases."]),
            responseText("proposed"),
        ])
        let proposalRuntime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            memoryStore: store, agentName: "Fixture Agent", transport: { request in try await proposalFixture.send(request) })
        proposalRuntime.start(prompt: "stage a recipe")
        try await approveOneTool(proposalRuntime)
        await wait { proposalRuntime.state == .completed }
        let proposals = try await store.proposals()
        let recipe = proposals.first { $0.title == "Review safely" }
        assert(recipe?.status == "proposed" && recipe?.kind == "how-to")
        assert(recipe?.source.hasPrefix("native-agent:Fixture Agent:") == true)
        let approvedPages = try await store.pages()
        assert(approvedPages.count == 1)

        let tools = try NativeAgentTools(directory: root, memoryStore: store)
        let cancelledProposal = Task {
            try await tools.execute(.init(id: UUID(), callID: "cancelled-recipe", name: "propose_recipe",
                invocation: .proposeRecipe(title: "Cancelled recipe", body: "Must not be staged")))
        }
        cancelledProposal.cancel()
        do { _ = try await cancelledProposal.value; preconditionFailure("Cancelled recipe executed") } catch {}
        let cancelledStoreWrite = Task {
            try await store.propose(title: "Cancelled recipe", body: "Must not be staged", kind: "how-to", source: "fixture")
        }
        cancelledStoreWrite.cancel()
        do { _ = try await cancelledStoreWrite.value; preconditionFailure("Cancelled store write executed") } catch {}
        let afterCancellation = try await store.proposals()
        assert(!afterCancellation.contains { $0.title == "Cancelled recipe" })

        let scopedFixture = FixtureTransport([
            try responseCall(id: "scope", name: "memory_search", arguments: ["query": "approval", "project": "other"]),
        ])
        let scopedRuntime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            memoryStore: store, transport: { request in try await scopedFixture.send(request) })
        scopedRuntime.start(prompt: "switch projects")
        await wait { if case .failed = scopedRuntime.state { true } else { false } }
        assert(scopedRuntime.pendingApproval == nil)
    }

    @MainActor
    private static func approveOneTool(_ runtime: NativeAgentRuntime) async throws {
        await wait { runtime.pendingApproval?.phase == .execute }
        runtime.approvePendingTool(runtime.pendingApproval!.id)
        await wait { runtime.pendingApproval?.phase == .sendOutput }
        runtime.approvePendingTool(runtime.pendingApproval!.id)
    }

    private static func responseCall(id: String, name: String, arguments: [String: Any]) throws -> String {
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]), as: UTF8.self)
        let item: [String: Any] = ["type": "function_call", "id": "fc-\(id)", "call_id": id,
                                   "name": name, "arguments": encoded, "status": "completed"]
        return String(decoding: try JSONSerialization.data(withJSONObject: ["status": "completed", "error": NSNull(), "output": [item]]), as: UTF8.self)
    }

    private static func responseText(_ text: String) -> String {
        "{\"status\":\"completed\",\"error\":null,\"output\":[{\"type\":\"message\",\"id\":\"msg\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[{\"type\":\"output_text\",\"text\":\"\(text)\",\"annotations\":[]}]}]}"
    }

    @MainActor
    private static func wait(_ condition: () -> Bool) async {
        for _ in 0..<300 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Timed out waiting for runtime state")
    }

    private static func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    }

    private static func assertThrows(_ operation: () async throws -> Any) async {
        do { _ = try await operation(); preconditionFailure("Expected failure") } catch {}
    }
}

private actor FixtureTransport {
    private var responses: [String]
    private var requests: [URLRequest] = []
    init(_ responses: [String]) { self.responses = responses }
    var count: Int { requests.count }
    func request(at index: Int) -> URLRequest { requests[index] }
    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let body = responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        return (Data(body.utf8), response)
    }
}

private actor RaceTransport {
    private(set) var oldStarted = false
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let input = body["input"] as! [[String: Any]]
        let content = input.first?["content"] as! [[String: Any]]
        let prompt = content.first?["text"] as! String
        if prompt == "old" {
            oldStarted = true
            try? await Task.sleep(for: .milliseconds(100))
        }
        let text = prompt == "old" ? "old answer" : "new answer"
        let json = "{\"status\":\"completed\",\"error\":null,\"output\":[{\"type\":\"message\",\"id\":\"msg\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[{\"type\":\"output_text\",\"text\":\"\(text)\",\"annotations\":[]}]}]}"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        return (Data(json.utf8), response)
    }
}
