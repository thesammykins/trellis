import Darwin
import Foundation

@main
enum NativeAgentCheck {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: root.appendingPathComponent("note.txt"))

        try await checkSparseResponses(root)
        try await checkReasoningEffort(root)
        try await checkReusableTools(root)
        try await checkReviewedAppReads(root)
        try await checkTerminalSubmission(root)
        try await checkApprovalPolicies(root)
        try await checkDirectAssignments(root)
        try await checkDelegatedApprovals(root)
        try await checkDelegationReviewPolicies(root)
        try await checkDelegationBoundaries(root)
        try await checkRoleBudgets(root)
        try await checkUsageAndWireHistory(root)
        try await checkProviderReasoningDetails(root)
        try await checkTokenLimits(root)
        try checkStreamingDecoder()
        try await checkRecoveryAndReceipts(root)
        try await checkLiveStreaming(root)
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
    private static func checkTokenLimits(_ root: URL) async throws {
        for reportsUsage in [true, false] {
            var reply = try JSONSerialization.jsonObject(with: Data(responseText("Finished within one response").utf8)) as! [String: Any]
            if reportsUsage { reply["usage"] = ["input_tokens": 1_000, "output_tokens": 24] }
            let first = String(decoding: try JSONSerialization.data(withJSONObject: reply), as: UTF8.self)
            let fixture = FixtureTransport([first, responseText("Must not be requested")])
            var config = configuration(.responses)
            config.maxOutputTokens = 4_096
            let writer = AgentProfile(handle: "writer", name: "Writer", access: .textOnly)
            let runtime = try NativeAgentRuntime(configuration: config, apiKey: "fixture", directory: root,
                transport: { try await fixture.send($0) }, team: .init(profiles: [writer], maximumTokens: 1_024))
            assert(runtime.start(prompt: "Bound this work", assignedAgentID: writer.id))
            await wait { runtime.state == .completed }
            let body = try jsonBody(await fixture.request(at: 0))
            assert(body["max_output_tokens"] as? Int == 1_024)
            let wire = String(decoding: await fixture.request(at: 0).httpBody!, as: UTF8.self)
            assert(wire.contains("Token allowance 1024") && wire.contains("1024 remaining"))
            assert(runtime.followUp(prompt: "No budget left for this request"))
            await wait { if case .failed = runtime.state { return true }; return false }
            let count = await fixture.count
            assert(count == 1, "Descendant usage must stop further parent requests; missing usage is not zero")
            if case .failed(let reason) = runtime.state {
                assert(reason.contains(reportsUsage ? "token limit" : "did not report"))
            }
        }
    }

    @MainActor
    private static func checkDirectAssignments(_ root: URL) async throws {
        let writer = AgentProfile(handle: "writer", name: "Writer", instructions: "ROLE_MARKER", access: .textOnly)
        var team = AgentTeamConfiguration(profiles: [writer])
        let recipes = try ReusableAgentTools(root: root.appendingPathComponent("delegation-recipes"), projectID: "fixture", directory: root)
        let fixture = FixtureTransport([responseText("Direct result"), responseText("Parent answer"), responseText("Second result")])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            instructionContext: "PRIVATE_PARENT_CONTEXT", reusableTools: recipes, transport: { try await fixture.send($0) }, team: team)
        team.profiles[0].name = "Changed later"
        assert(runtime.start(prompt: "Write the explicit task", assignedAgentID: writer.id))
        await wait { runtime.state == .completed }
        assert(runtime.modelRequestCount == 0 && runtime.sharedModelRequestCount == 1 && runtime.sharedTaskCount == 1)
        assert(runtime.availableProfiles[0].name == "Writer" && runtime.delegations[0].child.displayName == "Writer")
        assert(runtime.receipts[0].state == .taskCompleted && runtime.receipts[0].sentToModel == nil)
        let childRequest = await fixture.request(at: 0)
        let childBody = try jsonBody(childRequest)
        let childWire = String(decoding: childRequest.httpBody!, as: UTF8.self)
        assert(childBody["tools"] == nil && childWire.contains("ROLE_MARKER") && childWire.contains("Write the explicit task"))
        assert(!childWire.contains("PRIVATE_PARENT_CONTEXT"))
        assert(!childWire.contains("run_saved_tool") && !childWire.contains("propose_saved_tool") && !childWire.contains("list_saved_tools"))
        assert(runtime.followUp(prompt: "PARENT_HISTORY_SECRET"))
        await wait { runtime.state == .completed }
        assert(runtime.followUp(prompt: "Second explicit task", assignedAgentID: writer.id))
        await wait { runtime.state == .completed }
        let secondChild = await fixture.request(at: 2)
        let secondWire = String(decoding: secondChild.httpBody!, as: UTF8.self)
        assert(!secondWire.contains("PARENT_HISTORY_SECRET") && !secondWire.contains("Direct result"))
        assert(runtime.sharedTaskCount == 2 && runtime.modelRequestCount == 1)

        var remote = writer
        remote.endpoint = "http://127.0.0.1:9998/v1"
        let keys = AppReadCounter()
        let remoteFixture = FixtureTransport([responseText("Remote result"), responseText("Again")])
        let remoteRuntime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "root-key", directory: root,
            transport: { try await remoteFixture.send($0) }, team: .init(profiles: [remote]),
            credentialResolver: { endpoint in assert(endpoint == remote.endpoint); keys.count += 1; return "role-key" })
        assert(remoteRuntime.start(prompt: "Exact reviewed task", assignedAgentID: remote.id))
        assert(remoteRuntime.pendingApproval?.phase == .execute && remoteRuntime.delegations.isEmpty && keys.count == 0)
        assert(remoteRuntime.pendingApproval!.request.reviewText.contains(remote.endpoint))
        let beforeReview = await remoteFixture.count
        assert(beforeReview == 0)
        remoteRuntime.approvePendingTool(remoteRuntime.pendingApproval!.id)
        await wait { remoteRuntime.state == .completed }
        let remoteRequest = await remoteFixture.request(at: 0)
        assert(remoteRequest.url?.port == 9998 && remoteRequest.value(forHTTPHeaderField: "Authorization") == "Bearer role-key")
        assert(keys.count == 1 && remoteRuntime.modelRequestCount == 0)
        assert(remoteRuntime.followUp(prompt: "Another reviewed task", assignedAgentID: remote.id))
        assert(remoteRuntime.pendingApproval?.phase == .execute)
        remoteRuntime.approvePendingTool(remoteRuntime.pendingApproval!.id)
        await wait { remoteRuntime.state == .completed }
        assert(keys.count == 1)
        assert(remoteRuntime.followUp(prompt: "Rejected remote task", assignedAgentID: remote.id))
        remoteRuntime.rejectPendingTool(remoteRuntime.pendingApproval!.id)
        assert(remoteRuntime.state == .completed && remoteRuntime.receipts.last?.state == .rejected)
        assert(remoteRuntime.receipts.last?.sentToModel == nil && remoteRuntime.sharedTaskCount == 2)
    }

    @MainActor
    private static func checkDelegatedApprovals(_ root: URL) async throws {
        let coding = AgentProfile(handle: "coding", name: "Coding", access: .reviewedTools)
        let fixture = FixtureTransport([
            try delegationCall("coding", task: "Inspect command output", context: "Explicit child context"),
            try responseCall(id: "child-command", name: "run_command", arguments: ["executable": "/usr/bin/printf", "arguments": ["child-output"], "directory": "."]),
            responseText("Child compact answer"), responseText("Parent final answer"),
        ])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            approvalPolicy: .scopedReadsAndOutput, transport: { try await fixture.send($0) }, team: .init(profiles: [coding]))
        runtime.start(prompt: "Delegate this work")
        await wait { runtime.approvalOwner?.pendingApproval?.request.name == "run_command" }
        let child = runtime.delegations[0].child
        assert(runtime.approvalOwner === child && runtime.pendingApproval?.phase == .execute)
        assert(child.receipts[0].output.isEmpty && !child.receipts[0].automaticallyExecuted)
        let approval = child.pendingApproval!.id
        runtime.approvePendingTool(approval)
        runtime.approvePendingTool(approval)
        await wait { runtime.approvalOwner?.pendingApproval?.phase == .sendOutput }
        assert(child.receipts[0].output == "child-output" && child.receipts[0].exitCode == 0)
        let beforeRelease = await fixture.count
        assert(beforeRelease == 2)
        runtime.approvePendingTool(child.pendingApproval!.id, outputForModel: "Reviewed child output")
        await wait { runtime.state == .completed }
        assert(child.receipts.count == 1 && child.receipts[0].sentToModel == "Reviewed child output\n\n[exit code: 0]")
        let parentRequest = await fixture.request(at: 3)
        let parentWire = String(decoding: parentRequest.httpBody!, as: UTF8.self)
        assert(parentWire.contains("Child compact answer") && !parentWire.contains("Reviewed child output"))
        assert(runtime.sharedTaskCount == 1 && runtime.sharedModelRequestCount == 4)
        assert(runtime.receipts[0].automaticallyExecuted && runtime.receipts[0].automaticallyReleased)

        let cancelledFixture = FixtureTransport([try responseCall(id: "cancel-child", name: "run_command",
            arguments: ["executable": "/usr/bin/printf", "arguments": ["must not run"], "directory": "."])])
        let cancelled = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            transport: { try await cancelledFixture.send($0) }, team: .init(profiles: [coding]))
        cancelled.start(prompt: "Cancel before child execution", assignedAgentID: coding.id)
        await wait { cancelled.approvalOwner?.pendingApproval?.phase == .execute }
        let cancelledChild = cancelled.delegations[0].child
        let staleID = cancelledChild.pendingApproval!.id
        cancelled.cancel()
        cancelled.approvePendingTool(staleID)
        try await Task.sleep(for: .milliseconds(30))
        assert(cancelled.state == .cancelled && cancelledChild.state == .cancelled && cancelled.approvalOwner == nil)
        assert(cancelledChild.receipts[0].output.isEmpty)
    }

    @MainActor
    private static func checkDelegationReviewPolicies(_ root: URL) async throws {
        let writer = AgentProfile(handle: "writer", name: "Writer", access: .textOnly)
        for policy in [NativeAgentApprovalPolicy.manual, .scopedReads] {
            let fixture = FixtureTransport([try delegationCall("writer"), responseText("Child result"), responseText("Parent result")])
            let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                approvalPolicy: policy, transport: { try await fixture.send($0) }, team: .init(profiles: [writer]))
            runtime.start(prompt: "Use the writer")
            if policy == .manual {
                await wait { runtime.pendingApproval?.phase == .execute }
                assert(runtime.delegations.isEmpty)
                runtime.approvePendingTool(runtime.pendingApproval!.id)
            }
            await wait { runtime.pendingApproval?.phase == .sendOutput }
            let count = await fixture.count
            assert(count == 2 && runtime.approvalOwner === runtime)
            assert(!runtime.receipts[0].automaticallyReleased)
            assert(runtime.receipts[0].automaticallyExecuted == (policy == .scopedReads))
            runtime.approvePendingTool(runtime.pendingApproval!.id, outputForModel: "Reviewed summary only")
            await wait { runtime.state == .completed }
            let last = await fixture.request(at: 2)
            let wire = String(decoding: last.httpBody!, as: UTF8.self)
            assert(wire.contains("Reviewed summary only") && !wire.contains("Child result"))
        }

        let coding = AgentProfile(handle: "coding", name: "Coding", access: .reviewedTools)
        var remote = writer
        remote.endpoint = "http://127.0.0.1:9998/v1"
        let fixture = FixtureTransport([try responseCall(id: "interrupted", name: "run_command",
            arguments: ["executable": "/usr/bin/printf", "arguments": ["must not run"], "directory": "."]), responseText("New task")])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            transport: { try await fixture.send($0) }, team: .init(profiles: [coding, remote]), credentialResolver: { _ in "role-key" })
        runtime.start(prompt: "First task", assignedAgentID: coding.id)
        await wait { runtime.approvalOwner?.pendingApproval?.phase == .execute }
        let oldChild = runtime.delegations[0].child
        let oldID = oldChild.pendingApproval!.id
        runtime.cancel()
        assert(runtime.followUp(prompt: "Replacement task", assignedAgentID: remote.id))
        let newID = runtime.pendingApproval!.id
        runtime.approvePendingTool(oldID)
        try await Task.sleep(for: .milliseconds(30))
        assert(runtime.pendingApproval?.id == newID && runtime.approvalOwner === runtime && oldChild.state == .cancelled)
        runtime.approvePendingTool(newID)
        await wait { runtime.state == .completed }
        assert(runtime.messages.last?.text.contains("New task") == true)
    }

    @MainActor
    private static func checkDelegationBoundaries(_ root: URL) async throws {
        var first = AgentProfile(handle: "first", name: "First", access: .textOnly)
        var second = AgentProfile(handle: "second", name: "Second", access: .projectRead)
        first.delegates = [second.id]
        second.escalation = first.id
        let cycleFixture = FixtureTransport([try delegationCall("second"), try delegationCall("first", kind: "escalate"), responseText("Cycle safely stopped")])
        let cycle = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            approvalPolicy: .scopedReadsAndOutput, transport: { try await cycleFixture.send($0) }, team: .init(profiles: [first, second]))
        cycle.start(prompt: "Check cycle", assignedAgentID: first.id)
        await wait { cycle.state == .completed }
        let child = cycle.delegations[0].child
        assert(child.delegations.count == 1 && child.delegations[0].child.delegations.isEmpty)
        if case .failed = child.delegations[0].child.state {} else { preconditionFailure("Ancestor cycle accepted") }
        assert(cycle.sharedTaskCount == 2 && cycle.sharedModelRequestCount == 3)
        let firstRequest = try jsonBody(await cycleFixture.request(at: 0))
        let delegationSchema = (firstRequest["tools"] as! [[String: Any]]).first { $0["name"] as? String == "delegate_task" }!
        let parameters = delegationSchema["parameters"] as! [String: Any]
        let properties = parameters["properties"] as! [String: Any]
        assert((properties["agent"] as! [String: Any])["enum"] as? [String] == ["second"])
        let firstInput = firstRequest["input"] as! [[String: Any]]
        let firstSystem = (firstInput[0]["content"] as! [[String: Any]])[0]["text"] as! String
        assert(firstSystem.contains("agent=\"second\", kind=\"delegate\""))

        let coding = AgentProfile(handle: "coding", name: "Coding", access: .reviewedTools)
        let explore = AgentProfile(handle: "explore", name: "Explore", access: .projectRead, escalation: coding.id)
        let escalationFixture = FixtureTransport([try delegationCall("coding", kind: "escalate"), responseText("Coding result"), responseText("Explore result")])
        let escalation = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            approvalPolicy: .scopedReadsAndOutput, transport: { try await escalationFixture.send($0) }, team: .init(profiles: [explore, coding]))
        escalation.start(prompt: "Escalate the task to Coding", assignedAgentID: explore.id)
        await wait { escalation.state == .completed }
        assert(escalation.delegations[0].child.delegations[0].kind == .escalate)
        assert(escalation.delegations[0].child.delegations[0].child.state == .completed && escalation.modelRequestCount == 0)
        let exploreBody = try jsonBody(await escalationFixture.request(at: 0))
        let exploreInput = exploreBody["input"] as! [[String: Any]]
        let exploreSystem = (exploreInput[0]["content"] as! [[String: Any]])[0]["text"] as! String
        assert(exploreSystem.contains("agent=\"coding\", kind=\"escalate\""))

        for limit in ["tasks", "depth", "requests"] {
            var team = AgentTeamConfiguration(profiles: [first, second])
            if limit == "tasks" { team.maximumTasks = 1 }
            if limit == "depth" { team.maximumDepth = 1 }
            if limit == "requests" { team.maximumModelRequests = 1 }
            let fixture = FixtureTransport([try delegationCall("second"), responseText("Budget reached")])
            let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                approvalPolicy: .scopedReadsAndOutput, transport: { try await fixture.send($0) }, team: team)
            runtime.start(prompt: "Bound this task", assignedAgentID: first.id)
            await wait { runtime.state == .completed }
            let count = await fixture.count
            assert(count == (limit == "requests" ? 1 : 2))
            assert(runtime.sharedTaskCount <= team.maximumTasks && runtime.sharedModelRequestCount <= team.maximumModelRequests)
            if limit != "requests" { assert(runtime.delegations[0].child.delegations.isEmpty) }
        }

        second.escalation = nil
        let restricted = AgentProfile(handle: "restricted", name: "Restricted", access: .textOnly)
        for handle in ["second", "restricted", "missing", "Second", "@second"] {
            let fixture = FixtureTransport([try delegationCall(handle)])
            let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                transport: { try await fixture.send($0) }, team: .init(profiles: [restricted, second]))
            runtime.start(prompt: "No allowed routes", assignedAgentID: restricted.id)
            await wait { runtime.state == .completed }
            assert(runtime.sharedTaskCount == 1 && runtime.delegations[0].child.delegations.isEmpty)
            if case .failed(let message) = runtime.delegations[0].child.state {
                if ["missing", "Second", "@second"].contains(handle) { assert(message.contains("Unknown or disabled agent handle")) }
                if handle == "restricted" { assert(message.contains("ancestor")) }
                if handle == "second" { assert(message.contains("not allowed to delegate or escalate")) }
            } else { preconditionFailure("Invalid route accepted") }
        }
        let forged = FixtureTransport([try responseCall(id: "forged", name: "read_file", arguments: ["path": "note.txt"])])
        let textOnly = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            approvalPolicy: .scopedReadsAndOutput, transport: { try await forged.send($0) }, team: .init(profiles: [restricted]))
        textOnly.start(prompt: "Text only", assignedAgentID: restricted.id)
        await wait { textOnly.state == .completed }
        assert(textOnly.delegations[0].child.receipts.isEmpty)
        let readTools = try NativeAgentTools(directory: root, access: .projectRead)
        let command = NativeToolRequest(id: UUID(), callID: "denied", name: "run_command", invocation: .runCommand(executable: "/usr/bin/true", arguments: [], directory: "."))
        await assertThrows { try await readTools.prepared(command) }
        await assertThrows { try await readTools.execute(command) }
        let escaped = NativeToolRequest(id: UUID(), callID: "escape", name: "read_file", invocation: .readFile(path: "../outside"))
        await assertThrows { try await readTools.prepared(escaped) }
    }

    @MainActor
    private static func checkUsageAndWireHistory(_ root: URL) async throws {
        var response = try JSONSerialization.jsonObject(with: Data(responseText("Usage answer").utf8)) as! [String: Any]
        response["usage"] = ["input_tokens": 100, "output_tokens": 12, "input_tokens_details": ["cached_tokens": 80]]
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
        let fixture = FixtureTransport([encoded, encoded])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            transport: { try await fixture.send($0) })
        runtime.start(prompt: "Usage")
        await wait { runtime.state == .completed }
        assert(runtime.usage == .init(inputTokens: 100, outputTokens: 12, cachedInputTokens: 80))
        assert(runtime.followUp(prompt: "Again"))
        await wait { runtime.state == .completed }
        assert(runtime.usage?.inputTokens == 200 && runtime.usageSamples == 2 && runtime.modelRequestCount == 2)
        let request = await fixture.request(at: 1)
        assert(runtime.requestBytes == request.httpBody!.count)

        let call: [String: Any] = ["id": "thinking-call", "type": "function", "function": ["name": "read_file", "arguments": "{\"path\":\"note.txt\"}"], "extra_content": ["google": ["thought_signature": "opaque-signature"]]]
        let chat: [String: Any] = ["choices": [["message": ["role": "assistant", "content": "", "reasoning_content": "PRIVATE_REASONING", "tool_calls": [call]], "finish_reason": "tool_calls"]], "usage": ["prompt_tokens": 30, "completion_tokens": 5]]
        let plainChat = "{\"choices\":[{\"message\":{\"content\":\"Done\"},\"finish_reason\":\"stop\"}]}"
        let chatFixture = FixtureTransport([String(decoding: try JSONSerialization.data(withJSONObject: chat), as: UTF8.self), plainChat, plainChat])
        let thinking = try NativeAgentRuntime(configuration: configuration(.chatCompletions), apiKey: "fixture", directory: root,
            approvalPolicy: .scopedReadsAndOutput, transport: { try await chatFixture.send($0) })
        thinking.start(prompt: "Read")
        await wait { thinking.state == .completed }
        let continuation = await chatFixture.request(at: 1)
        let wire = String(decoding: continuation.httpBody!, as: UTF8.self)
        assert(wire.contains("PRIVATE_REASONING") && wire.contains("opaque-signature"))
        assert(!thinking.messages.contains { $0.text.contains("PRIVATE_REASONING") } && thinking.usageSamples == 1)
        assert(thinking.followUp(prompt: "Continue the chat"))
        await wait { thinking.state == .completed }
        let followUp = try jsonBody(await chatFixture.request(at: 2))
        let retainedMessages = followUp["messages"] as! [[String: Any]]
        let plainAnswer = retainedMessages.first { $0["content"] as? String == "Done" }!
        assert(plainAnswer["tool_calls"] == nil)

        var decoder = NativeAgentStreamDecoder(api: .chatCompletions)
        let stream = "data: {\"choices\":[{\"delta\":{\"content\":\"Visible\",\"reasoning_content\":\"Hidden\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: {\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"prompt_tokens_details\":{\"cached_tokens\":8}}}\n\ndata: [DONE]\n\n"
        try decoder.append(Data(stream.utf8))
        let final = try JSONSerialization.jsonObject(with: decoder.finish()) as! [String: Any]
        assert(decoder.text == "Visible" && AgentModelUsage.parse(final, api: .chatCompletions) == .init(inputTokens: 10, outputTokens: 2, cachedInputTokens: 8))
    }

    @MainActor
    private static func checkProviderReasoningDetails(_ root: URL) async throws {
        let details: [[String: Any]] = [
            ["type": "reasoning.encrypted", "data": "PRIVATE_OPAQUE_CONTENT", "index": 0,
             "format": "fixture-v1", "provider_metadata": ["nested": [1, NSNull(), true]]],
            ["type": "reasoning.text", "text": "PRIVATE_OPAQUE_TEXT", "signature": "fixture-signature", "index": 1]
        ]
        let call = ["id": "details-call", "type": "function", "function": ["name": "read_file", "arguments": "{\"path\":\"note.txt\"}"]] as [String: Any]
        let response: [String: Any] = ["choices": [["message": ["role": "assistant", "content": "", "tool_calls": [call],
            "reasoning_details": details], "finish_reason": "tool_calls"]]]
        let plain = "{\"choices\":[{\"message\":{\"content\":\"Visible output\"},\"finish_reason\":\"stop\"}]}"
        let fixture = FixtureTransport([String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self), plain])
        let runtime = try NativeAgentRuntime(configuration: configuration(.chatCompletions), apiKey: "fixture", directory: root,
            approvalPolicy: .scopedReadsAndOutput, transport: { try await fixture.send($0) })
        runtime.start(prompt: "Read the fixture")
        await wait { runtime.state == .completed }
        let body = try jsonBody(await fixture.request(at: 1))
        let history = body["messages"] as! [[String: Any]]
        let replay = history.first { $0["reasoning_details"] != nil }!["reasoning_details"] as! [[String: Any]]
        assert(NSArray(array: replay).isEqual(to: details))
        assert(!runtime.messages.contains { $0.text.contains("PRIVATE_OPAQUE") || $0.text.contains("fixture-signature") })

        func chunk(_ value: Any) throws -> Data {
            let json: [String: Any] = ["choices": [["delta": ["reasoning_details": value], "finish_reason": NSNull()]]]
            return Data("data: ".utf8) + (try JSONSerialization.data(withJSONObject: json)) + Data("\n\n".utf8)
        }
        var decoder = NativeAgentStreamDecoder(api: .chatCompletions)
        try decoder.append(chunk([details[0]]))
        try decoder.append(chunk([details[1]]))
        try decoder.append(Data("data: {\"choices\":[{\"delta\":{\"content\":\"Visible\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8))
        let final = try JSONSerialization.jsonObject(with: decoder.finish()) as! [String: Any]
        let message = (final["choices"] as! [[String: Any]])[0]["message"] as! [String: Any]
        assert(NSArray(array: message["reasoning_details"] as! [[String: Any]]).isEqual(to: details))
        assert(decoder.text == "Visible")
        var malformed = NativeAgentStreamDecoder(api: .chatCompletions)
        do { try malformed.append(chunk(["wrong-shape"])); preconditionFailure("Malformed reasoning metadata accepted") }
        catch DirectModelError.invalidResponse { }
        var excessive = NativeAgentStreamDecoder(api: .chatCompletions)
        let part: [[String: Any]] = [["type": "reasoning.encrypted", "data": String(repeating: "x", count: 64 * 1024)]]
        try excessive.append(chunk(part))
        do { try excessive.append(chunk(part)); preconditionFailure("Cumulative reasoning metadata bound ignored") }
        catch DirectModelError.responseTooLarge { }
    }

    @MainActor
    private static func checkRoleBudgets(_ root: URL) async throws {
        var reader = AgentProfile(handle: "reader", name: "Reader", access: .projectRead, toolOutputBytes: 1_024)
        let recipes = try ReusableAgentTools(root: root.appendingPathComponent("reader-recipes"), projectID: "fixture", directory: root)
        let text = String(repeating: "🌳 context ", count: 1_000)
        try Data(text.utf8).write(to: root.appendingPathComponent("large-role-note.txt"))
        let fixture = FixtureTransport([try responseCall(id: "bounded-read", name: "read_file", arguments: ["path": "large-role-note.txt"]), responseText("Compact finding")])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            reusableTools: recipes, approvalPolicy: .scopedReadsAndOutput, transport: { try await fixture.send($0) },
            team: .init(profiles: [reader], maximumTasks: 1))
        runtime.start(prompt: "Read a bounded note", assignedAgentID: reader.id)
        await wait { runtime.state == .completed }
        let child = runtime.delegations[0].child
        let readerRequest = await fixture.request(at: 0)
        let readerWire = String(decoding: readerRequest.httpBody!, as: UTF8.self)
        assert(readerWire.contains("list_saved_tools") && !readerWire.contains("run_saved_tool") && !readerWire.contains("propose_saved_tool"))
        assert(child.receipts[0].output.utf8.count <= 1_024 && child.receipts[0].sentToModel!.utf8.count <= 1_024 && child.receipts[0].truncated)
        assert(runtime.followUp(prompt: "Second task exceeds the shared budget", assignedAgentID: reader.id))
        await wait { runtime.state == .completed }
        let count = await fixture.count
        assert(count == 2 && runtime.sharedTaskCount == 1 && runtime.delegations.count == 1)

        for limit in ["turns", "tools"] {
            reader.maxModelTurns = limit == "turns" ? 1 : 6
            reader.maxToolCalls = limit == "tools" ? 0 : 12
            let fixture = FixtureTransport([try responseCall(id: "role-limit", name: "read_file", arguments: ["path": "note.txt"])])
            let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                approvalPolicy: .scopedReadsAndOutput, transport: { try await fixture.send($0) }, team: .init(profiles: [reader]))
            runtime.start(prompt: "Bound the role", assignedAgentID: reader.id)
            await wait { runtime.state == .completed }
            let child = runtime.delegations[0].child
            if case .failed = child.state {} else { preconditionFailure("Role limit ignored") }
            assert(child.modelRequestCount == 1 && child.receipts.count == (limit == "tools" ? 0 : 1))
        }
        var disabled = reader
        disabled.enabled = false
        let unavailable = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            team: .init(profiles: [disabled]))
        assert(!unavailable.start(prompt: "Disabled assignment", assignedAgentID: disabled.id) && unavailable.sharedTaskCount == 0)

        reader.endpoint = "http://127.0.0.1:9998/v1"
        let noKeyFixture = FixtureTransport([])
        let noKey = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "must-not-fallback", directory: root,
            transport: { try await noKeyFixture.send($0) }, team: .init(profiles: [reader]), credentialResolver: { _ in "" })
        noKey.start(prompt: "No override credential", assignedAgentID: reader.id)
        assert(noKey.pendingApproval?.phase == .execute)
        noKey.approvePendingTool(noKey.pendingApproval!.id)
        await wait { noKey.state == .completed }
        let noKeyCount = await noKeyFixture.count
        assert(noKeyCount == 0 && noKey.delegations.isEmpty && noKey.messages.last!.text.contains("API key"))
    }

    private static func delegationCall(_ handle: String, task: String = "Bounded task", context: String = "", kind: String = "delegate") throws -> String {
        try responseCall(id: UUID().uuidString, name: "delegate_task", arguments: ["agent": handle, "task": task, "context": context, "kind": kind, "reason": "Use the configured specialist for this task."])
    }

    @MainActor
    private static func checkTerminalSubmission(_ root: URL) async throws {
        let probe = TerminalInjectionProbe()
        let command = "printf '%s' 'reviewed 👋'; pwd"
        let target = "Fixture shell · " + root.path
        let runner: NativeAgentTerminalRunner = { command in
            guard probe.available else { throw NativeAgentToolError.terminalUnavailable }
            probe.commands.append(command)
        }
        let tools = try NativeAgentTools(directory: root, terminalTarget: target, terminalRunner: runner)
        let request = NativeToolRequest(id: UUID(), callID: "terminal", name: "run_in_terminal",
            invocation: .runInTerminal(command: command), reason: "Show the current directory in the visible shell.")
        let unavailable = try NativeAgentTools(directory: root)
        await assertThrows { try await unavailable.prepared(request) }
        await assertThrows { try await tools.execute(request) }
        let prepared = try await tools.prepared(request)
        assert(prepared.reviewText.contains(target) && prepared.reviewText.contains(command) && prepared.reason == request.reason)
        let result = try await tools.execute(prepared)
        assert(probe.commands == [command] && result.exitCode == nil && result.output.contains("unknown"))
        await assertThrows { try await tools.execute(prepared) }
        await assertThrows { try await tools.execute(.init(id: UUID(), callID: "changed", name: "run_in_terminal",
            invocation: .runInTerminal(command: command, target: "A different terminal"))) }
        for invalid in ["", " ", "echo one\necho two", "echo\r", "echo\t", "\u{1b}[A", "a\u{2028}b", String(repeating: "a", count: 4_097)] {
            await assertThrows { try await tools.prepared(.init(id: UUID(), callID: "invalid", name: "run_in_terminal",
                invocation: .runInTerminal(command: invalid))) }
        }
        probe.available = false
        let stale = try await tools.prepared(.init(id: UUID(), callID: "stale", name: "run_in_terminal", invocation: .runInTerminal(command: command)))
        await assertThrows { try await tools.execute(stale) }
        probe.available = true
        await assertThrows { try await tools.execute(stale) }
        assert(probe.commands == [command])

        let fixture = FixtureTransport([
            try responseCall(id: "visible-shell", name: "run_in_terminal", arguments: ["command": command, "reason": request.reason!]),
            responseText("Submission acknowledged, completion remains unknown."),
        ])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            terminalTarget: target, terminalRunner: runner, approvalPolicy: .scopedReadsAndOutput,
            transport: { try await fixture.send($0) })
        runtime.start(prompt: "Run this in the terminal")
        await wait { runtime.pendingApproval?.phase == .execute }
        assert(probe.commands.count == 1 && runtime.pendingApproval?.request.reason == request.reason)
        let approvalID = runtime.pendingApproval!.id
        runtime.approvePendingTool(approvalID)
        runtime.approvePendingTool(approvalID)
        await wait { runtime.pendingApproval?.phase == .sendOutput }
        let beforeRelease = await fixture.count
        assert(probe.commands.count == 2 && beforeRelease == 1)
        assert(runtime.receipts[0].exitCode == nil && !runtime.receipts[0].automaticallyExecuted && !runtime.receipts[0].automaticallyReleased)
        runtime.approvePendingTool(runtime.pendingApproval!.id, outputForModel: "Submission reviewed; completion unknown.")
        await wait { runtime.state == .completed }
        assert(runtime.receipts[0].sentToModel == "Submission reviewed; completion unknown.")

        let cancelledFixture = FixtureTransport([try responseCall(id: "cancel", name: "run_in_terminal", arguments: ["command": command])])
        let cancelled = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            terminalTarget: target, terminalRunner: runner, transport: { try await cancelledFixture.send($0) })
        cancelled.start(prompt: "Cancel before injection")
        await wait { cancelled.pendingApproval?.phase == .execute }
        let cancelledID = cancelled.pendingApproval!.id
        cancelled.approvePendingTool(cancelledID)
        cancelled.cancel()
        cancelled.approvePendingTool(cancelledID)
        try await Task.sleep(for: .milliseconds(30))
        assert(probe.commands.count == 2 && cancelled.state == .cancelled && cancelled.pendingApproval == nil)
    }

    @MainActor
    private static func checkApprovalPolicies(_ root: URL) async throws {
        for policy in NativeAgentApprovalPolicy.allCases {
            let fixture = FixtureTransport([
                try responseCall(id: "read", name: "read_file", arguments: ["path": "note.txt", "reason": "Inspect the note requested by the user."]),
                responseText("The note says hello."),
            ])
            let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                approvalPolicy: policy, transport: { try await fixture.send($0) })
            runtime.start(prompt: "Read the note")
            if policy == .manual {
                await wait { runtime.pendingApproval?.phase == .execute }
                runtime.approvePendingTool(runtime.pendingApproval!.id)
            }
            if policy != .scopedReadsAndOutput {
                await wait { runtime.pendingApproval?.phase == .sendOutput }
                let count = await fixture.count
                assert(count == 1)
                runtime.approvePendingTool(runtime.pendingApproval!.id, outputForModel: "hello")
            }
            await wait { runtime.state == .completed }
            assert(runtime.approvalPolicy == policy && runtime.receipts.count == 1)
            assert(runtime.receipts[0].automaticallyExecuted == (policy != .manual))
            assert(runtime.receipts[0].automaticallyReleased == (policy == .scopedReadsAndOutput))
            assert(runtime.receipts[0].sentToModel == "hello")
            let payload = try jsonBody(await fixture.request(at: 0))
            for schema in payload["tools"] as! [[String: Any]] {
                let parameters = schema["parameters"] as! [String: Any]
                assert((parameters["required"] as! [String]).contains("reason"))
            }
        }
        let neverAutomatic: [NativeToolInvocation] = [
            .runCommand(executable: "/usr/bin/true", arguments: [], directory: "."), .runInTerminal(command: "true"),
            .readApp(.terminalContext), .readApp(.sessionInfo), .proposeRecipe(title: "Recipe", body: "proposal"),
            .proposeSavedTool(recipe: .init(name: "True", description: "Exit", executable: "/usr/bin/true", arguments: [], directory: "."), id: nil, baseHash: nil),
            .runSavedTool(id: UUID(), hash: "hash"),
        ]
        assert(neverAutomatic.allSatisfy { !$0.isScopedRead })
        let counter = AppReadCounter()
        let fixture = FixtureTransport([try responseCall(id: "app-read", name: "read_session_info", arguments: [:])])
        let appRead = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            appReader: { _ in counter.count += 1; return "session info" }, approvalPolicy: .scopedReadsAndOutput,
            transport: { try await fixture.send($0) })
        appRead.start(prompt: "Read session identity")
        await wait { appRead.pendingApproval?.phase == .execute }
        assert(counter.count == 0 && !appRead.receipts[0].automaticallyExecuted)
        appRead.cancel()
        for reason in [String(repeating: "a", count: 321), "hidden\nline", "\u{1b}[A", ""] {
            let invalid = FixtureTransport([try responseCall(id: "invalid-reason", name: "read_file", arguments: ["path": "note.txt", "reason": reason])])
            let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                approvalPolicy: .scopedReadsAndOutput, transport: { try await invalid.send($0) })
            runtime.start(prompt: "Invalid reason")
            await wait { if case .failed = runtime.state { true } else { false } }
            assert(runtime.receipts.isEmpty && runtime.pendingApproval == nil)
        }
    }

    @MainActor
    private static func checkSparseResponses(_ root: URL) async throws {
        func event(_ value: [String: Any]) throws -> String {
            "data: " + String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self) + "\n\n"
        }
        let text = "Hello! 👋\n\n```sh\nprintf hello\n```"
        let delta = try event(["type": "response.output_text.delta", "delta": text])
        let sparse = try event(["type": "response.completed", "response": ["status": "completed", "output": []]])
        let missing = try event(["type": "response.completed", "response": ["status": "completed"]])
        for terminal in [sparse, missing] {
            let stream = delta + terminal
            var decoder = NativeAgentStreamDecoder(api: .responses)
            for byte in stream.utf8 { try decoder.append(Data([byte])) }
            let object = try JSONSerialization.jsonObject(with: decoder.finish()) as! [String: Any]
            let items = object["output"] as! [[String: Any]]
            assert((items[0]["content"] as! [[String: Any]])[0]["text"] as? String == text)
            let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                transport: { request in (Data(stream.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                    httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!) })
            runtime.start(prompt: "Greeting with code")
            await wait { runtime.state == .completed }
            assert(runtime.messages.count == 2 && runtime.messages.last?.text == text)
        }
        let call: [String: Any] = ["id": "fc-sparse", "type": "function_call", "call_id": "sparse-call",
                                  "name": "list_directory", "arguments": "{\"path\":\".\"}", "status": "completed"]
        let added = try event(["type": "response.output_item.added", "output_index": 0,
                              "item": ["id": "fc-sparse", "type": "function_call", "call_id": "sparse-call", "name": "list_directory", "arguments": ""]])
        let done = try event(["type": "response.output_item.done", "output_index": 0, "item": call])
        let completeTool = added + done + sparse
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            transport: { request in (Data(completeTool.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!) })
        runtime.start(prompt: "Sparse finalized tool")
        await wait { runtime.pendingApproval?.phase == .execute }
        assert(runtime.receipts.count == 1 && runtime.receipts[0].output.isEmpty)
        runtime.cancel()
        var incomplete = NativeAgentStreamDecoder(api: .responses)
        try incomplete.append(Data((delta + added + sparse).utf8))
        do { _ = try incomplete.finish(); preconditionFailure("Discarded an unfinished tool call") } catch {}
        let full = try event(["type": "response.completed", "response": ["status": "completed", "output": [
            ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]]]]]])
        var notDuplicated = NativeAgentStreamDecoder(api: .responses)
        try notDuplicated.append(Data((delta + full).utf8))
        let fullObject = try JSONSerialization.jsonObject(with: notDuplicated.finish()) as! [String: Any]
        assert((fullObject["output"] as! [[String: Any]]).count == 1)
    }

    @MainActor
    private static func checkReasoningEffort(_ root: URL) async throws {
        for api in DirectAPI.allCases {
            let result = api == .responses ? responseText("fixture") : #"{"choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"fixture"}}]}"#
            let fixture = FixtureTransport([result])
            var route = configuration(api)
            route.reasoningEffort = "low"
            let runtime = try NativeAgentRuntime(configuration: route, apiKey: "fixture", directory: root,
                transport: { try await fixture.send($0) })
            runtime.start(prompt: "offline payload check")
            await wait { runtime.state == .completed }
            let payload = try jsonBody(await fixture.request(at: 0))
            if api == .responses {
                assert((payload["reasoning"] as? [String: String]) == ["effort": "low"] && payload["reasoning_effort"] == nil)
            } else { assert(payload["reasoning_effort"] as? String == "low" && payload["reasoning"] == nil) }
            route.reasoningEffort = "invalid"
            let invalid = try NativeAgentRuntime(configuration: route, apiKey: "fixture", directory: root,
                transport: { try await fixture.send($0) })
            invalid.start(prompt: "must not send")
            await wait { if case .failed = invalid.state { true } else { false } }
            let count = await fixture.count
            assert(count == 1)
        }
    }

    @MainActor
    private static func checkReusableTools(_ root: URL) async throws {
        let storage = root.appendingPathComponent("saved-tool-storage")
        let store = try ReusableAgentTools(root: storage, projectID: "fixture", directory: root)
        let tools = try NativeAgentTools(directory: root, reusableTools: store)
        let recipe = ReusableToolRecipe(name: "Literal greeting", description: "Print an exact argument.",
            executable: "/usr/bin/printf", arguments: ["%s", "semi; $(never) 👋"], directory: ".")
        let rejected = try await store.propose(recipe, source: "fixture")
        try await store.reject(rejected.id)
        let noTools = try await store.approved()
        assert(noTools.isEmpty)
        await assertThrows { try await tools.prepared(.init(id: UUID(), callID: "unapproved", name: "run_saved_tool",
            invocation: .runSavedTool(id: rejected.pageID, hash: String(repeating: "0", count: 64)))) }
        let proposal = try await store.propose(recipe, source: "fixture")
        try await store.approve(proposal)
        let saved = try await store.approved(proposal.pageID)
        assert(saved.revision == 1 && saved.recipe == recipe)
        let prepared = try await tools.prepared(.init(id: UUID(), callID: "approved", name: "run_saved_tool",
            invocation: .runSavedTool(id: saved.id, hash: saved.hash)))
        assert(prepared.reviewText.contains("Literal greeting") && prepared.reviewText.contains("semi; $(never)"))
        let output = try await tools.execute(prepared)
        assert(output.output == "semi; $(never) 👋")
        let changed = ReusableToolRecipe(name: "Improved greeting", description: "Print a revised exact argument.",
            executable: "/usr/bin/printf", arguments: ["%s", "version two"], directory: ".")
        let next = try await store.propose(changed, id: saved.id, baseHash: saved.hash, source: "fixture")
        let stale = try await store.propose(recipe, id: saved.id, baseHash: saved.hash, source: "fixture")
        try await store.approve(next)
        await assertThrows { try await tools.execute(prepared) }
        await assertThrows { try await store.approve(stale) }
        await assertThrows { try await store.propose(recipe, id: saved.id, baseHash: saved.hash, source: "fixture") }
        let current = try await store.approved(saved.id)
        assert(current.revision == 2 && current.recipe == changed)
        let forged = ApprovedReusableTool(id: current.id, revision: current.revision, hash: current.hash, recipe: recipe)
        await assertThrows { try await tools.execute(.init(id: UUID(), callID: "forged", name: "run_saved_tool",
            invocation: .runSavedTool(id: current.id, hash: current.hash, snapshot: forged))) }
        let other = root.appendingPathComponent("other-saved-scope")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await assertThrows { try NativeAgentTools(directory: other, reusableTools: store) }
        await assertThrows { try await store.propose(.init(name: "Escape", description: "Invalid directory",
            executable: "/usr/bin/printf", arguments: [], directory: "../"), source: "fixture") }
        let isolated = try ReusableAgentTools(root: storage, projectID: "other-project", directory: root)
        let isolatedTools = try await isolated.approved()
        assert(isolatedTools.isEmpty)
        let ordinary = try MemoryStore(root: storage, projectID: "fixture")
        let ordinaryPages = try await ordinary.pages()
        assert(ordinaryPages.isEmpty)

        // A changed review payload cannot be applied using the snapshot displayed to the user.
        let mutable = try await store.propose(recipe, source: "fixture")
        let enumerator = FileManager.default.enumerator(at: storage, includingPropertiesForKeys: nil)!
        let files = enumerator.allObjects.compactMap { $0 as? URL }
        let proposalFile = files.first { $0.lastPathComponent == mutable.id.uuidString.lowercased() + ".json" }!
        let replacement = MemoryProposal(id: mutable.id, title: changed.name, body: try changed.encoded(), kind: "how-to",
            source: mutable.source, pageID: mutable.pageID, baseHash: mutable.baseHash, status: mutable.status)
        try JSONEncoder().encode(replacement).write(to: proposalFile)
        await assertThrows { try await store.approve(mutable) }
        let pageFile = files.first { $0.lastPathComponent == current.id.uuidString.lowercased() + ".md" }!
        let pageBytes = try Data(contentsOf: pageFile)
        let edited = String(decoding: pageBytes, as: UTF8.self).replacingOccurrences(of: "version two", with: "UNREVIEWED")
        try Data(edited.utf8).write(to: pageFile)
        await assertThrows { try await store.approved(current.id) }
        try pageBytes.write(to: pageFile)

        // The agent's saved-tool route retains both independent approval boundaries.
        let fixture = FixtureTransport([
            try responseCall(id: "run-saved", name: "run_saved_tool", arguments: ["id": current.id.uuidString, "hash": current.hash]),
            responseText("saved tool finished"),
        ])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            reusableTools: store, transport: { try await fixture.send($0) })
        runtime.start(prompt: "Use the saved tool")
        await wait { runtime.pendingApproval?.phase == .execute }
        let before = await fixture.count
        assert(before == 1 && runtime.receipts.first?.output.isEmpty == true)
        runtime.approvePendingTool(runtime.pendingApproval!.id)
        await wait { runtime.pendingApproval?.phase == .sendOutput }
        assert(runtime.receipts.first?.output == "version two")
        let notReleased = await fixture.count
        assert(notReleased == 1)
        runtime.approvePendingTool(runtime.pendingApproval!.id, outputForModel: "reviewed")
        await wait { runtime.state == .completed }
        assert(runtime.receipts.first?.sentToModel == "reviewed\n\n[exit code: 0]")
        try await store.setEnabled(false, snapshot: current)
        let disabled = try await store.approved(current.id)
        assert(!disabled.recipe.enabled)
        await assertThrows { try await tools.prepared(.init(id: UUID(), callID: "disabled", name: "run_saved_tool",
            invocation: .runSavedTool(id: disabled.id, hash: disabled.hash))) }
        await assertThrows { try await store.setEnabled(true, snapshot: current) }
        try await store.setEnabled(true, snapshot: disabled)
        let enabled = try await store.approved(current.id)
        let enabledRequest = try await tools.prepared(.init(id: UUID(), callID: "enabled", name: "run_saved_tool",
            invocation: .runSavedTool(id: enabled.id, hash: enabled.hash)))
        let enabledResult = try await tools.execute(enabledRequest)
        assert(enabledResult.output == "version two")

        let proposalFixture = FixtureTransport([
            try responseCall(id: "propose-executable", name: "propose_saved_tool", arguments: ["id": NSNull(), "base_hash": NSNull(),
                "name": "Agent proposed", "description": "Exact command recipe", "executable": "/usr/bin/printf", "arguments": ["%s", "proposal only"], "directory": "."]),
            responseText("proposal staged"),
        ])
        let proposing = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            reusableTools: isolated, transport: { try await proposalFixture.send($0) })
        proposing.start(prompt: "Create a reusable tool")
        await wait { proposing.pendingApproval?.phase == .execute }
        let beforeProposal = try await isolated.proposals()
        assert(beforeProposal.isEmpty)
        proposing.approvePendingTool(proposing.pendingApproval!.id)
        await wait { proposing.pendingApproval?.phase == .sendOutput }
        let proposedTools = try await isolated.proposals()
        let autoApproved = try await isolated.approved()
        assert(proposedTools.count == 1 && proposedTools[0].status == "proposed" && autoApproved.isEmpty)
        proposing.rejectPendingTool(proposing.pendingApproval!.id)
        await wait { proposing.state == .completed }
    }

    @MainActor
    private static func checkReviewedAppReads(_ root: URL) async throws {
        let counter = AppReadCounter()
        let fixture = FixtureTransport([
            try responseCall(id: "viewport", name: "read_terminal_context", arguments: [:]), responseText("read"),
        ])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
            appReader: { kind in
                counter.count += 1
                return kind == .terminalContext ? "explicit viewport" : "session info"
            }, transport: { try await fixture.send($0) })
        runtime.start(prompt: "Read this terminal")
        await wait { runtime.pendingApproval?.phase == .execute }
        assert(counter.count == 0)
        runtime.approvePendingTool(runtime.pendingApproval!.id)
        await wait { runtime.pendingApproval?.phase == .sendOutput }
        assert(counter.count == 1 && runtime.receipts.first?.output == "explicit viewport")
        let beforeRelease = await fixture.count
        assert(beforeRelease == 1)
        runtime.rejectPendingTool(runtime.pendingApproval!.id)
        await wait { runtime.state == .completed }
        assert(runtime.receipts.first?.state == .outputWithheld)
        let closed = try NativeAgentTools(directory: root, appReader: { _ in throw NativeAgentToolError.appContextUnavailable })
        await assertThrows { try await closed.execute(.init(id: UUID(), callID: "closed", name: "read_terminal_context",
            invocation: .readApp(.terminalContext))) }
    }

    private static func checkStreamingDecoder() throws {
        func decode(_ source: String, api: DirectAPI) throws -> [String: Any] {
            var decoder = NativeAgentStreamDecoder(api: api)
            // Every byte is a transport boundary, including the middle of the emoji and CRLF.
            for byte in source.utf8 { try decoder.append(Data([byte])) }
            return try JSONSerialization.jsonObject(with: decoder.finish()) as! [String: Any]
        }
        let completed = responseText("Hello 👋")
        let response = "event: ignored\r\ndata: {\"type\":\"future.event\"}\r\n\r\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello 👋\"}\n\ndata: {\"type\":\"response.completed\",\"response\":\(completed)}\n\n"
        let responseObject = try decode(response, api: .responses)
        assert(responseObject["status"] as? String == "completed")
        let chunks: [[String: Any]] = [
            ["choices": [["index": 0, "delta": ["content": "Hello 👋", "tool_calls": [["index": 0, "id": "call-1", "type": "function", "function": ["name": "list_directory", "arguments": "{\"pa"]]]]]]],
            ["choices": [["index": 0, "delta": ["tool_calls": [["index": 0, "function": ["arguments": "th\":\".\"}"]]]], "finish_reason": "tool_calls"]]],
        ]
        let chat = try chunks.map { "data: " + String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) + "\n\n" }.joined() + "data: [DONE]\n\n"
        let parsed = try decode(chat, api: .chatCompletions)
        let message = (parsed["choices"] as! [[String: Any]])[0]["message"] as! [String: Any]
        assert(message["content"] as? String == "Hello 👋")
        let function = (message["tool_calls"] as! [[String: Any]])[0]["function"] as! [String: Any]
        assert(function["arguments"] as? String == "{\"path\":\".\"}")
        for source in ["data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n", "data: {", "data: {\"type\":\"response.failed\"}\n\n"] {
            do { _ = try decode(source, api: .responses); preconditionFailure("Accepted incomplete stream") } catch {}
        }
        var bounded = NativeAgentStreamDecoder(api: .responses)
        do { try bounded.append(Data(repeating: 120, count: 2 * 1024 * 1024 + 1)); preconditionFailure("Accepted oversized stream") } catch {}
    }

    @MainActor
    private static func checkRecoveryAndReceipts(_ root: URL) async throws {
        let fixture = FixtureTransport([
            try responseCall(id: "one", name: "read_file", arguments: ["path": "note.txt"]), responseText("one"),
            try responseCall(id: "two", name: "read_file", arguments: ["path": "note.txt"]), responseText("two"),
            try responseCall(id: "three", name: "read_file", arguments: ["path": "note.txt"]), responseText("recovered"),
        ])
        let runtime = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                                             transport: { request in try await fixture.send(request) })
        runtime.start(prompt: "first")
        await wait { runtime.pendingApproval?.phase == .execute }
        assert(runtime.receipts.first?.state == .waitingApproval)
        runtime.approvePendingTool(runtime.pendingApproval!.id)
        await wait { runtime.pendingApproval?.phase == .sendOutput }
        runtime.rejectPendingTool(runtime.pendingApproval!.id)
        await wait { runtime.state == .completed }
        assert(runtime.receipts[0].state == .outputWithheld && runtime.receipts[0].output == "hello")
        assert(runtime.receipts[0].sentToModel?.contains("hello") == false)
        assert(runtime.followUp(prompt: "second"))
        await wait { runtime.pendingApproval?.phase == .execute }
        runtime.rejectPendingTool(runtime.pendingApproval!.id)
        await wait { runtime.state == .completed }
        assert(runtime.receipts[1].messageID == runtime.messages.first { $0.text == "second" }?.id)
        assert(runtime.followUp(prompt: "third"))
        await wait { runtime.pendingApproval?.phase == .execute }
        let stale = runtime.pendingApproval!.id
        runtime.cancel()
        assert(runtime.canFollowUp && runtime.receipts[2].state == .cancelled)
        runtime.approvePendingTool(stale)
        assert(runtime.pendingApproval == nil)
        assert(runtime.followUp(prompt: "continue explicitly"))
        await wait { runtime.state == .completed }
        assert(runtime.messages.first?.text == "first" && runtime.messages.last?.text == "recovered")
        let count = await fixture.count
        assert(count == 6)
        let failures = FixtureTransport(["invalid-json", responseText("explicit recovery")])
        let failed = try NativeAgentRuntime(configuration: configuration(.responses), apiKey: "fixture", directory: root,
                                            transport: { try await failures.send($0) })
        failed.start(prompt: "keep this question")
        await wait { if case .failed = failed.state { true } else { false } }
        assert(failed.canFollowUp && failed.messages.first?.text == "keep this question")
        assert(failed.followUp(prompt: "continue after failure"))
        await wait { failed.state == .completed }
        assert(failed.messages.last?.text == "explicit recovery")
    }

    @MainActor
    private static func checkLiveStreaming(_ root: URL) async throws {
        guard let endpoint = ProcessInfo.processInfo.environment["TRELLIS_STREAM_FIXTURE_URL"] else { return }
        for api in [DirectAPI.responses, .chatCompletions] {
            let config = DirectModelConfiguration(baseURL: endpoint, model: "trellis-fixture", api: api, maxOutputTokens: 1024)
            let keepAlive = try NativeAgentRuntime(configuration: config, apiKey: "fixture-only", directory: root)
            let began = Date()
            keepAlive.start(prompt: "STREAM_KEEPALIVE_FIXTURE")
            await wait { keepAlive.state == .completed }
            assert(Date().timeIntervalSince(began) < 2 && keepAlive.messages.last?.text == "Hello 👋")
            let runtime = try NativeAgentRuntime(configuration: config, apiKey: "fixture-only", directory: root)
            runtime.start(prompt: "STREAM_TEXT_FIXTURE")
            await wait { runtime.state == .working && runtime.messages.contains { $0.role == .assistant && !$0.text.isEmpty } }
            let firstID = runtime.messages.last!.id
            await wait { runtime.state == .completed }
            assert(runtime.messages.count == 2 && runtime.messages.last?.id == firstID)
            assert(runtime.messages.last?.text.contains("👋") == true)
            runtime.start(prompt: "STREAM_TEXT_FIXTURE")
            await wait { runtime.messages.contains { $0.role == .assistant } }
            runtime.cancel()
            let text = runtime.messages.last?.text
            try await Task.sleep(for: .milliseconds(300))
            assert(runtime.state == .cancelled && runtime.messages.last?.text == text)
            assert(runtime.messages.last?.interruption == "Stopped")
            assert(runtime.followUp(prompt: "STREAM_KEEPALIVE_FIXTURE"))
            await wait { runtime.state == .completed }
            assert(runtime.messages.contains { $0.text == text && $0.interruption == "Stopped" })
            let failedStream = try NativeAgentRuntime(configuration: config, apiKey: "fixture-only", directory: root)
            failedStream.start(prompt: "STREAM_FAIL_FIXTURE")
            await wait { if case .failed = failedStream.state { return true }; return false }
            let partial = failedStream.messages.last!
            precondition(partial.role == .assistant && partial.interruption == "Incomplete", "Partial state: \(failedStream.state), messages: \(failedStream.messages)")
            assert(failedStream.followUp(prompt: "STREAM_KEEPALIVE_FIXTURE"))
            await wait { failedStream.state == .completed }
            assert(failedStream.messages.first { $0.id == partial.id } == partial)
            let fixtureDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build-support/ux9-fixture")
            let toolRuntime = try NativeAgentRuntime(configuration: config, apiKey: "fixture-only", directory: fixtureDirectory)
            toolRuntime.start(prompt: "inspect the fixture")
            try await Task.sleep(for: .milliseconds(100))
            assert(toolRuntime.pendingApproval == nil && toolRuntime.receipts.isEmpty)
            await wait { toolRuntime.pendingApproval?.phase == .execute }
            let approval = toolRuntime.pendingApproval!.id
            toolRuntime.rejectPendingTool(approval)
            toolRuntime.approvePendingTool(approval)
            await wait { toolRuntime.state == .completed }
            assert(toolRuntime.receipts.count == 1 && toolRuntime.receipts[0].state == .rejected)
        }
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
        assert(runtime.receipts.first?.state == .awaitingOutputReview)
        assert(runtime.receipts.first?.messageID == runtime.messages.first?.id)
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
        assert(body["parallel_tool_calls"] as? Bool == false && body["stream"] as? Bool == true)
        assert(runtime.receipts.first?.state == .reviewedOutputSent)
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
        let filesystemTools = try NativeAgentTools(directory: URL(fileURLWithPath: "/"))
        let rootRead = try await filesystemTools.prepared(.init(id: UUID(), callID: "root-read", name: "read_file",
            invocation: .readFile(path: root.appendingPathComponent("note.txt").path)))
        let rootResult = try await filesystemTools.execute(rootRead)
        assert(rootResult.output == "hello", "A root-scoped conversation can read its descendant fixture")
        let rootSearch = try await filesystemTools.execute(.init(id: UUID(), callID: "root-search", name: "find_files",
            invocation: .findFiles(query: "note.txt", path: root.path)))
        let expectedPath = String(root.appendingPathComponent("note.txt").standardizedFileURL.path.dropFirst())
        assert(rootSearch.output.split(separator: "\n").contains(Substring(expectedPath)), "Expected \(expectedPath); received \(rootSearch.output)")
        let scopedSearch = try await tools.execute(.init(id: UUID(), callID: "scoped-search", name: "find_files",
            invocation: .findFiles(query: "note.txt", path: ".")))
        assert(scopedSearch.output.split(separator: "\n").contains("note.txt"), "Search keeps the same normalized folder scope as file reads")
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
        assert(runtime.receipts.first?.state == .rejected)
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
        for _ in 0..<9 {
            assert(runtime.followUp(prompt: largePrompt))
            await wait { runtime.state == .completed }
        }
        assert(runtime.omittedContextTurns > 0 && runtime.requestBytes < 128 * 1024)
        assert(!runtime.followUp(prompt: String(repeating: "z", count: 100 * 1024)))
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

    private static func assertThrows(isolation: isolated (any Actor)? = #isolation, _ operation: () async throws -> Any) async {
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
        let content = input.last?["content"] as! [[String: Any]]
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

@MainActor
private final class AppReadCounter { var count = 0 }

@MainActor
private final class TerminalInjectionProbe {
    var commands: [String] = []
    var available = true
}
