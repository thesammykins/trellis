import Foundation

@main
struct CodexSubscriptionCheck {
    @MainActor static func main() async throws {
        try await checkNativeTurns()
        try await checkApprovals()
        try await checkRestoreAndAccount()
        try await checkCancellationAndBudget()
        try await checkAccountChanges()
        try await checkDefaultAndReasoning()
        try await checkOwnedProcess()
        print("Codex subscription checks passed")
    }

    @MainActor private static func make(_ fixture: Fixture, limit: Int? = nil, threadID: String? = nil) -> CodexConversationRuntime {
        let client = CodexSubscriptionClient(executable: "/fixture", directory: URL(fileURLWithPath: "/tmp"), transport: fixture)
        return CodexConversationRuntime(executable: "/fixture", directory: URL(fileURLWithPath: "/tmp"),
                                         model: "fixture-model", reasoningEffort: "high", maximumTokens: limit, threadID: threadID, client: client)
    }

    @MainActor private static func checkNativeTurns() async throws {
        let fixture = Fixture(), runtime = make(fixture)
        assert(runtime.start(prompt: "first"))
        await wait { fixture.turns == 1 }
        fixture.usage(input: 10, output: 3)
        fixture.usage(input: 10, output: 3)
        fixture.emit("item/agentMessage/delta", ["itemId": "message-1", "delta": "Hello"])
        fixture.emit("item/completed", ["item": ["id": "message-1", "type": "agentMessage", "text": "Hello final"]])
        fixture.complete()
        await wait { runtime.state == .completed }
        assert(runtime.messages.last?.text == "Hello final")
        assert(runtime.usage?.inputTokens == 10 && runtime.usage?.outputTokens == 3)
        assert(runtime.budgetContext.contains("13 reported"))
        assert(runtime.followUp(prompt: "second"))
        await wait { fixture.turns == 2 }
        fixture.usage(input: 25, output: 7); fixture.complete()
        await wait { runtime.state == .completed }
        assert(runtime.budgetContext.contains("32 reported"))
        let thread = fixture.sent.first { $0["method"] as? String == "thread/start" }!["params"] as! [String: Any]
        assert(thread["modelProvider"] as? String == "openai" && thread["approvalPolicy"] as? String == "on-request")
        assert(thread["sandbox"] == nil && thread["config"] == nil && thread["dynamicTools"] == nil && thread["environments"] == nil)
        let turns = fixture.sent.filter { $0["method"] as? String == "turn/start" }
        let last = turns.last!["params"] as! [String: Any]
        let input = last["input"] as! [[String: Any]]
        assert(input.count == 1 && input[0]["text"] as? String == "second")
        assert(last["effort"] as? String == "high")
        assert(runtime.threadID == "thread-fixture" && runtime.turnCount == 2)
        assert(runtime.permissionSummary == "Workspace access · Approval on request")
        await runtime.cancelAndWait()
    }

    @MainActor private static func checkApprovals() async throws {
        let fixture = Fixture(), runtime = make(fixture)
        assert(runtime.start(prompt: "run")); await wait { fixture.turns == 1 }
        fixture.emit("item/started", ["item": ["id": "file-1", "type": "fileChange", "status": "inProgress",
            "changes": [["path": "/tmp/fixture.txt", "kind": ["type": "update"], "diff": "+review this exact text"]]]])
        fixture.approval(100, method: "item/fileChange/requestApproval", item: "file-1", extras: ["reason": "Save requested fixture"])
        fixture.approval(100, method: "item/fileChange/requestApproval", item: "file-1", extras: [:])
        let approval = runtime.pendingApproval!
        assert(approval.canApprove && approval.details.contains("+review this exact text") && approval.reason == "Save requested fixture")
        runtime.approve(id: UUID()); assert(fixture.responses.isEmpty)
        runtime.approve(id: approval.id); runtime.approve(id: approval.id)
        assert(fixture.responses.count == 1 && (fixture.responses[0]["result"] as? [String: Any])?["decision"] as? String == "accept")
        fixture.approval(101, method: "item/commandExecution/requestApproval", item: "command-1", extras: ["reason": "Missing command"])
        assert(runtime.pendingApproval?.canApprove == false)
        runtime.approve(id: runtime.pendingApproval!.id); assert(fixture.responses.count == 1)
        runtime.reject(id: runtime.pendingApproval!.id)
        assert(fixture.responses.count == 2)
        fixture.approval(102, method: "item/permissions/requestApproval", item: "permission-1", extras: ["permissions": ["network": ["enabled": true]]])
        assert((fixture.responses.last?["result"] as? [String: Any])?["permissions"] is [String: Any])
        assert(runtime.pendingApproval == nil && runtime.messages.last!.text.contains("No approval was granted"))
        fixture.complete(); await wait { runtime.state == .completed }
        await runtime.cancelAndWait()
    }

