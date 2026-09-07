import AppKit
import SwiftUI

@MainActor
final class NativeAgentDraft: ObservableObject {
    @Published var prompt = ""
    @Published var terminalContext = ""
    @Published var terminalContextProvenance = ""
    @Published var reviewedToolOutput = ""
    @Published var reviewedApprovalID: UUID?
    @Published var instructionSnapshot: AgentInstructionSnapshot?
    @Published var selectedInstructions = Set<String>()
    @Published var includeSkills = false
    var instructionScope: URL?
}

struct NativeAgentPanel: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var draft: NativeAgentDraft
    private let sessionID: UUID?
    @Environment(\.trellisSecondary) private var secondary
    @Environment(\.trellisBorder) private var border
    @AppStorage("nativeAgentName") private var agentName = "Trellis Agent"
    @AppStorage("apiBaseURL") private var endpoint = "https://api.openai.com/v1"
    @AppStorage("apiModel") private var model = ""
    @AppStorage("apiKind") private var api = "responses"
    @AppStorage("apiReasoningEffort") private var reasoningEffort = ""
    private var instructionSnapshot: AgentInstructionSnapshot? {
        get { draft.instructionSnapshot }
        nonmutating set { draft.instructionSnapshot = newValue }
    }
    private var selectedInstructions: Set<String> {
        get { draft.selectedInstructions }
        nonmutating set { draft.selectedInstructions = newValue }
    }
    private var includeSkills: Bool {
        get { draft.includeSkills }
        nonmutating set { draft.includeSkills = newValue }
    }
    @State private var showsContext = false
    @State private var reusableTools: ReusableAgentTools?
    @State private var showsTools = false
    @State private var showsAttachment = false
    @State private var error: String?
    @State private var followsLatest = true

    init(workspace: Workspace) {
        self.workspace = workspace
        sessionID = workspace.selectedSessionID
        draft = workspace.nativeAgentDraft
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(border)
            if let agent = workspace.nativeAgent {
                transcript(agent)
                if let approval = agent.pendingApproval { approvalView(approval, agent: agent) }
                if case .failed(let message) = agent.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                        .padding(.horizontal, 14).padding(.bottom, 8)
                }
            } else {
                setup
                Spacer(minLength: 0)
            }
            Divider().overlay(border)
            composer
        }
        .onChange(of: workspace.chatScope) { resetSourcesIfNeeded() }
        .onChange(of: workspace.nativeAgent?.pendingApproval?.id) {
            syncReviewedOutput()

        }
        .onChange(of: workspace.nativeAgent?.state) {
            guard let state = workspace.nativeAgent?.state else { return }
            switch state {
            case .completed: announce("Assistant response complete")
            case .cancelled: announce("Assistant stopped")
            case .failed(let message): announce("Assistant failed. " + message)
            default: break
            }
        }
        .onAppear {
            syncReviewedOutput()
            resetSourcesIfNeeded()

        }
        .task(id: workspace.nativeAgent?.pendingApproval?.id) {
            guard let approval = workspace.nativeAgent?.pendingApproval else { return }
            // Let deliberate composer focus settle before speaking the pending action.
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled, workspace.nativeAgent?.pendingApproval?.id == approval.id else { return }
            announce(approval.phase == .execute ? "Tool approval required" : "Tool output review required")
        }
        .sheet(isPresented: $showsContext) { contextSheet }
        .sheet(isPresented: $showsTools) {
            if let reusableTools { ReusableToolsView(store: reusableTools) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                headerControls
                VStack(alignment: .leading, spacing: 6) {
                    agentTitle
                    HStack(spacing: 8) { Spacer(minLength: 0); headerActions }
                }
            }
            HStack(spacing: 5) {
                Text(workspace.chatOriginLabel).lineLimit(1)
                Text("·").foregroundStyle(secondary.opacity(0.7))
                Text(scopeSummary).lineLimit(1).truncationMode(.middle)
            }
            .font(.caption).foregroundStyle(secondary)
            if let fixed = workspace.nativeAgentScope,
               fixed.standardizedFileURL != workspace.chatScope.standardizedFileURL {
                Label("Conversation stays in \(fixed.path); terminal is now in \(workspace.chatScope.path)",
                      systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            DisclosureGroup("Connection and scope") {
                VStack(alignment: .leading, spacing: 5) {
                    if !workspace.nativeAgentRoute.isEmpty { Text(workspace.nativeAgentRoute) }
                    else {
                        Text(model.isEmpty ? "Model not configured" : routeSummary)
                        Text(endpoint)
                    }
                    Text("File tools stay inside the conversation scope. Approved commands use your macOS permissions.")
                    Text("Conversation history is kept in memory until New Conversation or app exit.")
                }
                .font(.caption).foregroundStyle(secondary).textSelection(.enabled).padding(.top, 3)
            }
            .font(.caption)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var headerControls: some View {
        HStack(spacing: 8) {
            agentTitle
            Spacer(minLength: 8)
            headerActions
        }
    }

    private var agentTitle: some View {
        Label(agentName.isEmpty ? "Trellis Agent" : agentName, systemImage: "sparkles")
            .font(.headline).lineLimit(1)
    }

    @ViewBuilder private var headerActions: some View {
            Button("Reusable Tools", systemImage: "wrench.and.screwdriver") { openTools() }
                .labelStyle(.iconOnly).help("Review this conversation's reusable tools")
                .disabled(workspace.selectedSession?.location.localURL == nil)
            if let agent = workspace.nativeAgent {
                Label(status(agent), systemImage: statusSymbol(agent))
                    .font(.caption).foregroundStyle(statusColor(agent)).fixedSize()
                Menu { Button("New Conversation") { workspace.nativeAgent = nil }.disabled(isBusy(agent)) }
                label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).accessibilityLabel("Conversation Actions")
            } else {
                SettingsLink { Image(systemName: "gearshape") }.accessibilityLabel("Agent Settings")
            }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.isEmpty ? "Choose a model in Settings to begin." : "Start a conversation about this terminal.")
                    .font(.callout).foregroundStyle(secondary)
                Spacer()
                Button("Instructions & Skills…") { showsContext = true; loadSources() }
            }
            if !selectedInstructions.isEmpty || includeSkills {
                Text("\(selectedInstructions.count) instruction sources · \(includeSkills ? instructionSnapshot?.skills.count ?? 0 : 0) skills available")
                    .font(.caption).foregroundStyle(secondary)
            }
            if let reason = workspace.chatUnavailableReason {
                Label(reason, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(14)
    }

    private func transcript(_ agent: NativeAgentRuntime) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(agent.messages) { message in
                        ConversationTurn(message: message,
                                         receipts: agent.receipts.filter { $0.messageID == message.id })
                    }
                    Color.clear.frame(height: 1).id("latest")
                }
                .padding(14)
            }
            .overlay(alignment: .bottomTrailing) {
                if !followsLatest {
                    Button {
                        proxy.scrollTo("latest", anchor: .bottom)
                        followsLatest = true
                    } label: {
                    Label("Jump to latest", systemImage: "arrow.down")
                    }
                    .buttonStyle(.bordered).controlSize(.small).padding(12)
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
            } action: { _, isNearBottom in
                followsLatest = isNearBottom
            }
            .onChange(of: transcriptVersion(agent)) {
                if followsLatest { proxy.scrollTo("latest", anchor: .bottom) }
            }
        }
    }

    private func executionTitle(_ request: NativeToolRequest) -> String {
        switch request.invocation {
        case .proposeRecipe, .proposeSavedTool: "Stage Proposal"
        case .runCommand, .runSavedTool: "Run Tool"
        default: "Allow Read"
        }
    }

    private func executionExplanation(_ request: NativeToolRequest) -> String {
        switch request.invocation {
        case .proposeRecipe, .proposeSavedTool: "This stages a proposal. Apply it separately after review."
        case .runCommand, .runSavedTool: "This command runs once with your macOS permissions."
        default: "Read once, then review the result before releasing it to the model."
        }
    }

    private func rejectionTitle(_ request: NativeToolRequest) -> String {
        switch request.invocation {
        case .proposeRecipe, .proposeSavedTool: "Reject Proposal"
        case .runCommand, .runSavedTool: "Don’t Run"
        default: "Deny Read"
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func approvalView(_ approval: NativeAgentApproval, agent: NativeAgentRuntime) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(border)
            Text(approval.phase == .execute ? "Review tool" : "Review output for the model").font(.headline)
            ScrollView(.vertical) {
                Text(approval.request.reviewText).font(.callout.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 100)
            if approval.phase == .sendOutput {
                PlainTextEditor(text: $draft.reviewedToolOutput, label: "Tool output to send").frame(height: 110)
                Text("Only the reviewed text is released to the configured endpoint.")
                    .font(.caption).foregroundStyle(secondary)
            } else {
                Text(executionExplanation(approval.request))
                    .font(.caption).foregroundStyle(secondary)
            }
            ViewThatFits(in: .horizontal) {
                approvalActions(approval, agent: agent)
                VStack(alignment: .trailing, spacing: 6) {
                    rejectionButton(approval, agent: agent)
                    approvalButton(approval, agent: agent)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14).padding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(approval.phase == .execute ? "Tool approval" : "Output review")
    }

    private func approvalActions(_ approval: NativeAgentApproval, agent: NativeAgentRuntime) -> some View {
        HStack {
            rejectionButton(approval, agent: agent)
            Spacer()
            approvalButton(approval, agent: agent)
        }
    }

    private func rejectionButton(_ approval: NativeAgentApproval, agent: NativeAgentRuntime) -> some View {
        Button(approval.phase == .execute ? rejectionTitle(approval.request) : "Withhold Output") {
            agent.rejectPendingTool(approval.id)
        }
    }

    private func approvalButton(_ approval: NativeAgentApproval, agent: NativeAgentRuntime) -> some View {
        Button(approval.phase == .execute ? executionTitle(approval.request) : "Send Reviewed Output") {
            agent.approvePendingTool(approval.id,
                                     outputForModel: approval.phase == .sendOutput ? draft.reviewedToolOutput : nil)
        }
        .buttonStyle(.borderedProminent)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !draft.terminalContextProvenance.isEmpty {
                DisclosureGroup(isExpanded: $showsAttachment) {
                    PlainTextEditor(text: $draft.terminalContext, label: "Terminal snapshot to send").frame(height: 100)
                    HStack {
                        Text(draft.terminalContextProvenance).font(.caption).foregroundStyle(secondary)
                        Spacer()
                        Button("Remove") { removeAttachment() }.controlSize(.small)
                    }
                } label: {
                    Label("Terminal snapshot attached", systemImage: "terminal").font(.caption)
                }
            }
            ZStack(alignment: .topLeading) {
                PlainTextEditor(text: $draft.prompt, label: "Message Trellis Agent",
                                usesSystemFont: true,
                                accessibilityHelp: "Return sends. Shift-Return inserts a new line.",
                                focusRequest: workspace.chatFocusRequest,
                                onFocusConsumed: { request in
                                    if workspace.chatFocusRequest == request { workspace.chatFocusRequest = nil }
                                }, onSubmit: send)
                if draft.prompt.isEmpty {
                    Text("Message \(agentName.isEmpty ? "Trellis Agent" : agentName)…")
                        .foregroundStyle(.tertiary).padding(.horizontal, 6).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 66, maxHeight: 120)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { composerActions; shortcutHint }
                VStack(alignment: .leading, spacing: 5) { composerActions; shortcutHint }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(12)
    }

    @ViewBuilder private var composerActions: some View {
        HStack(spacing: 8) {
            Button { attachTerminal() } label: { Label("Attach Terminal", systemImage: "paperclip").fixedSize() }
                .disabled(workspace.selectedSession?.terminal == nil)
            Spacer(minLength: 8)
            if let agent = workspace.nativeAgent, isBusy(agent) {
                Button("Stop") { agent.cancel() }.keyboardShortcut(".", modifiers: .command)
            } else {
                Button("Send", action: send).buttonStyle(.borderedProminent).disabled(!canSend)
            }
        }
    }
    private var shortcutHint: some View {
        Text("Return sends · Shift-Return adds a line")
            .font(.caption2).foregroundStyle(secondary.opacity(0.8))
            .help("Press Return to send. Press Shift-Return to add a line.")
    }

    private var canSend: Bool {
        guard !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let agent = workspace.nativeAgent { return agent.canFollowUp }
        return workspace.chatUnavailableReason == nil && !model.isEmpty
    }

    private func send() {
        guard canSend else { return }
        if let agent = workspace.nativeAgent {
            if agent.followUp(prompt: composedPrompt(draft.prompt)) { clearSentDraft() }
        } else { start() }
    }

    private func start() {
        do {
            let configuration = DirectModelConfiguration(baseURL: endpoint, model: model,
                api: DirectAPI(rawValue: api) ?? .responses, maxOutputTokens: 4096,
                reasoningEffort: reasoningEffort.isEmpty ? nil : reasoningEffort)
            let name = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.utf8.count <= 80,
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw TerminalRuntime.Failure("Agent name must be 1–80 bytes with no control characters.")
            }
            let sources = instructionSnapshot?.instructions.filter { selectedInstructions.contains($0.id) } ?? []
            let context = sources.map { "Source: " + $0.declaredPath + "\nSHA256: " + $0.sha256 + "\n" + $0.text }
                .joined(separator: "\n\n")
            guard context.utf8.count <= 60_000 else {
                throw TerminalRuntime.Failure("Selected instructions exceed 60 KB. Select fewer sources.")
            }
            let project = workspace.chatScope
            let integration = try MemoryIntegration(project: project)
            let store = try MemoryStore(root: integration.root, projectID: integration.projectID)
            guard let origin = workspace.selectedSession else {
                throw TerminalRuntime.Failure("Open a terminal before starting a conversation.")
            }
            let owner = workspace
            let appReader: NativeAgentAppReader = { [weak origin, weak owner] request in
                guard let origin, let owner, owner.sessions.contains(where: { $0 === origin }) else {
                    throw TerminalRuntime.Failure("The originating terminal session has closed.")
                }
                switch request {
                case .terminalContext:
                    guard let text = origin.terminal?.agentContextText() else {
                        throw TerminalRuntime.Failure("Terminal context is unavailable while stopped or secure input is active.")
                    }
                    return "Captured from: " + origin.displayTitle + "\n" + origin.location.summary + "\n\n" + text
                case .sessionInfo:
                    let info: [String: String] = ["title": origin.displayTitle,
                        "harness": origin.customHarness?.name ?? origin.profile.title,
                        "location": origin.location.summary, "conversation_scope": project.path,
                        "host": origin.remote?.hostAlias ?? "local",
                        "terminal": origin.terminal == nil ? "stopped" : "open"]
                    return String(decoding: try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]), as: UTF8.self)
                }
            }
            let savedTools = try ReusableAgentTools(root: integration.root, projectID: integration.projectID, directory: project)
            let agent = try NativeAgentRuntime(configuration: configuration,
                apiKey: EndpointKey.read(endpoint: endpoint), directory: project, memoryStore: store,
                instructionContext: context, agentName: name,
                instructionSnapshot: includeSkills ? instructionSnapshot : nil,
                reusableTools: savedTools, appReader: appReader)
            guard agent.start(prompt: composedPrompt(draft.prompt)) else {
                throw TerminalRuntime.Failure("The message and selected context are too large. Shorten the message or select fewer instruction sources.")
            }
            let reviewed = sources.map { $0.declaredPath + " · " + String($0.sha256.prefix(12)) }.joined(separator: "\n")
            workspace.nativeAgentRoute = name + " · " + routeSummary + "\n" + endpoint + "\nConversation scope: " + project.path
                + (reviewed.isEmpty ? "" : "\nSources:\n" + reviewed)
            workspace.nativeAgentScope = project
            workspace.nativeAgent = agent
            clearSentDraft()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func openTools() {
        do {
            if let existing = workspace.nativeAgent?.reusableTools { reusableTools = existing }
            else {
                let project = workspace.chatScope
                let integration = try MemoryIntegration(project: project)
                reusableTools = try ReusableAgentTools(root: integration.root, projectID: integration.projectID, directory: project)
            }
            showsTools = true
        } catch { self.error = error.localizedDescription }
    }

    private func loadSources() {
        guard instructionSnapshot == nil else { return }
        let project = workspace.chatScope
        error = nil
        Task {
            do {
                let snapshot = try await Task.detached { try AgentInstructions.discover(project: project) }.value
                guard workspace.selectedSessionID == sessionID, project.standardizedFileURL.path == workspace.chatScope.standardizedFileURL.path else { return }
                instructionSnapshot = snapshot
            } catch { self.error = error.localizedDescription }
        }
    }

    private func attachTerminal() {
        guard let session = workspace.selectedSession,
              let context = session.terminal?.agentContextText() else {
            removeAttachment()
            error = "Terminal context is unavailable while secure input is active. Finish secure input, then attach again."
            return
        }
        draft.terminalContext = context
        draft.terminalContextProvenance = "\(session.displayTitle) · \(Date().formatted(date: .abbreviated, time: .shortened)) · \(workspace.chatScope.path)"
        showsAttachment = false
        error = nil
    }

    private func composedPrompt(_ value: String) -> String {
        guard !draft.terminalContextProvenance.isEmpty else { return value }
        return value + "\n\n[User-reviewed terminal attachment]\n" + draft.terminalContextProvenance + "\n" + draft.terminalContext
    }

    private func clearSentDraft() { draft.prompt = ""; removeAttachment() }
    private func removeAttachment() {
        draft.terminalContext = ""; draft.terminalContextProvenance = ""; showsAttachment = false
    }
    private func resetSourcesIfNeeded() {
        guard workspace.selectedSessionID == sessionID, draft.instructionScope != workspace.chatScope else { return }
        selectedInstructions = []; includeSkills = false; instructionSnapshot = nil
        draft.instructionScope = workspace.chatScope
    }
    private func syncReviewedOutput() {
        guard let approval = workspace.nativeAgent?.pendingApproval else {
            draft.reviewedApprovalID = nil
            draft.reviewedToolOutput = ""
            return
        }
        guard draft.reviewedApprovalID != approval.id else { return }
        draft.reviewedApprovalID = approval.id
        draft.reviewedToolOutput = approval.result?.output ?? ""
    }
    private var routeSummary: String {
        let apiLabel = api == "chatCompletions" ? "Chat Completions" : "Responses"
        return model + " · " + apiLabel + (reasoningEffort.isEmpty ? "" : " · " + reasoningEffort)
    }
    private var scopeSummary: String {
        let path = (workspace.nativeAgentScope ?? workspace.chatScope).path
        let label = workspace.nativeAgent == nil
            ? (workspace.selectedSession?.location.label ?? "Folder")
            : "Scope"
        return label + " · " + path
    }
    private func isBusy(_ agent: NativeAgentRuntime) -> Bool {
        agent.state == .working || agent.state == .waitingApproval
    }
    private func status(_ agent: NativeAgentRuntime) -> String {
        switch agent.state {
        case .idle: "Ready"
        case .working: "Working"
        case .waitingApproval: "Waiting for approval"
        case .completed: "Ready"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        }
    }
    private func statusSymbol(_ agent: NativeAgentRuntime) -> String {
        switch agent.state {
        case .working: "ellipsis"
        case .waitingApproval: "hand.raised"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .cancelled: "stop.circle"
        default: "circle"
        }
    }
    private func statusColor(_ agent: NativeAgentRuntime) -> Color {
        switch agent.state {
        case .failed, .waitingApproval: .orange
        default: secondary
        }
    }
    private func transcriptVersion(_ agent: NativeAgentRuntime) -> Int {
        agent.messages.reduce(agent.receipts.count) { $0 + $1.text.utf8.count }
    }

    private var contextSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Instructions & Skills").font(.title2); Spacer(); Button("Done") { showsContext = false } }
            Text("Selected instructions and the skill catalogue are sent with this conversation. They do not grant command permissions.").font(.caption)
            if let instructionSnapshot {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(instructionSnapshot.instructions) { source in
                            Toggle(source.declaredPath, isOn: Binding(get: { selectedInstructions.contains(source.id) }, set: { enabled in
                                if enabled { selectedInstructions.insert(source.id) } else { selectedInstructions.remove(source.id) }
                            }))
                            DisclosureGroup("View source · " + source.scope) {
                                Text(source.resolvedPath + "\nSHA256 " + source.sha256).font(.caption.monospaced()).textSelection(.enabled)
                                Text(source.text).font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                        Toggle("Make \(instructionSnapshot.skills.count) discovered skills available", isOn: $draft.includeSkills)
                        if includeSkills {
                            ForEach(instructionSnapshot.skills) { skill in
                                VStack(alignment: .leading) {
                                    Text(skill.name).fontWeight(.medium); Text(skill.description)
                                    Text(skill.declaredPath).font(.caption.monospaced())
                                }
                            }
                        }
                        ForEach(instructionSnapshot.diagnostics, id: \.self) { Text($0).foregroundStyle(.orange) }
                    }
                }
            } else { Text(error ?? "Loading instruction and skill sources…").foregroundStyle(secondary) }
        }
        .padding(20).frame(width: 720, height: 600)
    }
}

