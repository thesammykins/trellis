import SwiftUI

struct AgentModelPicker: View {
    let profile: LaunchProfile
    let directory: URL
    @Binding var modelID: String
    @Binding var reasoning: String
    @State private var models: [AgentModel] = []
    @State private var loading = false
    @State private var error: String?
    @State private var refreshID = UUID()

    private var selected: AgentModel? { models.first { $0.id == modelID } }
    private var displayedReasoningEfforts: [String] {
        if let selected { return selected.reasoningEfforts }
        return ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
    }

    static func reasoningAfterSuccessfulCatalog(profile: LaunchProfile, modelID: String,
                                                reasoning: String, models: [AgentModel]) -> String {
        guard profile == .codex, !reasoning.isEmpty,
              let model = models.first(where: { $0.id == modelID }) else { return reasoning }
        return model.reasoningEfforts.contains(reasoning) ? reasoning : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Model", selection: $modelID) {
                    Text("Use agent default").tag("")
                    ForEach(models) { model in
                        Text(profile == .opencode ? model.displayName + " · " + String(model.id.split(separator: "/").first ?? "") : model.displayName).tag(model.id)
                    }
                    if !modelID.isEmpty && selected == nil { Text(modelID + " (custom)").tag(modelID) }
                }
                Button { refreshID = UUID() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh available models").accessibilityLabel("Refresh available models").disabled(loading)
            }
            if loading { ProgressView("Loading models from " + profile.title + "…").controlSize(.small) }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if !modelID.isEmpty { Text(modelID).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
            if profile == .codex, !modelID.isEmpty {
                Picker("Reasoning", selection: $reasoning) {
                    Text("Use agent default").tag("")
                    ForEach(displayedReasoningEfforts, id: \.self) { effort in Text(effort.capitalized).tag(effort) }
                }
                if selected == nil {
                    Text("Reasoning support is unknown for this manual model. Codex validates it when the session starts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Custom model ID") {
                TextField("Exact model identifier", text: $modelID)
                Text("For models missing from the catalogue. Availability is checked by the agent when it starts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: "\(profile.rawValue)-\(directory.path)-\(refreshID)") {
            loading = true; error = nil; models = []
            do {
                let result = try await AgentModelCatalog.load(profile: profile, directory: directory)
                guard !Task.isCancelled else { return }
                models = result
                if result.isEmpty { error = "No models were advertised. Use the agent default or an exact model ID." }
                reasoning = Self.reasoningAfterSuccessfulCatalog(
                    profile: profile, modelID: modelID, reasoning: reasoning, models: result
                )
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Model discovery unavailable: \(error.localizedDescription)"
            }
            loading = false
        }
        .onChange(of: modelID) { reasoning = "" }
    }
}
