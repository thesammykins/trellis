import SwiftUI

enum AgentMentionMode: String, CaseIterable { case agents = "Agents", sessions = "Sessions" }

struct AgentMentionView: View {
    let profiles: [AgentProfile]
    let sessions: [WorkspaceSession]
    @Binding var references: [SessionReference]
    @Binding var mode: AgentMentionMode
    let onReference: (SessionReference) -> Void
    let onAssign: (AgentProfile) -> Void
    let onSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mention", selection: $mode) {
                ForEach(AgentMentionMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding([.horizontal, .top], 20)
            if mode == .sessions {
                SessionReferencesView(sessions: sessions, references: $references, onReference: onReference)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Assign an Agent").font(.title2)
                        Spacer()
                        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                    }
                    Text("Your next message goes directly to this specialist. Only its task and attached context are supplied.")
                        .font(.callout).foregroundStyle(.secondary)
                    TextField("Find an agent", text: $query).textFieldStyle(.roundedBorder)
                    List {
                        ForEach(profiles.filter { $0.enabled && (query.isEmpty || ($0.name + " " + $0.handle + " " + $0.specialty).localizedStandardContains(query)) }) { profile in
                            Button {
                                onAssign(profile)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(profile.name + " · @" + profile.handle).font(.headline)
                                        Text(profile.specialty).font(.callout).foregroundStyle(.secondary)
                                        Text(profile.access.title + " · " + (profile.model.isEmpty ? "Conversation model" : profile.model))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                                }.padding(.vertical, 6).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Assign " + profile.name)
                        }
                    }.overlay {
                        if !profiles.contains(where: \.enabled) {
                            ContentUnavailableView("No Enabled Agents", systemImage: "person.3",
                                description: Text("Create or enable specialists in Agent Team settings."))
                        }
                    }
                    HStack {
                        Text("Commands still require review. Routes and limits come from this conversation's agent settings.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Agent Team Settings…") { dismiss(); onSettings() }
                    }
                }.padding(20).frame(width: 720, height: 520)
            }
        }
    }
}
