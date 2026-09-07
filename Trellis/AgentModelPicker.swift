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
                    .help("Refresh available models").disabled(loading)
            }
            if loading { ProgressView("Loading models from " + profile.title + "…").controlSize(.small) }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if !modelID.isEmpty { Text(modelID).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
            if profile == .codex, let selected, !selected.reasoningEfforts.isEmpty {
                Picker("Reasoning", selection: $reasoning) {
                    Text("Use agent default").tag("")
                    ForEach(selected.reasoningEfforts, id: \.self) { effort in Text(effort.capitalized).tag(effort) }
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
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Model discovery unavailable: \(error.localizedDescription)"
            }
            if profile != .codex || selected?.reasoningEfforts.contains(reasoning) != true { reasoning = "" }
            loading = false
        }
        .onChange(of: modelID) { reasoning = "" }
    }
}
