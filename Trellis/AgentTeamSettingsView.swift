import SwiftUI

@MainActor
final class AgentTeamSettingsDraft: ObservableObject {
    enum Selection: Hashable { case team, profile(UUID) }
    @Published var configuration: AgentTeamConfiguration
    @Published var selection = Selection.team
    @Published private(set) var error: String?
    @Published private(set) var hasExternalChanges = false
    private var baseline: AgentTeamConfiguration

    var isDirty: Bool { configuration != baseline }

    init(store: AgentTeamStore? = nil) {
        let store = store ?? .shared
        configuration = store.configuration
        baseline = store.configuration
    }

    func refresh(from store: AgentTeamStore) {
        if isDirty { hasExternalChanges = store.configuration != baseline }
        else { discard(from: store) }
    }

    func discard(from store: AgentTeamStore) {
        configuration = store.configuration
        baseline = store.configuration
        hasExternalChanges = false
        error = nil
        if case let .profile(id) = selection, !configuration.profiles.contains(where: { $0.id == id }) { selection = .team }
    }

    func save(to store: AgentTeamStore) {
        guard !hasExternalChanges else { error = "Saved settings changed. Discard this draft to reload them before editing."; return }
        do {
            try store.save(configuration)
            baseline = configuration
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct AgentTeamSettingsView: View {
    @ObservedObject var store: AgentTeamStore
    @ObservedObject var draft: AgentTeamSettingsDraft
    var onOpenAgentSettings: () -> Void
    @State private var search = ""
    @State private var deleting: AgentProfile?
    @State private var restoreDefaults = false

    @MainActor
    init(store: AgentTeamStore? = nil, draft: AgentTeamSettingsDraft, onOpenAgentSettings: @escaping () -> Void = {}) {
        self.store = store ?? .shared
        self.draft = draft
        self.onOpenAgentSettings = onOpenAgentSettings
    }

    private var profiles: [AgentProfile] {
        draft.configuration.profiles.filter {
            search.isEmpty || ($0.name + " " + $0.handle + " " + $0.specialty).localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                VStack(spacing: 0) {
                    TextField("Find Agent", text: $search).textFieldStyle(.roundedBorder).padding(10)
                    List(selection: Binding(get: { Optional(draft.selection) }, set: { if let value = $0 { draft.selection = value } })) {
                        Label("Team & Limits", systemImage: "person.3").tag(AgentTeamSettingsDraft.Selection.team)
                        Section("Agents") {
                            ForEach(profiles) { profile in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name).lineLimit(1)
                                    Text("@" + profile.handle + (profile.enabled ? "" : " · Disabled"))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .tag(AgentTeamSettingsDraft.Selection.profile(profile.id))
                                .contextMenu {
                                    Button("Duplicate") { add(profile) }.disabled(draft.configuration.profiles.count >= 24)
                                    Button("Delete…", role: .destructive) { deleting = profile }
                                }
                            }
                        }
                    }.listStyle(.sidebar)
                    HStack {
                        Menu {
                            Button("New Agent") { add(AgentProfile()) }
                            Divider()
                            ForEach(AgentProfile.templates) { profile in Button("From \(profile.name) Preset") { add(profile) } }
                        } label: { Label("Add Agent", systemImage: "plus") }
                        .menuStyle(.borderlessButton)
                        .disabled(draft.configuration.profiles.count >= 24)
                        Spacer()
                    }.padding(12)
                }.frame(minWidth: 160, idealWidth: 175, maxWidth: 215)
                switch draft.selection {
                case .team: teamSettings
                case let .profile(id):
                    if draft.configuration.profiles.contains(where: { $0.id == id }) {
                        AgentProfileSettingsEditor(profile: profileBinding(id), team: draft.configuration,
                            onSelect: { draft.selection = .profile($0) }, onOpenAgentSettings: onOpenAgentSettings,
                            onDuplicate: { if let profile = draft.configuration.profiles.first(where: { $0.id == id }) { add(profile) } },
                            onDelete: { deleting = draft.configuration.profiles.first(where: { $0.id == id }) })
                            .id(id)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                if let error = draft.error ?? store.error { Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled) }
                if draft.hasExternalChanges {
                    Text("Saved settings changed elsewhere. Discard this draft to reload them.").foregroundStyle(.orange).font(.callout)
                }
                HStack {
                    Text(draft.isDirty ? "Unsaved changes · Apply to new conversations" : "Changes apply to new conversations")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Discard") { draft.discard(from: store) }.disabled(!draft.isDirty && !draft.hasExternalChanges)
                    Button("Save Changes") { draft.save(to: store) }
                        .disabled(!draft.isDirty || draft.hasExternalChanges)
                }
            }.padding(12)
        }
        .onAppear { draft.refresh(from: store) }
        .onChange(of: store.configuration) { _, _ in draft.refresh(from: store) }
        .alert("Delete Agent?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let deleting { remove(deleting.id) }; deleting = nil }
        } message: {
            Text("Delete \(deleting?.name ?? "this agent") and its incoming routes from this draft? Current conversations keep their existing team.")
        }
        .confirmationDialog("Replace this draft with the four starter agents and default limits?", isPresented: $restoreDefaults) {
            Button("Use Starter Team", role: .destructive) { draft.configuration = AgentTeamConfiguration(); draft.selection = .team }
        }
    }

    private var teamSettings: some View {
        Form {
            Section("Delegation") {
                Toggle("Allow Automatic Delegation", isOn: $draft.configuration.automaticDelegation)
                Text("Trellis can assign work to enabled agents and follow their allowed routes. Commands and other protected tools keep their review steps.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Routes") {
                AgentTeamRouteMap(team: draft.configuration, selected: nil) { draft.selection = .profile($0) }
            }
            Section("Shared Conversation Limits") {
                AgentTeamNumberField(title: "Child-agent tasks", value: $draft.configuration.maximumTasks, range: 1...24)
                AgentTeamNumberField(title: "Delegation depth", value: $draft.configuration.maximumDepth, range: 1...4)
                AgentTeamNumberField(title: "Shared model requests", value: $draft.configuration.maximumModelRequests, range: 1...100)
                Text("The task limit counts child agents. The model-request limit is shared by Trellis and every child agent. Start a new conversation to reset these limits; they are not a token or currency budget.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Starter Team") {
                Text("Explore, Coding, Writing and Review inherit your conversation’s gateway and model until you choose overrides.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Restore Starter Team…") { restoreDefaults = true }
            }
        }.formStyle(.grouped).frame(minWidth: 340)
    }

    private func profileBinding(_ id: UUID) -> Binding<AgentProfile> {
        Binding(get: { draft.configuration.profiles.first(where: { $0.id == id }) ?? AgentProfile(id: id) },
                set: { value in
                    if let index = draft.configuration.profiles.firstIndex(where: { $0.id == id }) { draft.configuration.profiles[index] = value }
                })
    }

    private func add(_ source: AgentProfile) {
        guard draft.configuration.profiles.count < 24 else { return }
        var profile = source
        profile.id = UUID()
        let existing = Set(draft.configuration.profiles.map(\.handle))
        let stem = String(source.handle.prefix(24))
        var suffix = 2
        while existing.contains(profile.handle) { profile.handle = "\(stem)-\(suffix)"; suffix += 1 }
        if profile.handle != source.handle {
            var name = source.name
            while (name + " Copy").utf8.count > 100 { name.removeLast() }
            profile.name = name + " Copy"
        }
        let ids = Set(draft.configuration.profiles.map(\.id))
        profile.delegates = profile.delegates.filter { ids.contains($0) }
        if let target = profile.escalation, !ids.contains(target) { profile.escalation = nil }
        draft.configuration.profiles.append(profile)
        draft.selection = .profile(profile.id)
        search = ""
    }

    private func remove(_ id: UUID) {
        draft.configuration.profiles.removeAll { $0.id == id }
        for index in draft.configuration.profiles.indices {
            draft.configuration.profiles[index].delegates.removeAll { $0 == id }
            if draft.configuration.profiles[index].escalation == id { draft.configuration.profiles[index].escalation = nil }
        }
        if draft.selection == .profile(id) { draft.selection = .team }
    }
}

private struct AgentProfileSettingsEditor: View {
    @Binding var profile: AgentProfile
    let team: AgentTeamConfiguration
    let onSelect: (UUID) -> Void
    let onOpenAgentSettings: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @AppStorage("apiBaseURL") private var gateway = "https://api.openai.com/v1"
    @AppStorage("apiModel") private var inheritedModel = ""
    @AppStorage("apiKind") private var inheritedAPI = "responses"
    @State private var credentialStatus = "Checking…"
    @State private var credentialRevision = UUID()

    private var endpoint: String { profile.endpoint.isEmpty ? gateway : profile.endpoint }
    private var targets: [AgentProfile] { team.profiles.filter { $0.id != profile.id } }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $profile.name)
                TextField("Handle", text: $profile.handle, prompt: Text("lowercase-name"))
                TextField("Specialty", text: $profile.specialty)
                Toggle("Enabled", isOn: $profile.enabled)
                HStack {
                    Button("Duplicate", action: onDuplicate).disabled(team.profiles.count >= 24)
                    Button("Delete…", role: .destructive, action: onDelete)
                }
            }
            Section("Capabilities") {
                Picker("Tool access", selection: $profile.access) {
                    ForEach(AgentToolAccess.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text(accessDescription).font(.callout).foregroundStyle(.secondary)
            }
            Section("Connection & Model") {
                Toggle("Use a Custom Endpoint", isOn: Binding(get: { !profile.endpoint.isEmpty }, set: { enabled in
                    profile.endpoint = enabled ? gateway : ""
                    if enabled { profile.api = DirectAPI(rawValue: inheritedAPI) ?? .responses }
                }))
                if profile.endpoint.isEmpty {
                    LabeledContent("Gateway", value: gateway).textSelection(.enabled)
                    LabeledContent("Credential", value: credentialStatus)
                        .accessibilityElement(children: .ignore).accessibilityLabel("Credential").accessibilityValue(credentialStatus)
                    Button("Agent Connection Settings…", action: onOpenAgentSettings)
                } else {
                    TextField("API base URL", text: $profile.endpoint)
                    Picker("API", selection: $profile.api) {
                        Text("Responses").tag(DirectAPI.responses)
                        Text("Chat Completions").tag(DirectAPI.chatCompletions)
                    }
                    EndpointKeyControls(endpoint: endpoint) { credentialRevision = UUID() }
                }
                TextField("Model identifier", text: $profile.model, prompt: Text(inheritedModel.isEmpty ? "Use conversation model" : inheritedModel))
                DirectModelCatalogPicker(baseURL: endpoint, apiKey: { try EndpointKey.read(endpoint: endpoint) }, modelID: $profile.model, credentialRevision: credentialRevision)
                Text("Leave the model blank to use the conversation’s model. An override must be available at this endpoint.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Reasoning effort", selection: $profile.reasoningEffort) {
                    Text("Provider default").tag("")
                    ForEach(DirectModelConfiguration.reasoningEfforts, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            Section("Instructions") {
                PlainTextEditor(text: $profile.instructions, label: "Instructions for \(profile.name)", usesSystemFont: true)
                    .frame(height: 150)
                Text("Describe the role’s job and reporting style. Instructions do not grant tools or expand its scope.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Routing") {
                AgentTeamRouteMap(team: team, selected: profile, onSelect: onSelect)
                DisclosureGroup("Allowed Delegates (\(profile.delegates.count))") {
                    ForEach(targets) { target in
                        Toggle(target.name + (target.enabled ? "" : " · Disabled"), isOn: Binding(
                            get: { profile.delegates.contains(target.id) },
                            set: { allowed in
                                profile.delegates.removeAll { $0 == target.id }
                                if allowed { profile.delegates.append(target.id) }
                            }))
                    }
                    if targets.isEmpty { Text("Add another agent to configure routes.").foregroundStyle(.secondary) }
                }
                Picker("Escalate to", selection: $profile.escalation) {
                    Text("No escalation").tag(Optional<UUID>.none)
                    ForEach(targets) { target in
                        Text(target.name + (target.enabled ? "" : " · Disabled")).tag(Optional(target.id))
                    }
                }
                Text("Delegation assigns a bounded subtask. Escalation sends a request to the configured specialist. Disabled targets cannot run; all routes share the conversation limits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Per-Task Limits") {
                AgentTeamNumberField(title: "Model turns", value: $profile.maxModelTurns, range: 1...24)
                AgentTeamNumberField(title: "Tool calls", value: $profile.maxToolCalls, range: 0...48)
                AgentTeamNumberField(title: "Output tokens per response", value: $profile.maxOutputTokens, range: 128...16_384)
                AgentTeamNumberField(title: "Context bytes", value: $profile.contextBytes, range: 8_192...65_536)
                AgentTeamNumberField(title: "Tool-output bytes", value: $profile.toolOutputBytes, range: 1_024...16_384)
                Text("These limits apply to each task assigned to this agent. The shared conversation limits still apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(minWidth: 340)
        .task(id: "\(endpoint)-\(profile.endpoint.isEmpty)-\(credentialRevision)") {
            guard profile.endpoint.isEmpty else { return }
            do { credentialStatus = try EndpointKey.isSaved(endpoint: endpoint) ? "Saved for this endpoint" : "No saved key" }
            catch { credentialStatus = error.localizedDescription }
        }
    }

    private var accessDescription: String {
        switch profile.access {
        case .textOnly: "Work from supplied task context. Project tools and commands are unavailable."
        case .projectRead: "Read scoped project files and approved context. Commands are unavailable."
        case .reviewedTools: "Use project tools and request commands through the normal review flow."
        }
    }
}

private struct AgentTeamRouteMap: View {
    let team: AgentTeamConfiguration
    let selected: AgentProfile?
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected {
                route(source: selected.name, symbol: "arrow.right", action: "Delegate",
                      targets: team.profiles.filter { selected.delegates.contains($0.id) })
                route(source: selected.name, symbol: "arrow.up.right", action: "Escalate",
                      targets: team.profiles.filter { $0.id == selected.escalation })
            } else {
                route(source: "Trellis", symbol: "arrow.right", action: "Delegate", targets: team.profiles.filter(\.enabled))
            }
            Text("→ Delegate     ↗ Escalate · Select an agent to edit it")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func route(source: String, symbol: String, action: String, targets: [AgentProfile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(source).fontWeight(.medium)
                Image(systemName: symbol).accessibilityHidden(true)
                Text(action).foregroundStyle(.secondary)
            }
            if targets.isEmpty { Text("No route").font(.callout).foregroundStyle(.secondary) }
            else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(targets) { target in
                            Button(target.name + (target.enabled ? "" : " · Disabled")) { onSelect(target.id) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("\(source) \(action.lowercased()) to \(target.name). Edit \(target.name)")
                        }
                    }
                }.frame(height: 34)
            }
        }
    }
}

private struct AgentTeamNumberField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            TextField(title, value: $value, format: .number)
            Stepper(title, value: $value, in: range).labelsHidden().fixedSize()
        }.help("\(range.lowerBound)–\(range.upperBound)")
    }
}
