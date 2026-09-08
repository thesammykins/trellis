import Combine
import Foundation

struct CodexApproval: Identifiable, Equatable {
    enum Kind: String { case command, fileChange }
    let id: UUID
    let kind: Kind
    let title: String
    let summary: String
    let details: String
    let reason: String?
    let canApprove: Bool
}

struct CodexActivity: Identifiable, Equatable {
    let id: String
    var title: String
    var detail: String
    var status: String
}

/// The Codex harness owns its tools, context, output sharing and native history.
/// Trellis renders public events and responds only to explicit, supported approval requests.
@MainActor
final class CodexConversationRuntime: ObservableObject {
    @Published private(set) var state: NativeAgentRunState = .idle
    @Published private(set) var messages: [NativeAgentMessage] = []
    @Published private(set) var activities: [CodexActivity] = []
    @Published private(set) var pendingApproval: CodexApproval?
    @Published private(set) var usage: AgentModelUsage?
    @Published private(set) var turnCount = 0
    @Published private(set) var contextWindow: Int?
    @Published private(set) var threadID: String?
    @Published private(set) var resolvedModel: String?
    @Published private(set) var permissionSummary = "Codex access settings not yet reported"
    let model: String
    let reasoningEffort: String?
    var budgetContext: String { tokenBudget.context.replacingOccurrences(of: "requests have unknown usage", with: "native turns have unknown usage") }
    var canFollowUp: Bool {
        guard threadID != nil, task == nil, cleanupTask == nil else { return false }
        switch state { case .idle, .completed, .cancelled, .failed: return true; default: return false }
    }

    private let client: CodexSubscriptionClient
    private let directory: URL
    private var tokenBudget: AgentTokenBudget
    private var task: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var connectedThread = false
    private var restoring = false
    private var activeTurns: [String: String] = [:]
    private var runID = UUID()
    private var activeTurnID: String?
    private var submitted = false
    private var sawUsage = false
    private var recordedUnknownUsage = false
    private var turnCompletion: CheckedContinuation<Void, Error>?
    private var completedTurn: Result<Void, Error>?
    private var budgetStop: String?
    private var itemMessages: [String: UUID] = [:]
    private var items: [String: [String: Any]] = [:]
    private var allowedThreads = Set<String>()
    private var seenRequests = Set<CodexRequestID>()
    private var approvals: [(CodexApproval, CodexRequestID)] = []

    init(executable: String, directory: URL, model: String, reasoningEffort: String? = nil,
         maximumTokens: Int? = nil, threadID: String? = nil, client: CodexSubscriptionClient? = nil) {
        self.directory = directory
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.threadID = threadID
        self.tokenBudget = AgentTokenBudget(limit: maximumTokens)
        self.client = client ?? CodexSubscriptionClient(executable: executable, directory: directory)
        self.client.onEvent = { [weak self] method, params in self?.event(method, params) }
        self.client.onServerRequest = { [weak self] id, method, params in self?.request(id, method, params) }
        self.client.onDisconnect = { [weak self] in
            guard let self else { return }
            self.connectedThread = false
            if self.submitted { self.finishTurn(.failure(CodexClientError.disconnected)) }
        }
    }

    /// Reattaches to persisted Codex history. It does not replay a prompt or start a turn.
    func restore() async throws {
        guard task == nil, cleanupTask == nil, !submitted, !restoring else { return }
        restoring = true; state = .working
        let id = runID
        defer { restoring = false }
        do {
            try await prepareThread()
            if id == runID { state = .completed }
        } catch {
            if id == runID { state = .failed(error.localizedDescription) }
            throw error
        }
    }

    @discardableResult
    func start(prompt: String) -> Bool { submit(prompt) }

    @discardableResult
    func followUp(prompt: String) -> Bool {
        guard canFollowUp else { return false }
        return submit(prompt)
    }