    @MainActor private static func checkRestoreAndAccount() async throws {
        let fixture = Fixture()
        fixture.history = [["id": "old-turn", "items": [
            ["id": "old-user", "type": "userMessage", "content": [["type": "text", "text": "original prompt"]]],
            ["id": "old-answer", "type": "agentMessage", "text": "native answer"]]]]
        fixture.resumeUsage = (1000, 100)
        let runtime = make(fixture, limit: 20, threadID: "thread-fixture")
        try await runtime.restore()
        assert(runtime.messages.map(\.text) == ["original prompt", "native answer"] && fixture.turns == 0)
        assert(runtime.budgetContext.contains("0 reported"))
        assert(runtime.followUp(prompt: "continue")); await wait { fixture.turns == 1 }
        fixture.usage(input: 1010, output: 103)
        fixture.complete(); await wait { runtime.state == .completed }
        assert(runtime.budgetContext.contains("13 reported"))
        await runtime.cancelAndWait()
        let wrongAccount = Fixture(); wrongAccount.accountType = "apiKey"
        let denied = make(wrongAccount)
        assert(denied.start(prompt: "must not send"))
        await wait { if case .failed = denied.state { true } else { false } }
        assert(wrongAccount.turns == 0 && !wrongAccount.sent.contains { $0["method"] as? String == "thread/start" })
        await denied.cancelAndWait()
    }

    @MainActor private static func checkCancellationAndBudget() async throws {
        let fixture = Fixture(), runtime = make(fixture, limit: 20)
        assert(runtime.start(prompt: "cancel")); await wait { fixture.turns == 1 }
        fixture.usage(input: 10, output: 2)
        fixture.approval(200, method: "item/commandExecution/requestApproval", item: "command-2", extras: ["command": "printf fixture", "cwd": "/tmp"])
        let approval = runtime.pendingApproval!
        await runtime.cancelAndWait()
        runtime.approve(id: approval.id)
        assert(runtime.state == .cancelled && fixture.closed)
        assert(fixture.responses.count == 1 && (fixture.responses[0]["result"] as? [String: Any])?["decision"] as? String == "cancel")
        assert(fixture.sent.contains { $0["method"] as? String == "turn/interrupt" })
        assert(runtime.budgetContext.contains("12 reported") && runtime.budgetContext.contains("unknown usage"))
        assert(!runtime.followUp(prompt: "unknown usage cannot bypass limit"))

        let budgetFixture = Fixture(), budget = make(budgetFixture, limit: 20)
        assert(budget.start(prompt: "budget")); await wait { budgetFixture.turns == 1 }
        budgetFixture.usage(input: 16, output: 5)
        budgetFixture.usage(input: 16, output: 5)
        assert(budgetFixture.sent.filter { $0["method"] as? String == "turn/interrupt" }.count == 1)
        budgetFixture.complete(status: "interrupted")
        await wait { if case .failed = budget.state { true } else { false } }
        assert(budget.budgetContext.contains("21 reported"))
        assert(!budget.followUp(prompt: "exhausted"))
        await budget.cancelAndWait()
    }

    @MainActor private static func checkAccountChanges() async throws {
        let fixture = Fixture(), runtime = make(fixture)
        assert(runtime.start(prompt: "subscription first")); await wait { fixture.turns == 1 }
        fixture.complete(); await wait { runtime.state == .completed }
        fixture.accountType = "apiKey"
        assert(runtime.followUp(prompt: "must not silently use API billing"))
        await wait { if case .failed = runtime.state { true } else { false } }
        assert(fixture.turns == 1 && fixture.closed)
        assert(fixture.sent.filter { $0["method"] as? String == "account/read" }.count == 2)
        await runtime.cancelAndWait()

        let logout = Fixture(), active = make(logout)
        assert(active.start(prompt: "active subscription")); await wait { logout.turns == 1 }
        logout.emit("account/updated", ["authMode": NSNull()])
        await wait { if case .failed = active.state { true } else { false } }
        assert(logout.closed && logout.sent.contains { $0["method"] as? String == "turn/interrupt" })
        await active.cancelAndWait()
    }

