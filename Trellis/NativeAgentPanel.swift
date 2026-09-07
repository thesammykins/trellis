import SwiftUI

@MainActor
final class NativeAgentDraft: ObservableObject {
    @Published var prompt = ""
    @Published var terminalContext = ""
    @Published var terminalContextProvenance = ""
}

/// The workspace retains the run when navigating back to a terminal or memory.
struct NativeAgentPanel: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var draft: NativeAgentDraft
    @AppStorage("nativeAgentName") private var agentName = "Trellis Agent"
    @State private var instructionSnapshot: AgentInstructionSnapshot?
    @State private var selectedInstructions = Set<String>()
    @State private var includeSkills = false
    @State private var showsContext = false
    @State private var reviewedContext = ""
    @State private var error: String?
    @AppStorage("apiBaseURL") private var endpoint = "https://api.openai.com/v1"
    @AppStorage("apiModel") private var model = ""
    @AppStorage("apiKind") private var api = "responses"

    init(workspace: Workspace) {
        self.workspace = workspace
        draft = workspace.nativeAgentDraft
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(agentName.isEmpty ? "Trellis Agent" : agentName, systemImage: "sparkles").font(.title2)
                Spacer()
            }
            if let agent = workspace.nativeAgent {
                NativeAgentRunView(agent: agent, workspace: workspace, draft: draft, route: workspace.nativeAgentRoute) { workspace.nativeAgent = nil }
            } else {
                HStack {
                    Text(model.isEmpty ? "Model not configured" : model).lineLimit(1)
                    Spacer()
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                }
                Text("Run scope · " + scope.path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                ZStack(alignment: .topLeading) {
                    PlainTextEditor(text: $draft.prompt, label: "Message Trellis Agent", focusOnAppear: true)
                    if draft.prompt.isEmpty {
                        Text("Ask about this terminal, or give me a task…")
                            .foregroundStyle(.tertiary).padding(.horizontal, 6).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }.frame(minHeight: 120, maxHeight: 220)
                terminalAttachment
                Button("Instructions & Skills…") { showsContext = true; loadSources() }
                if !selectedInstructions.isEmpty || includeSkills {
                    Text("\(selectedInstructions.count) instruction sources · \(includeSkills ? instructionSnapshot?.skills.count ?? 0 : 0) skills available").font(.caption)
                }
                DisclosureGroup("Run details") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Endpoint", value: endpoint)
                        LabeledContent("API", value: DirectAPI(rawValue: api) == .chatCompletions ? "Chat Completions" : "Responses")
                        Text("The saved API key for this endpoint is used separately from your ChatGPT subscription.")
                        Text("File tools stay inside the run scope. Approved commands use your macOS permissions. Each tool and its output require review. Follow-ups each receive 12 model turns and 24 tool calls; commands have a 30-second limit.")
                    }
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let error { Text(error).foregroundStyle(.orange) }
                HStack {
                    Spacer()
                    Button("Send") { start() }.buttonStyle(.borderedProminent)
                        .disabled(draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isEmpty)
                }
                Spacer()
            }
        }.padding(20)
        .onChange(of: workspace.selectedProject) {
            selectedInstructions = []; includeSkills = false; reviewedContext = ""; instructionSnapshot = nil
        }
        .onChange(of: workspace.selectedSessionID) {
            selectedInstructions = []; includeSkills = false; reviewedContext = ""; instructionSnapshot = nil
        }
        .sheet(isPresented: $showsContext) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Instructions & Skills").font(.title2); Spacer(); Button("Done") { showsContext = false } }
                Text("Selected instructions and the skill catalogue will be sent with your task. Skill bodies are loaded only through a reviewed tool call. These sources do not grant command permissions.").font(.caption)
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
                            Toggle("Make \(instructionSnapshot.skills.count) discovered skills available", isOn: $includeSkills)
                            if includeSkills {
                                ForEach(instructionSnapshot.skills) { skill in
                                    VStack(alignment: .leading) { Text(skill.name).fontWeight(.medium); Text(skill.description); Text(skill.declaredPath).font(.caption.monospaced()) }
                                }
                            }
                            ForEach(instructionSnapshot.diagnostics, id: \.self) { Text($0).foregroundStyle(.orange) }
                        }
                    }
                } else { Text(error ?? "Loading instruction and skill sources…").foregroundStyle(.secondary) }
            }.padding(20).frame(width: 720, height: 600)
        }
    }

    private func loadSources() {
        guard instructionSnapshot == nil else { return }
        let project = scope
        error = nil
        Task {
            do {
                let snapshot = try await Task.detached { try AgentInstructions.discover(project: project) }.value
                guard project.standardizedFileURL.path == scope.standardizedFileURL.path else { return }
                instructionSnapshot = snapshot
            } catch { self.error = error.localizedDescription }
        }
    }

    private func start() {
        do {
            let configuration = DirectModelConfiguration(baseURL: endpoint, model: model,
                api: DirectAPI(rawValue: api) ?? .responses, maxOutputTokens: 4096)
            let name = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.utf8.count <= 80, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw TerminalRuntime.Failure("Agent name must be 1–80 bytes with no control characters.")
            }
            let sources = instructionSnapshot?.instructions.filter { selectedInstructions.contains($0.id) } ?? []
            let context = sources.map { "Source: " + $0.declaredPath + "\nSHA256: " + $0.sha256 + "\n" + $0.text }.joined(separator: "\n\n")
            guard context.utf8.count <= 60_000 else { throw TerminalRuntime.Failure("Selected instructions exceed 60 KB. Select fewer sources.") }
            let project = scope
            let integration = try MemoryIntegration(project: project)
            let store = try MemoryStore(root: integration.root, projectID: integration.projectID)
            let agent = try NativeAgentRuntime(configuration: configuration,
                apiKey: EndpointKey.read(endpoint: endpoint), directory: project, memoryStore: store,
                instructionContext: context, agentName: name, instructionSnapshot: includeSkills ? instructionSnapshot : nil)
            guard agent.start(prompt: composedPrompt(draft.prompt)) else {
                throw TerminalRuntime.Failure("The message and selected context are too large. Shorten the message or select fewer instruction sources.")
            }
            reviewedContext = sources.map { $0.declaredPath + " · " + String($0.sha256.prefix(12)) }.joined(separator: "\n")
            workspace.nativeAgentRoute = name + " · " + model + " · " + endpoint + "\nRun scope: " + project.path + (reviewedContext.isEmpty ? "" : "\nSources:\n" + reviewedContext)
            workspace.nativeAgent = agent
            draft.prompt = ""; draft.terminalContext = ""; draft.terminalContextProvenance = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private var scope: URL { workspace.selectedSession?.directory ?? workspace.selectedProject ?? Workspace.home }

    @ViewBuilder private var terminalAttachment: some View {
        Button("Attach Terminal") { attachTerminal() }
            .disabled(workspace.selectedSession?.terminal == nil)
        if !draft.terminalContextProvenance.isEmpty {
            Text(draft.terminalContextProvenance).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            PlainTextEditor(text: $draft.terminalContext, label: "Terminal snapshot to send")
                .frame(minHeight: 100, maxHeight: 180)
            Button("Remove Attachment") { draft.terminalContext = ""; draft.terminalContextProvenance = "" }
                .controlSize(.small)
        }
    }

    private func attachTerminal() {
        guard let session = workspace.selectedSession,
              let context = session.terminal?.agentContextText() else {
            draft.terminalContext = ""; draft.terminalContextProvenance = ""
            error = "Terminal context is unavailable while secure input is active. Finish secure input, then attach again."
            return
        }
        draft.terminalContext = context
        draft.terminalContextProvenance = "Terminal snapshot · \(session.displayTitle) · \(session.directory.path)"
        error = nil
    }

    private func composedPrompt(_ value: String) -> String {
        guard !draft.terminalContextProvenance.isEmpty else { return value }
        return value + "\n\n[User-reviewed terminal attachment]\n" + draft.terminalContextProvenance + "\n" + draft.terminalContext
    }
}

