import SwiftUI

struct NewSessionView: View {
    private enum LaunchChoice: String, CaseIterable, Identifiable {
        case startNew
        case resumeHistory

        var id: String { rawValue }
        var title: String {
            switch self {
            case .startNew: "Start New"
            case .resumeHistory: "Resume History"
            }
        }
    }

    @ObservedObject var workspace: Workspace
    @State private var memoryEnabled = true
    @State private var modelID = ""
    @State private var reasoning = ""
    @State private var profile: LaunchProfile = .shell
    @State private var launchChoice = LaunchChoice.startNew
    @State private var historyID = ""
    @State private var resumeError: String?
    @State private var version = "Version not checked"
    init(workspace: Workspace, profile: LaunchProfile = .codex) {
        self.workspace = workspace
        _profile = State(initialValue: profile)
        _modelID = State(initialValue: UserDefaults.standard.string(forKey: profile.rawValue + "LaunchModel") ?? "")
        _reasoning = State(initialValue: UserDefaults.standard.string(forKey: profile.rawValue + "LaunchReasoning") ?? "")
    }

    private var executable: Result<String, Error> {
        Result { try profile.executable(searchPath: AgentInstallation.searchPath) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { HarnessIcon(profile: profile); Text("New " + profile.title + " Session").font(.title2) }
            Picker("Session", selection: $profile) {
                ForEach(LaunchProfile.allCases.filter { $0 != .remote && $0 != .custom && $0 != .tmux }) { Text($0.title).tag($0) }
            }
            LabeledContent("Project", value: workspace.selectedProject?.path ?? Workspace.home.path)
            if profile == .pi {
                Text("Resume history is unavailable for Pi until its CLI support is verified.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            switch executable {
            case .success(let path):
                LabeledContent("Executable", value: path)
                Text(version).font(.caption).foregroundStyle(.secondary)
                if supportsModel {
                    AgentModelPicker(profile: profile, directory: workspace.selectedProject ?? Workspace.home, modelID: $modelID, reasoning: $reasoning)
                }
                if supportsResume {
                    Picker("Launch", selection: $launchChoice) {
                        ForEach(LaunchChoice.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    if launchChoice == .resumeHistory {
                        TextField("History ID", text: $historyID)
                        Text("Starts a new local process for this exact history ID; it does not restore a dead local process.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if profile == .codex || profile == .opencode {
                    Toggle("Enable project memory tools", isOn: $memoryEnabled)
                    Text("Retrieve approved notes and submit proposals. Applying changes still requires review.").font(.caption)
                }
                Text(profile == .shell ? "A normal login shell in this folder." : "Uses the agent’s account and configuration. Manage sign-in in Accounts & Agents.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { workspace.showsNewSession = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(primaryTitle) { start() }.keyboardShortcut(.defaultAction)
                }
                if let resumeError { Text(resumeError).font(.caption).foregroundStyle(.orange) }
            case .failure(let error):
                Text(error.localizedDescription).foregroundStyle(.orange)
                SettingsLink { Text("Accounts & Agents Setup…") }
                Button("Cancel") { workspace.showsNewSession = false }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 520)
        .task(id: profile) {
            version = "Checking version…"
            do {
                let installation = try await AgentInstallation.inspect(profile)
                guard !Task.isCancelled else { return }
                version = installation.version
            } catch {
                guard !Task.isCancelled else { return }
                version = error.localizedDescription
            }
        }
        .onChange(of: profile) {
            launchChoice = .startNew
            historyID = ""
            modelID = UserDefaults.standard.string(forKey: profile.rawValue + "LaunchModel") ?? ""
            reasoning = UserDefaults.standard.string(forKey: profile.rawValue + "LaunchReasoning") ?? ""
            resumeError = nil
        }
    }

    private var supportsModel: Bool { [.codex, .opencode, .claude, .gemini].contains(profile) }

    private var supportsResume: Bool {
        profile == .codex || profile == .opencode
    }

    private var primaryTitle: String {
        supportsResume ? launchChoice.title : LaunchChoice.startNew.title
    }

    private func start() {
        do {
            var arguments = supportsResume && launchChoice == .resumeHistory
                ? try AgentResume.arguments(profile: profile, sessionID: historyID)
                : nil
            let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if supportsModel {
                arguments = try AgentResume.modelArguments(profile: profile, model: model) + (try AgentResume.reasoningArguments(profile: profile, effort: reasoning)) + (arguments ?? [])
                UserDefaults.standard.set(model, forKey: profile.rawValue + "LaunchModel")
                UserDefaults.standard.set(reasoning, forKey: profile.rawValue + "LaunchReasoning")
            }
            workspace.startSession(profile, arguments: arguments,
                                   memoryEnabled: memoryEnabled && supportsResume,
                                   launchSettings: supportsModel ? SessionLaunchSettings(model: model, reasoning: reasoning) : nil)
        } catch {
            resumeError = error.localizedDescription
        }
    }
}