    private func submit(_ prompt: String) -> Bool {
        guard task == nil, cleanupTask == nil, !submitted, !restoring,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              prompt.utf8.count <= 128 * 1024, !prompt.utf8.contains(0) else { return false }
        do { try tokenBudget.checkBeforeRequest() }
        catch { state = .failed(error.localizedDescription); return false }
        runID = UUID(); let id = runID
        state = .working
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.prepareThread()
                try Task.checkCancellation()
                guard id == self.runID, let threadID = self.threadID else { return }
                self.messages.append(.init(id: UUID(), role: .user, text: prompt))
                self.trimTranscript()
                self.submitted = true; self.sawUsage = false; self.recordedUnknownUsage = false; self.budgetStop = nil
                self.activeTurnID = nil; self.completedTurn = nil
                var params: [String: Any] = ["threadId": threadID, "input": [["type": "text", "text": prompt]],
                                             "approvalPolicy": "on-request", "approvalsReviewer": "user"]
                if !self.model.isEmpty { params["model"] = self.model }
                if let effort = self.reasoningEffort { params["effort"] = effort }
                if self.tokenBudget.limit != nil {
                    params["additionalContext"] = [["kind": "application", "value": self.tokenBudget.context]]
                }
                self.turnCount += 1
                let response = try await self.client.request("turn/start", params)
                guard let turn = response["turn"] as? [String: Any], let turnID = turn["id"] as? String else {
                    throw CodexClientError.invalidMessage
                }
                self.activeTurnID = turnID
                self.activeTurns[threadID] = turnID
                if let result = self.completedTurn { try result.get() }
                else { try await withCheckedThrowingContinuation { self.turnCompletion = $0 } }
                if id == self.runID { self.state = .completed }
            } catch is CancellationError {
                if id == self.runID { self.state = .cancelled; await self.closeFailedTurn() }
            } catch {
                if id == self.runID { self.state = .failed(error.localizedDescription); await self.closeFailedTurn() }
            }
            if id == self.runID {
                self.recordUnreportedTurn()
                self.submitted = false; self.task = nil; self.clearApprovals()
            }
        }
        return true
    }

    func approve(id: UUID) { decide(id, accepted: true) }
    func reject(id: UUID) { decide(id, accepted: false) }

    private func decide(_ id: UUID, accepted: Bool) {
        guard let (approval, requestID) = approvals.first, approval.id == id,
              !accepted || approval.canApprove else { return }
        do { try client.respond(requestID, result: ["decision": accepted ? "accept" : "decline"]) }
        catch { finishTurn(.failure(error)); return }
        approvals.removeFirst()
        pendingApproval = approvals.first?.0
        state = pendingApproval == nil ? .working : .waitingApproval
    }

    func cancel() {
        guard cleanupTask == nil else { return }
        runID = UUID()
        let ownedTask = task
        task?.cancel(); task = nil
        if let threadID, let activeTurnID { client.interrupt(threadID: threadID, turnID: activeTurnID) }
        for (_, id) in approvals { try? client.respond(id, result: ["decision": "cancel"]) }
        clearApprovals()
        recordInterruptedTurn(); submitted = false
        finishTurn(.failure(CancellationError()))
        connectedThread = false
        if state != .idle && state != .completed { state = .cancelled }
        cleanupTask = Task { [weak self, client] in
            await client.close()
            await ownedTask?.value
            self?.cleanupTask = nil
        }
    }

    func cancelAndWait() async {
        cancel()
        await cleanupTask?.value
    }

    private func closeFailedTurn() async {
        recordInterruptedTurn()
        if let threadID, let activeTurnID { client.interrupt(threadID: threadID, turnID: activeTurnID) }
        for (_, id) in approvals { try? client.respond(id, result: ["decision": "cancel"]) }
        clearApprovals()
        connectedThread = false
        await client.close()
    }

    private func prepareThread() async throws {
        // Codex authentication can change while a conversation is idle. Recheck the native
        // account before every submitted turn; never reinterpret an API key as a subscription.
        guard case .chatGPT = try await client.account() else { throw CodexClientError.requiresChatGPT }
        if connectedThread { return }
        guard model.utf8.count <= 512, !model.utf8.contains(0) else { throw CodexClientError.invalidMessage }
        var params: [String: Any] = ["modelProvider": "openai", "cwd": directory.path,
                                     "approvalPolicy": "on-request", "approvalsReviewer": "user"]
        if !model.isEmpty { params["model"] = model }
        seenRequests.removeAll(); activeTurns.removeAll()
        let response: [String: Any]
        if let threadID {
            allowedThreads = [threadID]
            params["threadId"] = threadID
            response = try await client.request("thread/resume", params)
        } else {
            params["allowProviderModelFallback"] = false
            response = try await client.request("thread/start", params)
        }
        guard let thread = response["thread"] as? [String: Any], let id = thread["id"] as? String,
              response["modelProvider"] as? String == "openai",
              let actualModel = response["model"] as? String, !actualModel.isEmpty,
              model.isEmpty || actualModel == model else {
            throw CodexClientError.rejected("Codex did not select the requested ChatGPT model and provider. No turn was sent.")
        }
        if let current = threadID, current != id { throw CodexClientError.invalidMessage }
        if let effort = reasoningEffort {
            let models = try await client.models()
            guard let selected = models.first(where: { $0.id == actualModel }), selected.reasoningEfforts.contains(effort) else {
                throw CodexClientError.rejected("The selected reasoning effort is not advertised for this Codex model. Refresh the model picker and select a supported effort.")
            }
        }
        threadID = id; resolvedModel = actualModel; allowedThreads = [id]; connectedThread = true
        let access: String
        switch (response["sandbox"] as? [String: Any])?["type"] as? String {
        case "workspaceWrite": access = "Workspace access"
        case "readOnly": access = "Read-only access"
        case "dangerFullAccess": access = "Unrestricted access"
        case "externalSandbox": access = "External sandbox"
        default: access = "Unknown access mode"
        }
        let approval: String
        switch response["approvalPolicy"] as? String {
        case "on-request": approval = "Approval on request"
        case "untrusted": approval = "Approval for untrusted commands"
        case "never": approval = "No approval prompts"
        default:
            approval = (response["approvalPolicy"] as? [String: Any])?["granular"] is [String: Any]
                ? "Custom approval rules" : "Unknown approval policy"
        }
        permissionSummary = "\(access) · \(approval)"
        if let turns = thread["turns"] as? [[String: Any]], !turns.isEmpty {
            messages = []; activities = []; items = [:]; itemMessages = [:]
            for turn in turns.suffix(100) {
                for item in turn["items"] as? [[String: Any]] ?? [] { recordItem(item, completed: true, restoring: true) }
            }
            if response["turnsBackwardsCursor"] is String || response["itemsBackwardsCursor"] is String {
                messages.insert(.init(id: UUID(), role: .system, text: "Codex returned recent history. Earlier history remains in the native Codex thread."), at: 0)
            }
        }
    }

    private func event(_ method: String, _ params: [String: Any]) {
        if method == "account/updated" {
            if params["authMode"] as? String != "chatgpt" {
                connectedThread = false
                if submitted { finishTurn(.failure(CodexClientError.requiresChatGPT)) }
            }
            return
        }
        guard let eventThread = params["threadId"] as? String, allowedThreads.contains(eventThread) else { return }
        let rootEvent = eventThread == threadID
        switch method {
        case "turn/started":
            if let turn = params["turn"] as? [String: Any], let turnID = turn["id"] as? String {
                activeTurns[eventThread] = turnID
                if rootEvent, submitted { activeTurnID = turnID }
            }
        case "item/started", "item/completed":
            guard let item = params["item"] as? [String: Any] else { return }
            if rootEvent || !["agentMessage", "userMessage"].contains(item["type"] as? String ?? "") {
                recordItem(item, completed: method == "item/completed")
            }
        case "item/agentMessage/delta":
            guard rootEvent, submitted, let itemID = params["itemId"] as? String, let delta = params["delta"] as? String else { return }
            appendDelta(delta, itemID: itemID)
        case "item/commandExecution/outputDelta":
            guard let itemID = params["itemId"] as? String, let delta = params["delta"] as? String,
                  let index = activities.firstIndex(where: { $0.id == itemID }) else { return }
            activities[index].detail = bounded(activities[index].detail + delta)
        case "thread/tokenUsage/updated":
            guard rootEvent else { return }
            recordUsage(params, charge: submitted && params["turnId"] as? String == activeTurnID)
        case "thread/compacted":
            if rootEvent { activities.append(.init(id: UUID().uuidString, title: "Context compacted", detail: "Codex compacted its native conversation history.", status: "completed")) }
        case "turn/completed":
            guard rootEvent, submitted, let turn = params["turn"] as? [String: Any],
                  activeTurnID == nil || activeTurnID == turn["id"] as? String else { return }
            recordUnreportedTurn()
            switch turn["status"] as? String {
            case "completed": finishTurn(budgetStop.map { .failure(CodexClientError.rejected($0)) } ?? .success(()))
            case "interrupted": finishTurn(budgetStop.map { .failure(CodexClientError.rejected($0)) } ?? .failure(CancellationError()))
            default:
                let error = (turn["error"] as? [String: Any])?["message"] as? String ?? "Codex did not complete the turn."
                finishTurn(.failure(CodexClientError.rejected(error)))
            }
        default: break
        }
    }

    private func request(_ id: CodexRequestID, _ method: String, _ params: [String: Any]) {
        guard seenRequests.insert(id).inserted else { return }
        guard submitted, let requestedThread = params["threadId"] as? String, allowedThreads.contains(requestedThread),
              let requestedTurn = params["turnId"] as? String, activeTurns[requestedThread] == requestedTurn else { denyUnsupported(id, method); return }
        let kind: CodexApproval.Kind
        switch method {
        case "item/commandExecution/requestApproval": kind = .command
        case "item/fileChange/requestApproval": kind = .fileChange
        default: denyUnsupported(id, method); return
        }
        guard let itemID = params["itemId"] as? String else { denyUnsupported(id, method); return }
        var exact = params
        if let item = items[itemID] { exact["item"] = item }
        guard let data = try? JSONSerialization.data(withJSONObject: exact, options: [.sortedKeys, .prettyPrinted]),
              data.count <= 256 * 1024, let details = String(data: data, encoding: .utf8) else { denyUnsupported(id, method); return }
        let command = params["command"] as? String
        let changes = items[itemID]?["changes"] as? [[String: Any]]
        let knownAction = kind == .command ? !(command ?? "").isEmpty : !(changes ?? []).isEmpty
        let decisions = params["availableDecisions"] as? [Any]
        let accepts = decisions == nil || decisions?.contains(where: { $0 as? String == "accept" }) == true
        let approval = CodexApproval(id: UUID(), kind: kind,
            title: kind == .command ? (params["kind"] as? String == "writeStdin" ? "Send input to Codex command" : "Run Codex command") : "Apply Codex file changes",
            summary: kind == .command ? String((command ?? "Command details unavailable").prefix(500)) : String((changes ?? []).compactMap { $0["path"] as? String }.joined(separator: "\n").prefix(500)),
            details: details, reason: params["reason"] as? String, canApprove: knownAction && accepts)
        approvals.append((approval, id)); pendingApproval = approvals.first?.0; state = .waitingApproval
    }

    private func denyUnsupported(_ id: CodexRequestID, _ method: String) {
        do {
            switch method {
            case "item/commandExecution/requestApproval", "item/fileChange/requestApproval": try client.respond(id, result: ["decision": "decline"])
            case "item/permissions/requestApproval": try client.respond(id, result: ["permissions": [:], "scope": "turn"])
            case "mcpServer/elicitation/request": try client.respond(id, result: ["action": "decline"])
            case "item/tool/requestUserInput": try client.respond(id, result: ["answers": [:]])
            default: try client.rejectUnsupported(id, method: method)
            }
        } catch { finishTurn(.failure(error)) }
        messages.append(.init(id: UUID(), role: .system, text: "Codex requested \(method), which this Trellis view cannot review. No approval was granted. Continue this native thread in Codex for that interaction."))
        trimTranscript()
    }

    private func recordItem(_ item: [String: Any], completed: Bool, restoring: Bool = false) {
        guard let id = item["id"] as? String, let type = item["type"] as? String else { return }
        if type == "reasoning" { return }
        if type == "agentMessage", let text = item["text"] as? String { setMessage(text, itemID: id, role: .assistant); return }
        if type == "userMessage" {
            if restoring {
                let text = (item["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
                setMessage(text, itemID: id, role: .user)
            }
            return
        }
        if let receivers = item["receiverThreadIds"] as? [String] { allowedThreads.formUnion(receivers) }
        // Retain only bounded public item details used in native approval review and activity disclosure.
        let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys, .prettyPrinted])
        if let data, data.count <= 256 * 1024 { items[id] = item }
        let detail = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Details unavailable"
        let title: String
        switch type {
        case "commandExecution": title = item["command"] as? String ?? "Command"
        case "fileChange": title = "File changes"
        case "mcpToolCall": title = [item["server"] as? String, item["tool"] as? String].compactMap { $0 }.joined(separator: " · ")
        case "contextCompaction": title = "Context compacted"
        case "collabAgentToolCall": title = "Codex agent task"
        case "webSearch": title = "Web search"
        case "plan": title = "Plan"
        default: title = type
        }
        let activity = CodexActivity(id: id, title: String(title.prefix(240)), detail: bounded(detail),
                                      status: item["status"] as? String ?? (completed ? "completed" : "inProgress"))
        if let index = activities.firstIndex(where: { $0.id == id }) { activities[index] = activity }
        else { activities.append(activity) }
        if activities.count > 200 { activities.removeFirst(activities.count - 200) }
        if items.count > 200 { items = items.filter { key, _ in activities.contains { $0.id == key } } }
    }

    private func setMessage(_ text: String, itemID: String, role: NativeAgentMessage.Role) {
        guard !text.isEmpty else { return }
        let id = itemMessages[itemID] ?? UUID(); itemMessages[itemID] = id
        if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].text = bounded(text) }
        else { messages.append(.init(id: id, role: role, text: bounded(text))) }
        trimTranscript()
    }

    private func appendDelta(_ text: String, itemID: String) {
        let existing = itemMessages[itemID].flatMap { id in messages.first { $0.id == id }?.text } ?? ""
        setMessage(existing + text, itemID: itemID, role: .assistant)
    }

    private func bounded(_ text: String) -> String { AgentContextBudget.boundedToolOutput(text, maximumBytes: 128 * 1024) }
    private func trimTranscript() {
        if messages.count > 200 { messages.removeFirst(messages.count - 200) }
        itemMessages = itemMessages.filter { _, id in messages.contains { $0.id == id } }
    }
    private func clearApprovals() { approvals = []; pendingApproval = nil }
    private func finishTurn(_ result: Result<Void, Error>) {
        guard completedTurn == nil else { return }
        completedTurn = result
        turnCompletion?.resume(with: result); turnCompletion = nil
    }
    private func recordUnreportedTurn() {
        if submitted && !sawUsage && !recordedUnknownUsage {
            tokenBudget.record(nil); recordedUnknownUsage = true
        }
    }

    private func recordInterruptedTurn() {
        // One native turn can contain more than one model request. Earlier cumulative
        // usage does not establish the cost of an interrupted later request.
        if submitted && !recordedUnknownUsage { tokenBudget.record(nil); recordedUnknownUsage = true }
    }

    private func recordUsage(_ params: [String: Any], charge: Bool) {
        guard let tokenUsage = params["tokenUsage"] as? [String: Any], let total = tokenUsage["total"] as? [String: Any] else { return }
        let wire: [String: Any] = ["usage": ["input_tokens": total["inputTokens"] ?? NSNull(), "output_tokens": total["outputTokens"] ?? NSNull(),
            "input_tokens_details": ["cached_tokens": total["cachedInputTokens"] ?? NSNull()],
            "output_tokens_details": ["reasoning_tokens": total["reasoningOutputTokens"] ?? NSNull()]]]
        guard let sample = AgentModelUsage.parse(wire, api: .responses), let input = sample.inputTokens, let output = sample.outputTokens else { return }
        guard charge else { usage = sample; return }
        let oldInput = usage?.inputTokens ?? 0, oldOutput = usage?.outputTokens ?? 0
        guard input >= oldInput, output >= oldOutput else { tokenBudget.record(nil); return }
        tokenBudget.record(.init(inputTokens: input - oldInput, outputTokens: output - oldOutput))
        usage = sample; sawUsage = true
        if let value = tokenUsage["modelContextWindow"] as? Int, value > 0 { contextWindow = value }
        if tokenBudget.remaining == 0, budgetStop == nil {
            budgetStop = "The Codex thread reached its reported token allowance. Trellis requested interruption; usage is reported after model work and is not a prepaid cap."
            if let threadID, let activeTurnID { client.interrupt(threadID: threadID, turnID: activeTurnID) }
        }
    }
}