private struct NativeAgentRunView: View {
    @ObservedObject var agent: NativeAgentRuntime
    @ObservedObject var workspace: Workspace
    @ObservedObject var draft: NativeAgentDraft
    let route: String
    let onNewTask: () -> Void
    @State private var reviewedOutput = ""
    @State private var attachmentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(status, systemImage: symbol)
                Spacer()
                Button("New Task", action: onNewTask).disabled(agent.state == .working || agent.state == .waitingApproval)
                Button("Cancel Task") { agent.cancel() }
                    .disabled(agent.state != .working && agent.state != .waitingApproval)
            }
            Text(route).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(agent.messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                            Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ForEach(agent.receipts) { receipt in
                        DisclosureGroup(receipt.request.name + (receipt.sentToModel == nil ? " · output withheld" : " · output sent")) {
                            Text(receipt.request.reviewText).font(.caption.monospaced()).textSelection(.enabled)
                            Text(receipt.output).font(.caption.monospaced()).textSelection(.enabled)
                            if let code = receipt.exitCode { Text("Exit status: \(code)").font(.caption) }
                            if receipt.truncated { Text("Output truncated").font(.caption).foregroundStyle(.orange) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let approval = agent.pendingApproval {
                Divider()
                Text(approval.phase == .execute ? "Review tool" : "Review output for your model").font(.headline)
                Text(approval.request.reviewText).font(.callout.monospaced()).textSelection(.enabled)
                if approval.phase == .sendOutput {
                    PlainTextEditor(text: $reviewedOutput, label: "Tool output to send").frame(height: 140)
                    Text("Remove anything you do not want sent to the configured endpoint.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("This action will run once. Command execution is not sandboxed by Trellis.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(approval.phase == .execute ? "Reject Tool" : "Withhold Output") { agent.rejectPendingTool(approval.id) }
                    Spacer()
                    Button(approval.phase == .execute ? "Run Tool" : "Send Reviewed Output") {
                        agent.approvePendingTool(approval.id, outputForModel: approval.phase == .sendOutput ? reviewedOutput : nil)
                    }.buttonStyle(.borderedProminent)
                }
            }
            if agent.state == .completed {
                Divider()
                ZStack(alignment: .topLeading) {
                    PlainTextEditor(text: $draft.prompt, label: "Follow up", focusOnAppear: true)
                    if draft.prompt.isEmpty {
                        Text("Ask about this terminal, or give me a task…")
                            .foregroundStyle(.tertiary).padding(.horizontal, 6).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }.frame(minHeight: 70, maxHeight: 140)
                Button("Attach Terminal") { attachTerminal() }
                    .disabled(workspace.selectedSession?.terminal == nil)
                if !draft.terminalContextProvenance.isEmpty {
                    Text(draft.terminalContextProvenance).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    PlainTextEditor(text: $draft.terminalContext, label: "Terminal snapshot to send").frame(height: 100)
                }
                if let attachmentError { Text(attachmentError).font(.caption).foregroundStyle(.orange) }
                HStack {
                    if !draft.terminalContextProvenance.isEmpty {
                        Button("Remove Attachment") { draft.terminalContext = ""; draft.terminalContextProvenance = "" }
                    }
                    Spacer()
                    Button("Send") { sendFollowUp() }.buttonStyle(.borderedProminent)
                        .disabled(draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { reviewedOutput = agent.pendingApproval?.result?.output ?? "" }
        .onChange(of: agent.pendingApproval?.id) {
            reviewedOutput = agent.pendingApproval?.result?.output ?? ""
        }
    }

    private func attachTerminal() {
        guard let session = workspace.selectedSession,
              let context = session.terminal?.agentContextText() else {
            draft.terminalContext = ""; draft.terminalContextProvenance = ""
            attachmentError = "Terminal context is unavailable while secure input is active. Finish secure input, then attach again."
            return
        }
        draft.terminalContext = context
        draft.terminalContextProvenance = "Terminal snapshot · \(session.displayTitle) · \(session.directory.path)"
        attachmentError = nil
    }

    private func sendFollowUp() {
        let message = draft.terminalContextProvenance.isEmpty ? draft.prompt : draft.prompt + "\n\n[User-reviewed terminal attachment]\n" + draft.terminalContextProvenance + "\n" + draft.terminalContext
        if agent.followUp(prompt: message) {
            draft.prompt = ""; draft.terminalContext = ""; draft.terminalContextProvenance = ""
        }
    }

    private var status: String {
        switch agent.state {
        case .idle: "Ready"
        case .working: "Working"
        case .waitingApproval: "Waiting for your approval"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .failed(let message): "Failed: " + message
        }
    }
    private var symbol: String {
        switch agent.state {
        case .working: "gearshape.2"
        case .waitingApproval: "hand.raised"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        default: "pause.circle"
        }
    }
}