private struct ConversationTurn: View {
    let message: NativeAgentMessage
    let receipts: [NativeToolReceipt]

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            Text(speaker).font(.caption).foregroundStyle(.secondary)
            if message.role == .user {
                VStack(alignment: .leading, spacing: 7) {
                    RichMessageView(markdown: visibleUserText)
                    if let attachment {
                        DisclosureGroup {
                            ScrollView(.horizontal) {
                                Text(attachment.body).font(.caption.monospaced()).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } label: {
                            Label(attachment.label, systemImage: "terminal").font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 420, alignment: .trailing)
            } else {
                RichMessageView(markdown: message.text).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let interruption = message.interruption {
                Label(interruption, systemImage: interruption == "Stopped" ? "stop.circle" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Assistant response " + interruption.lowercased())
            }
            ForEach(receipts) { ToolReceiptView(receipt: $0) }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(speaker + " message")
    }

    private var speaker: String {
        switch message.role { case .user: "You"; case .assistant: "Assistant"; case .system: "System" }
    }
    private var attachment: (label: String, body: String)? {
        let marker = "\n\n[User-reviewed terminal attachment]\n"
        guard let range = message.text.range(of: marker) else { return nil }
        let content = String(message.text[range.upperBound...])
        let parts = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return (parts.first.map(String.init) ?? "Terminal snapshot", parts.count > 1 ? String(parts[1]) : "")
    }
    private var visibleUserText: String {
        let marker = "\n\n[User-reviewed terminal attachment]\n"
        return message.text.range(of: marker).map { String(message.text[..<$0.lowerBound]) } ?? message.text
    }
}

private struct RichMessageView: View {
    private enum Block: Identifiable {
        case prose(Int, String), code(Int, String, String)
        var id: Int { switch self { case .prose(let id, _), .code(let id, _, _): id } }
    }
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks) { block in
                switch block {
                case .prose(_, let source):
                    ProseMarkdownView(source: source)
                case .code(_, let language, let code):
                    VStack(spacing: 0) {
                        HStack {
                            Text(language.isEmpty ? "Code" : language).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { copy(code) } label: { Label("Copy Code", systemImage: "doc.on.doc") }
                                .buttonStyle(.borderless).controlSize(.small)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        Divider()
                        ScrollView(.horizontal) {
                            Text(code).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                .padding(9).fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel((language.isEmpty ? "Code" : language + " code") + " block")
                }
            }
        }
    }

    private var blocks: [Block] {
        MarkdownFenceParser.parse(markdown).enumerated().map { index, block in
            switch block {
            case .prose(let source): .prose(index, source)
            case .code(let language, let body): .code(index, language, body)
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct ProseMarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(source.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("### ") { markdown(String(line.dropFirst(4))).font(.headline).accessibilityAddTraits(.isHeader) }
                else if line.hasPrefix("## ") { markdown(String(line.dropFirst(3))).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader) }
                else if line.hasPrefix("# ") { markdown(String(line.dropFirst(2))).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader) }
                else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                        markdown(String(line.dropFirst(2)))
                    }.accessibilityElement(children: .combine)
                        .accessibilityLabel("List item: " + String(line.dropFirst(2)))
                } else if let item = orderedItem(line) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(item.number + ".").foregroundStyle(.secondary)
                        markdown(item.text)
                    }.accessibilityElement(children: .combine)
                        .accessibilityLabel("List item " + item.number + ": " + item.text)
                } else if line.isEmpty { Color.clear.frame(height: 3) }
                else { markdown(line) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return .discarded
            }
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    private func markdown(_ value: String) -> Text {
        let rendered = (try? AttributedString(markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value)
        return Text(rendered)
    }

    private func orderedItem(_ line: String) -> (number: String, text: String)? {
        guard let separator = line.firstIndex(of: "."), separator != line.startIndex,
              line[..<separator].allSatisfy(\.isNumber) else { return nil }
        let after = line.index(after: separator)
        guard after < line.endIndex, line[after] == " " else { return nil }
        return (String(line[..<separator]), String(line[line.index(after: after)...]))
    }
}

private struct ToolReceiptView: View {
    let receipt: NativeToolReceipt

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 7) {
                LabeledContent("Request") { Text(receipt.request.reviewText).font(.caption.monospaced()).textSelection(.enabled) }
                if !receipt.output.isEmpty {
                    LabeledContent("Original output") { Text(receipt.output).font(.caption.monospaced()).textSelection(.enabled) }
                }
                if let released = receipt.sentToModel {
                    LabeledContent("Released to model") { Text(released).font(.caption.monospaced()).textSelection(.enabled) }
                }
                if let code = receipt.exitCode { Text("Exit status: \(code)").font(.caption) }
                if receipt.truncated { Text("Original output was truncated").font(.caption).foregroundStyle(.orange) }
            }
            .padding(.top, 5)
        } label: {
            Label(receipt.request.name + " · " + receipt.state.rawValue, systemImage: receiptSymbol).font(.caption)
        }
        .padding(9)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(receipt.request.name + ", " + receipt.state.rawValue)
    }

    private var receiptSymbol: String {
        switch receipt.state {
        case .waitingApproval: "hand.raised"
        case .running: "gearshape.2"
        case .awaitingOutputReview: "eye"
        case .rejected: "xmark.circle"
        case .outputWithheld: "eye.slash"
        case .reviewedOutputSent: "checkmark.circle"
        case .cancelled: "stop.circle"
        }
    }
}
