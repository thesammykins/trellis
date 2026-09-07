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
    @Published var references: [SessionReference] = []
    @Published var approvalPolicy: NativeAgentApprovalPolicy = .scopedReadsAndOutput
    @Published var confirmsEmptyPrompt = false
    @Published var assignedAgentID: UUID?
    var instructionScope: URL?
}

struct NativeAgentPanel: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var draft: NativeAgentDraft
    @ObservedObject private var teamStore = AgentTeamStore.shared
    private let sessionID: UUID?
    @Environment(\.trellisSecondary) private var secondary
    @Environment(\.trellisBorder) private var border
    @Environment(\.openSettings) private var openSettings
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
    @State private var showsConnection = false
    @State private var reusableTools: ReusableAgentTools?
    @State private var showsTools = false
    @State private var showsAttachment = false
    @State private var error: String?
    @State private var followsLatest = true
    @State private var showsReferences = false
    @State private var referenceRange: NSRange?
    @State private var composerSelection: NSRange?
    @State private var mentionMode = AgentMentionMode.agents
    @State private var showsAgentActivity = false
    private var availableProfiles: [AgentProfile] {
        workspace.nativeAgent?.availableProfiles ?? teamStore.configuration.profiles
    }
    private var assignedAgent: AgentProfile? { availableProfiles.first { $0.id == draft.assignedAgentID } }

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
                if !agent.delegations.isEmpty {
                    Button {
                        showsAgentActivity = true
                    } label: {
                        HStack {
                            Label("Agent Activity", systemImage: "person.3")
                            Spacer()
                            Text(agent.activityStatus)
                            Image(systemName: "chevron.right")
                        }.font(.caption)
                    }.buttonStyle(.plain).padding(.horizontal, 14).padding(.vertical, 8)
                }
                if let owner = agent.approvalOwner, let approval = owner.pendingApproval {
                    if owner !== agent {
                        Text("Requested by " + owner.displayName).font(.caption).foregroundStyle(secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
                    }
                    approvalView(approval, agent: owner)
                }
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
        .onChange(of: showsReferences) { _, shown in if shown { composerSelection = nil } }
        .onChange(of: workspace.selectedSession?.state.focused) { _, focused in
            if focused == true { draft.confirmsEmptyPrompt = false }
        }
        .onChange(of: workspace.nativeAgent?.approvalOwner?.pendingApproval?.id) {
            syncReviewedOutput()
            draft.confirmsEmptyPrompt = false
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
        .task(id: workspace.nativeAgent?.approvalOwner?.pendingApproval?.id) {
            guard let approval = workspace.nativeAgent?.approvalOwner?.pendingApproval else { return }
            // Let deliberate composer focus settle before speaking the pending action.
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled, workspace.nativeAgent?.approvalOwner?.pendingApproval?.id == approval.id else { return }
            announce(approval.phase == .execute ? "Tool approval required" : "Tool output review required")
        }
        .sheet(isPresented: $showsContext) { contextSheet }
        .sheet(isPresented: $showsTools) {
            if let reusableTools { ReusableToolsView(store: reusableTools) }
        }
        .sheet(isPresented: $showsReferences) {
            AgentMentionView(profiles: availableProfiles,
                sessions: workspace.onOpenSessions?() ?? workspace.sessions,
                references: $draft.references, mode: $mentionMode,
                onReference: insertReference, onAssign: assignAgent, onSettings: openTeamSettings)
        }
        .sheet(isPresented: $showsAgentActivity) {
            if let agent = workspace.nativeAgent { AgentActivityView(agent: agent) }
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
        if let agent = workspace.nativeAgent {
            Label(status(agent), systemImage: statusSymbol(agent))
                .font(.caption).foregroundStyle(statusColor(agent)).fixedSize()
        }
        Menu {
            Button("Connection & Scope…", systemImage: "info.circle") { showsConnection = true }
            Button("Session Context…", systemImage: "at") { referenceRange = nil; mentionMode = .sessions; showsReferences = true }
            Button("Assign Agent…", systemImage: "person.crop.circle") { referenceRange = nil; mentionMode = .agents; showsReferences = true }
            if workspace.nativeAgent != nil { Button("Agent Activity & Usage…", systemImage: "list.bullet.indent") { showsAgentActivity = true } }
            if workspace.nativeAgent == nil {
                Button("Instructions & Skills…", systemImage: "text.book.closed") { showsContext = true; loadSources() }
            }
            Button("Reusable Tools…", systemImage: "wrench.and.screwdriver") { openTools() }
                .disabled(workspace.selectedSession?.location.localURL == nil)
            Divider()
            Button("Agent Settings…", systemImage: "gearshape", action: openAgentSettings)
            Button("Agent Team Settings…", systemImage: "person.3", action: openTeamSettings)
            if let agent = workspace.nativeAgent {
                Divider()
                Button("New Conversation", systemImage: "square.and.pencil") { workspace.nativeAgent = nil }
                    .disabled(isBusy(agent))
            }
        } label: { Image(systemName: "ellipsis.circle") }
        .menuStyle(.borderlessButton)
        .help("Conversation settings, context and tools")
        .accessibilityLabel("Conversation Actions")
        .popover(isPresented: $showsConnection) { connectionDetails }
    }

    private var connectionDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connection & Scope").font(.headline).foregroundStyle(.primary)
            if !workspace.nativeAgentRoute.isEmpty { Text(workspace.nativeAgentRoute) }
            else {
                Text(model.isEmpty ? "Model not configured" : routeSummary)
                Text(endpoint)
                Text(scopeSummary)
            }
            Divider()
            Text("File tools stay inside the conversation scope. Approved commands use your macOS permissions.")
            Text("Conversation history is kept in memory until New Conversation or app exit.")
            Text(policyExplanation(workspace.nativeAgent?.approvalPolicy ?? draft.approvalPolicy))
            if let agent = workspace.nativeAgent {
                Text("\(agent.messages.count) messages · \(agent.receipts.count) tool actions. Start a new conversation to clear its context.")
            }
        }
        .font(.caption).foregroundStyle(secondary).textSelection(.enabled)
        .padding(16).frame(width: 320)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.isEmpty ? "Choose a model to start a conversation." : "Start a conversation about this terminal.")
                .font(.callout).foregroundStyle(secondary)
            if model.isEmpty {
                Button("Open Agent Settings…", systemImage: "gearshape", action: openAgentSettings)
            }
            if !selectedInstructions.isEmpty || includeSkills {
                Text("\(selectedInstructions.count) instruction sources · \(includeSkills ? instructionSnapshot?.skills.count ?? 0 : 0) skills available")
                    .font(.caption).foregroundStyle(secondary)
            }
            if let reason = workspace.chatUnavailableReason {
                Label(reason, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            Picker("Approvals", selection: $draft.approvalPolicy) {
                Text("Review Every Action").tag(NativeAgentApprovalPolicy.manual)
                Text("Auto-read; Review Sharing").tag(NativeAgentApprovalPolicy.scopedReads)
                Text("Auto-read & Share").tag(NativeAgentApprovalPolicy.scopedReadsAndOutput)
            }.controlSize(.small)
            Text(policyExplanation(draft.approvalPolicy)).font(.caption).foregroundStyle(secondary)
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
        case .runInTerminal: "Run in Terminal"
        case .delegateTask: "Share Task & Run"
        default: "Allow Read"
        }
    }

    private func executionExplanation(_ request: NativeToolRequest) -> String {
        switch request.invocation {
        case .proposeRecipe, .proposeSavedTool: "This stages a proposal. Apply it separately after review."
        case .runCommand, .runSavedTool: "This command runs once with your macOS permissions."
        case .runInTerminal: "Types this command into the visible shell and presses Return once. Completion is not tracked; output is not shared automatically."
        case .delegateTask: "Shares the task and explicit context with this agent’s configured model. It follows saved routes and shared limits. Commands still require review."
        default: "Read once, then review the result before releasing it to the model."
        }
    }

    private func rejectionTitle(_ request: NativeToolRequest) -> String {
        switch request.invocation {
        case .proposeRecipe, .proposeSavedTool: "Reject Proposal"
        case .runCommand, .runSavedTool, .runInTerminal: "Don’t Run"
        case .delegateTask: "Don’t Assign"
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
            Label(approval.phase == .execute ? approval.request.actionTitle : "Share result with model?",
                  systemImage: approval.phase == .execute ? "hand.raised" : "arrow.up.right.circle").font(.headline)
            if let reason = approval.request.reason, !reason.isEmpty {
                Text("Agent’s reason: " + reason).font(.callout).foregroundStyle(secondary).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true).help(reason)
            }
            if approval.phase == .execute {
                if case let .runInTerminal(command, target) = approval.request.invocation {
                    ScrollView(.horizontal) { Text(command).font(.callout.monospaced()).textSelection(.enabled).fixedSize() }
                        .frame(maxHeight: 45)
                    Text(target ?? "Originating shell").font(.caption).foregroundStyle(secondary)
                        .lineLimit(2).truncationMode(.middle).help(target ?? "Originating shell")
                } else {
                    ScrollView(.vertical) {
                        Text(approval.request.reviewText).font(.callout.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 100)
                }
            }
            if approval.phase == .sendOutput {
                PlainTextEditor(text: $draft.reviewedToolOutput, label: "Tool output to send").frame(height: 110)
                Text("Sends only this text to \(agent.endpointHost). Edit it before sharing.")
                    .font(.caption).foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(executionExplanation(approval.request))
                    .font(.caption).foregroundStyle(secondary)
                if case .runInTerminal = approval.request.invocation {
                    Toggle("The visible shell is at an empty prompt", isOn: $draft.confirmsEmptyPrompt)
                        .font(.caption).toggleStyle(.checkbox)
                }
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
            if approval.phase == .execute, case let .runInTerminal(command, _) = approval.request.invocation {
                guard draft.confirmsEmptyPrompt, let terminal = workspace.selectedSession?.terminal else { return }
                do { try terminal.authorizeReviewedCommand(command) }
                catch { self.error = error.localizedDescription; return }
            }
            agent.approvePendingTool(approval.id,
                                     outputForModel: approval.phase == .sendOutput ? draft.reviewedToolOutput : nil)
        }
        .buttonStyle(.borderedProminent)
        .disabled(approval.phase == .execute && isTerminalCommand(approval.request) && !draft.confirmsEmptyPrompt)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let assignedAgent {
                HStack {
                    Label("Assign to " + assignedAgent.name, systemImage: "person.crop.circle")
                    Spacer()
                    Button("Remove Assignment", systemImage: "xmark") { draft.assignedAgentID = nil }
                        .labelStyle(.iconOnly).controlSize(.small)
                }.font(.caption)
            }
            if !draft.references.isEmpty {
                HStack {
                    Button("\(draft.references.count) session references", systemImage: "at") { referenceRange = nil; mentionMode = .sessions; showsReferences = true }
                    Spacer()
                    Button("Clear") { draft.references = [] }
                }.font(.caption).controlSize(.small)
            }
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
                                }, onSubmit: send, onReference: { range in
                                    referenceRange = range; mentionMode = .agents; showsReferences = true
                                }, selectionRequest: composerSelection)
                if draft.prompt.isEmpty {
                    Text("Message \(agentName.isEmpty ? "Trellis Agent" : agentName)…")
                        .foregroundStyle(.tertiary).padding(.horizontal, 6).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 66, maxHeight: 120)
            composerActions
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(12)
    }

    @ViewBuilder private var composerActions: some View {
        HStack(spacing: 8) {
            Button { attachTerminal() } label: { Label("Attach Terminal", systemImage: "paperclip").fixedSize() }
                .disabled(workspace.selectedSession?.terminal == nil)
            Button { referenceRange = nil; mentionMode = .agents; showsReferences = true } label: { Image(systemName: "at") }
                .help("Assign an agent or reference an open session").accessibilityLabel("Mention Agent or Session")
            Spacer(minLength: 8)
            if let agent = workspace.nativeAgent, isBusy(agent) {
                Button("Stop") { agent.cancel() }.keyboardShortcut(".", modifiers: .command)
            } else {
                Button("Send", action: send).buttonStyle(.borderedProminent).disabled(!canSend)
                    .help("Return sends. Shift-Return adds a new line.")
            }
        }
    }

    private var canSend: Bool {
        guard !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let agent = workspace.nativeAgent { return agent.canFollowUp }
        return workspace.chatUnavailableReason == nil && !model.isEmpty
    }

    private func openAgentSettings() {
        UserDefaults.standard.set(SettingsPage.agent.rawValue, forKey: "settingsPage")
        NotificationCenter.default.post(name: SettingsPage.openAgentNotification, object: nil)
        openSettings()
    }

    private func openTeamSettings() {
        UserDefaults.standard.set(SettingsPage.team.rawValue, forKey: "settingsPage")
        NotificationCenter.default.post(name: SettingsPage.openAgentNotification, object: nil)
        openSettings()
    }

    private func send() {
        guard canSend else { return }
        let payload = composedPrompt(draft.prompt)
        guard !payload.utf8.contains(0), payload.utf8.count <= 128 * 1024 else {
            error = "Message and attachments must be under 128 KiB and contain no NUL characters. Shorten the context before sending."
            return
        }
        guard draft.references.count <= 8, draft.references.reduce(0, { $0 + $1.context.utf8.count }) <= 48 * 1024 else {
            error = "Session context exceeds 48 KiB. Remove a reference or shorten its snapshot."
            return
        }
        if let agent = workspace.nativeAgent {
            let previousMessageID = agent.messages.last?.id
            if agent.followUp(prompt: payload, assignedAgentID: draft.assignedAgentID) { clearSentDraft(); error = nil }
            else if let message = agent.messages.last, message.id != previousMessageID, message.role == .system { error = message.text }
            else { error = "This conversation cannot accept more context. Shorten the message or start a new conversation." }
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
            let appReader: NativeAgentAppReader = { [weak origin] request in
                guard let origin, let owner = origin.workspace, owner.sessions.contains(where: { $0 === origin }) else {
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
            let originalTerminal = origin.terminal
            let canRunInTerminal = originalTerminal != nil && origin.profile == .shell
                && origin.remote == nil && origin.multiplexer == nil && origin.customHarness == nil
            let terminalRunner: NativeAgentTerminalRunner = { [weak origin, weak originalTerminal] command in
                guard let origin, let owner = origin.workspace, let originalTerminal,
                      owner.sessions.contains(where: { $0 === origin }), owner.selectedSession === origin,
                      origin.terminal === originalTerminal, origin.profile == .shell,
                      origin.remote == nil, origin.multiplexer == nil, origin.customHarness == nil,
                      origin.location.localURL?.standardizedFileURL == project.standardizedFileURL,
                      originalTerminal.window === owner.window, owner.window?.isVisible == true else {
                    throw TerminalRuntime.Failure("Return to the originating local shell in its original folder before running this command.")
                }
                try originalTerminal.runReviewedCommand(command)
            }
            let savedTools = try ReusableAgentTools(root: integration.root, projectID: integration.projectID, directory: project)
            let agent = try NativeAgentRuntime(configuration: configuration,
                apiKey: EndpointKey.read(endpoint: endpoint), directory: project, memoryStore: store,
                instructionContext: context, agentName: name,
                instructionSnapshot: includeSkills ? instructionSnapshot : nil,
                reusableTools: savedTools, appReader: appReader,
                terminalTarget: canRunInTerminal ? origin.displayTitle + " · " + project.path : nil,
                terminalRunner: canRunInTerminal ? terminalRunner : nil,
                approvalPolicy: draft.approvalPolicy, team: try teamStore.configuration.validated(),
                credentialResolver: { try EndpointKey.read(endpoint: $0) })
            guard agent.start(prompt: composedPrompt(draft.prompt), assignedAgentID: draft.assignedAgentID) else {
                if case .failed(let message) = agent.state { throw TerminalRuntime.Failure(message) }
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
        var contexts = draft.references.map(\.context)
        if !draft.terminalContextProvenance.isEmpty { contexts.append(draft.terminalContextProvenance + "\n" + draft.terminalContext) }
        guard !contexts.isEmpty else { return value }
        return value + "\n\n[User-reviewed terminal attachment]\nSession context · \(contexts.count) references\n"
            + contexts.joined(separator: "\n\n---\n\n")
    }

    private func clearSentDraft() { draft.prompt = ""; draft.references = []; draft.assignedAgentID = nil; removeAttachment() }
    private func assignAgent(_ profile: AgentProfile) {
        draft.assignedAgentID = profile.id
        insertMention("@" + profile.handle + " ")
    }
    private func insertReference(_ reference: SessionReference) {
        insertMention("@" + reference.title + " ")
    }
    private func insertMention(_ marker: String) {
        let value = draft.prompt as NSString
        if let range = referenceRange, NSMaxRange(range) <= value.length, value.substring(with: range) == "@" {
            draft.prompt = value.replacingCharacters(in: range, with: marker)
            composerSelection = NSRange(location: range.location + marker.utf16.count, length: 0)
        } else {
            draft.prompt += (draft.prompt.isEmpty || draft.prompt.last?.isWhitespace == true ? "" : " ") + marker
            composerSelection = NSRange(location: draft.prompt.utf16.count, length: 0)
        }
        referenceRange = nil
        workspace.chatFocusRequest = UUID()
    }
    private func isTerminalCommand(_ request: NativeToolRequest) -> Bool {
        if case .runInTerminal = request.invocation { return true }
        return false
    }
    private func policyExplanation(_ policy: NativeAgentApprovalPolicy) -> String {
        switch policy {
        case .manual: "Review each action and its output before sharing."
        case .scopedReads: "Scoped file, memory and skill reads run automatically. Review output before sharing. Commands and terminal access need approval."
        case .scopedReadsAndOutput: "Scoped file, memory and skill reads are shared with the configured model automatically. Commands and terminal access need approval."
        }
    }
    private func removeAttachment() {
        draft.terminalContext = ""; draft.terminalContextProvenance = ""; showsAttachment = false
    }
    private func resetSourcesIfNeeded() {
        guard workspace.selectedSessionID == sessionID, draft.instructionScope != workspace.chatScope else { return }
        selectedInstructions = []; includeSkills = false; instructionSnapshot = nil
        draft.instructionScope = workspace.chatScope
    }
    private func syncReviewedOutput() {
        guard let approval = workspace.nativeAgent?.approvalOwner?.pendingApproval else {
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

struct ConversationTurn: View {
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
                if let reason = receipt.request.reason { Text("Agent’s reason: " + reason).font(.caption) }
                if receipt.automaticallyExecuted {
                    if case .delegateTask = receipt.request.invocation {
                        Text("Started under this conversation’s agent routes and shared limits. Commands keep their own review.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(receipt.automaticallyReleased ? "Read and shared automatically under this conversation’s scoped-read policy." : "Read automatically; output sharing reviewed separately.").font(.caption).foregroundStyle(.secondary)
                    }
                }
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
            Label(receipt.request.actionTitle + " · " + (receipt.automaticallyReleased ? "Auto-reviewed" : receipt.state.rawValue), systemImage: receiptSymbol).font(.caption)
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
        case .reviewedOutputSent, .taskCompleted: "checkmark.circle"
        case .cancelled: "stop.circle"
        }
    }
}

private extension NativeToolRequest {
    var actionTitle: String {
        switch invocation {
        case .listDirectory: "List folder"
        case .readFile: "Read file"
        case .findFiles: "Find files"
        case .runCommand: "Run background command"
        case .runInTerminal: "Run in visible terminal"
        case .memorySearch: "Search project memory"
        case .memoryRead: "Read project memory"
        case .proposeRecipe: "Propose a recipe"
        case .readSkill: "Read skill instructions"
        case .listSavedTools: "Find reusable tools"
        case .proposeSavedTool: "Propose a reusable tool"
        case .runSavedTool: "Run reusable tool"
        case .readApp(.terminalContext): "Capture terminal viewport"
        case .readApp(.sessionInfo): "Read session details"
        case let .delegateTask(agent, _, _, kind, _): "\(kind.rawValue.capitalized) to @\(agent)"
        }
    }
}