    @MainActor private static func checkDefaultAndReasoning() async throws {
        let fixture = Fixture()
        fixture.sandboxType = "futureMode"; fixture.approvalPolicy = "futurePolicy"
        let client = CodexSubscriptionClient(executable: "/fixture", directory: URL(fileURLWithPath: "/tmp"), transport: fixture)
        let runtime = CodexConversationRuntime(executable: "/fixture", directory: URL(fileURLWithPath: "/tmp"), model: "", client: client)
        assert(runtime.start(prompt: "agent default")); await wait { fixture.turns == 1 }
        assert(runtime.resolvedModel == "fixture-model")
        assert(runtime.permissionSummary == "Unknown access mode · Unknown approval policy")
        for method in ["thread/start", "turn/start"] {
            assert((fixture.sent.first { $0["method"] as? String == method }?["params"] as? [String: Any])?["model"] == nil)
        }
        fixture.complete(); await wait { runtime.state == .completed }
        await runtime.cancelAndWait()
        let invalid = Fixture()
        let invalidClient = CodexSubscriptionClient(executable: "/fixture", directory: URL(fileURLWithPath: "/tmp"), transport: invalid)
        let denied = CodexConversationRuntime(executable: "/fixture", directory: URL(fileURLWithPath: "/tmp"), model: "fixture-model", reasoningEffort: "invented", client: invalidClient)
        assert(denied.start(prompt: "unsupported reasoning"))
        await wait { if case .failed = denied.state { true } else { false } }
        assert(invalid.turns == 0)
        await denied.cancelAndWait()
    }

    @MainActor private static func checkOwnedProcess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-Codex-RPC-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("fixture")
        let python = """
        #!/usr/bin/python3
        import sys, json
        for line in sys.stdin:
            message=json.loads(line)
            if message.get('method')=='initialize': result={'userAgent':'fixture'}
            elif message.get('method')=='account/read': result={'account':{'type':'chatgpt','email':None,'planType':'pro'}}
            else: continue
            print(json.dumps({'id':message['id'],'result':result}),flush=True)
        """
        try Data(python.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let client = CodexSubscriptionClient(executable: script.path, directory: root)
        let account = try await client.account()
        assert(account == .chatGPT(email: nil, plan: "pro"))
        await client.close()
    }

    @MainActor private static func wait(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        preconditionFailure("Codex fixture timed out")
    }

    @MainActor private final class Fixture: CodexRPCTransport {
        var sent: [[String: Any]] = []
        var responses: [[String: Any]] { sent.filter { $0["method"] == nil } }
        var turns = 0
        var closed = false
        var accountType = "chatgpt"
        var sandboxType = "workspaceWrite"
        var approvalPolicy = "on-request"
        var history: [[String: Any]] = []
        var resumeUsage: (Int, Int)?
        private var receive: ((Data) -> Void)?
        func start(onMessage: @escaping @MainActor (Data) -> Void, onClose: @escaping @MainActor () -> Void) throws {
            closed = false; receive = onMessage
        }
        func send(_ data: Data) throws {
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            sent.append(object)
            guard let method = object["method"] as? String, let id = object["id"] else { return }
            let result: [String: Any]
            switch method {
            case "initialize": result = ["userAgent": "fixture"]
            case "account/read": result = ["account": ["type": accountType, "planType": "pro"]]
            case "thread/start", "thread/resume": result = ["thread": ["id": "thread-fixture", "turns": history], "modelProvider": "openai", "model": "fixture-model", "sandbox": ["type": sandboxType], "approvalPolicy": approvalPolicy]
            case "model/list": result = ["data": [["model": "fixture-model", "displayName": "Fixture", "supportedReasoningEfforts": [["reasoningEffort": "high"]], "defaultReasoningEffort": "high"]]]
            case "turn/start": turns += 1; result = ["turn": ["id": "turn-\(turns)", "status": "inProgress"]]
            case "turn/interrupt": result = [:]
            default: return
            }
            receive?(try JSONSerialization.data(withJSONObject: ["id": id, "result": result]))
            if method == "thread/resume", let resumeUsage { usage(input: resumeUsage.0, output: resumeUsage.1) }
        }
        func close() async { closed = true; receive = nil }
        func emit(_ method: String, _ params: [String: Any]) {
            var params = params; params["threadId"] = "thread-fixture"; params["turnId"] = "turn-\(turns)"
            receive?(try! JSONSerialization.data(withJSONObject: ["method": method, "params": params]))
        }
        func complete(status: String = "completed") { emit("turn/completed", ["turn": ["id": "turn-\(turns)", "status": status]]) }
        func usage(input: Int, output: Int) {
            emit("thread/tokenUsage/updated", ["tokenUsage": ["total": ["inputTokens": input, "outputTokens": output, "cachedInputTokens": 2, "reasoningOutputTokens": 1], "modelContextWindow": 32000]])
        }
        func approval(_ id: Int, method: String, item: String, extras: [String: Any]) {
            var params = extras; params["threadId"] = "thread-fixture"; params["turnId"] = "turn-\(turns)"; params["itemId"] = item
            receive?(try! JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params]))
        }
    }
}
