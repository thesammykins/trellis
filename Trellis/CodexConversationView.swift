import SwiftUI

struct CodexConversationView: View {
    @ObservedObject var runtime: CodexConversationRuntime
    @ObservedObject var draft: NativeAgentDraft
    let onSend: () -> Void
    let onAttach: () -> Void
    let onNewConversation: () -> Void
    let onSettings: () -> Void
    var submissionError: String? = nil
    @State private var showsUsage = false
    @State private var showsAttachment = false
    @State private var restoreError: String?

    private var busy: Bool { runtime.state == .working || runtime.state == .waitingApproval }
    private var status: String {
        switch runtime.state {
        case .idle: "Ready"
        case .working: "Working"
        case .waitingApproval: "Needs review"
        case .completed: "Complete"
        case .cancelled: "Stopped"
        case .failed: "Failed"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Codex · ChatGPT").font(.headline)
                    Text(status + " · " + (runtime.resolvedModel ?? (runtime.model.isEmpty ? "Codex default model" : runtime.model)))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Menu {
                    Button("New Conversation", action: onNewConversation).disabled(busy)
                    Button("Connection Settings…", action: onSettings)
                    Button("Usage & Context") { showsUsage.toggle() }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Codex Conversation Actions")
            }.padding(12)
            Divider()
            if showsUsage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(runtime.permissionSummary)
                    usageRow("Codex turns", value: runtime.turnCount.formatted())
                    usageRow("Reported input", value: runtime.usage?.inputTokens?.formatted() ?? "Not reported")
                    usageRow("Reported cached input", value: runtime.usage?.cachedInputTokens?.formatted() ?? "Not reported")
                    usageRow("Reported output", value: runtime.usage?.outputTokens?.formatted() ?? "Not reported")
                    usageRow("Context window", value: runtime.contextWindow?.formatted() ?? "Not reported")
                    Text(runtime.budgetContext).fixedSize(horizontal: false, vertical: true)
                    Text("Codex owns tools, output sharing, compaction and native history. Turns are not a count of its internal model requests.")
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.caption).foregroundStyle(.secondary).padding(12)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if runtime.messages.isEmpty {
                            Text("Work with your Codex account in this session’s folder.")
                                .foregroundStyle(.secondary).padding(.vertical)
                        }
                        ForEach(runtime.messages) { message in ConversationTurn(message: message, receipts: []) }
                        if !runtime.activities.isEmpty {
                            DisclosureGroup("Codex Activity · \(runtime.activities.count)") {
                                ForEach(runtime.activities) { activity in
                                    DisclosureGroup(activity.title + " · " + activity.status) {
                                        Text(activity.detail).font(.caption.monospaced()).textSelection(.enabled)
                                    }
                                }
                            }.font(.caption)
                        }
                        if case .failed(let message) = runtime.state { Text(message).foregroundStyle(.red).textSelection(.enabled) }
                        if let restoreError { Text(restoreError).foregroundStyle(.red).textSelection(.enabled) }
                        Color.clear.frame(height: 1).id("latest")
                    }.padding(12)
                }
                .onChange(of: runtime.messages.count) { proxy.scrollTo("latest", anchor: .bottom) }
            }
            if let approval = runtime.pendingApproval {
                VStack(alignment: .leading, spacing: 8) {
                    Label(approval.title, systemImage: "hand.raised").font(.headline)
                    Text(approval.summary).font(.callout).textSelection(.enabled)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    if let reason = approval.reason { Text(reason).font(.callout).fixedSize(horizontal: false, vertical: true) }
                    DisclosureGroup("Exact request") {
                        ScrollView { Text(approval.details).font(.caption.monospaced()).textSelection(.enabled) }.frame(maxHeight: 180)
                    }.font(.caption)
                    HStack {
                        Button("Decline") { runtime.reject(id: approval.id) }
                        Spacer()
                        Button("Approve Once") { runtime.approve(id: approval.id) }
                            .buttonStyle(.borderedProminent).disabled(!approval.canApprove)
                    }
                }.padding(12).background(.quaternary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let submissionError { Text(submissionError).font(.caption).foregroundStyle(.red) }
                if !draft.terminalContextProvenance.isEmpty {
                    DisclosureGroup("Attached terminal context", isExpanded: $showsAttachment) {
                        PlainTextEditor(text: $draft.terminalContext, label: "Terminal context for Codex")
                            .frame(height: 110)
                        Button("Remove Attachment") { draft.terminalContext = ""; draft.terminalContextProvenance = "" }
                    }.font(.caption)
                }
                PlainTextEditor(text: $draft.prompt, label: "Message Codex", focusOnAppear: true, usesSystemFont: true,
                    accessibilityHelp: "Return sends. Shift-Return inserts a new line.", onSubmit: { if !busy { onSend() } })
                    .frame(minHeight: 64, maxHeight: 130)
                HStack {
                    Button("Attach Terminal") { onAttach(); showsAttachment = true }
                    Spacer()
                    if busy { Button("Stop") { runtime.cancel() }.keyboardShortcut(".", modifiers: .command) }
                    else {
                        Button("Send", action: onSend).buttonStyle(.borderedProminent)
                            .disabled(draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }.padding(12)
        }
        .task {
            guard runtime.threadID != nil, runtime.messages.isEmpty else { return }
            do { try await runtime.restore() }
            catch { restoreError = error.localizedDescription }
        }
    }
    private func usageRow(_ label: String, value: String) -> some View {
        LabeledContent(label, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label).accessibilityValue(value)
    }

}
