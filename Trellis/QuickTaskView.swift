import SwiftUI

/// An explicit task owned by the installed Codex harness, separate from the active shell.
struct QuickTaskView: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var prompt = ""
    @State private var model = UserDefaults.standard.string(forKey: "codexLaunchModel") ?? ""
    @State private var reasoning = UserDefaults.standard.string(forKey: "codexLaunchReasoning") ?? ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { HarnessIcon(profile: .codex); Text("Ask Codex").font(.title2) }
            Text("Describe a task, such as finding a file or explaining a command. Codex runs it in a new terminal using your connected account.")
            LabeledContent("Starting folder", value: workspace.selectedProject?.path ?? Workspace.home.path)
            AgentModelPicker(profile: .codex, directory: workspace.selectedProject ?? Workspace.home, modelID: $model, reasoning: $reasoning)
            PlainTextEditor(text: $prompt, label: "Task for Codex").frame(height: 150)
            Text("The shell runs in Codex’s read-only sandbox. Codex can read files beyond this folder and load its configured instructions and integrations. This is a Codex task, not a direct API chat.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start Task") {
                    do {
                        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
                        let arguments = try AgentResume.reasoningArguments(profile: .codex, effort: reasoning)
                            + CodexModelClient.interactiveArguments(prompt: prompt, model: selectedModel.isEmpty ? nil : selectedModel)
                        if workspace.startSession(.codex, arguments: arguments, launchSettings: SessionLaunchSettings(model: selectedModel, reasoning: reasoning)) { dismiss() }
                    } catch { self.error = error.localizedDescription }
                }.disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 580)
    }
}
