import SwiftUI

struct AgentActivityView: View {
    @ObservedObject var agent: NativeAgentRuntime
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Agent Activity & Usage").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            Text("Child tasks: \(agent.sharedTaskCount) · Shared model requests: \(agent.sharedModelRequestCount)")
                .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 12)
            ScrollView {
                AgentActivityBranch(agent: agent).padding(20)
            }
            Divider()
            Text("Usage shows provider-reported counters for each agent. Missing counters remain unknown. Approvals appear in the conversation; Stop cancels the whole task.")
                .font(.caption).foregroundStyle(.secondary).padding(16)
        }.frame(minWidth: 620, idealWidth: 720, minHeight: 500, idealHeight: 650)
    }
}

private struct AgentActivityBranch: View {
    @ObservedObject var agent: NativeAgentRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(agent.displayName, systemImage: "person.crop.circle").font(.headline)
                Spacer()
                Text(agent.activityStatus).font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("\(agent.modelRequestCount) model requests · usage & context") {
                VStack(alignment: .leading, spacing: 6) {
                    metric("Reported input tokens", counter(agent.usage?.inputTokens))
                    metric("Reported cached input tokens", counter(agent.usage?.cachedInputTokens))
                    metric("Reported output tokens", counter(agent.usage?.outputTokens))
                    metric("Reported reasoning tokens", counter(agent.usage?.reasoningTokens))
                    metric("Responses with usage", "\(agent.usageSamples) of \(agent.modelRequestCount)")
                    metric("Latest request", ByteCountFormatter.string(fromByteCount: Int64(agent.requestBytes), countStyle: .file))
                    metric("Older turns omitted from context", agent.omittedContextTurns.formatted())
                    Text("Reported counters are accumulated when present; they may cover fewer responses than the request count. Request bytes are not tokens or cost.")
                        .foregroundStyle(.secondary)
                }.font(.caption).padding(.top, 6)
            }
            ForEach(agent.delegations) { delegation in
                VStack(alignment: .leading, spacing: 10) {
                    Label("\(delegation.kind.rawValue.capitalized) → \(delegation.profile.name)", systemImage: "arrow.turn.down.right")
                        .font(.subheadline.bold())
                    Text(delegation.configuration.model + " · " + delegation.child.endpointHost)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    DisclosureGroup("Task & conversation") {
                        VStack(alignment: .leading, spacing: 12) {
                            if delegation.child.messages.isEmpty { Text(delegation.task).textSelection(.enabled) }
                            AgentTaskTranscript(agent: delegation.child)
                        }.padding(.top, 8)
                    }.font(.caption)
                    AgentActivityBranch(agent: delegation.child)
                }
                .padding(12)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func counter(_ value: Int?) -> String { value?.formatted() ?? "Not reported" }

    private func metric(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
            .accessibilityElement(children: .ignore).accessibilityLabel(label).accessibilityValue(value)
    }
}

private struct AgentTaskTranscript: View {
    @ObservedObject var agent: NativeAgentRuntime
    var body: some View {
        ForEach(agent.messages) { message in
            ConversationTurn(message: message, receipts: agent.receipts.filter { $0.messageID == message.id })
        }
    }
}

extension NativeAgentRuntime {
    var activityStatus: String {
        switch state {
        case .idle: "Ready"
        case .working: "Working"
        case .waitingApproval: "Needs review"
        case .completed: "Complete"
        case .cancelled: "Stopped"
        case .failed: "Failed"
        }
    }
}
