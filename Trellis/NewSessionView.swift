import SwiftUI

/// One entry point for a saved launcher, an existing process, or a new project.
struct NewSessionView: View {
    @ObservedObject var workspace: Workspace
    @State private var harnesses: [CustomHarness] = []
    @State private var selectedID = ""
    @State private var directory: URL
    @State private var createsProject: Bool
    @State private var projectName = ""
    @AppStorage(ProjectDirectory.defaultsKey) private var rootPath = ProjectDirectory.root().path
    private var root: URL { URL(fileURLWithPath: rootPath, isDirectory: true) }
    @State private var showsManager = false
    @State private var errorMessage: String?
    @State private var showsOptions = false
    @State private var memoryEnabled = false
    @State private var modelID = ""
    @State private var reasoning = ""
    @State private var resumeHistory = false
    @State private var historyID = ""

    init(workspace: Workspace, profile: LaunchProfile = .custom) {
        self.workspace = workspace
        _directory = State(initialValue: workspace.selectedProject ?? Workspace.home)
        _createsProject = State(initialValue: workspace.newSessionCreatesProject)
        _selectedID = State(initialValue: workspace.newSessionHarnessID?.uuidString ?? (profile == .shell ? "shell" : ""))
    }

    private var harness: CustomHarness? { harnesses.first { $0.id.uuidString == selectedID } }
    private var profile: LaunchProfile { harness?.integration.flatMap(LaunchProfile.init(rawValue:)) ?? (selectedID == "shell" ? .shell : .custom) }
    private var supportsModel: Bool { [.codex, .opencode, .claude, .gemini].contains(profile) }
    private var supportsResume: Bool { [.codex, .opencode].contains(profile) }
    private var existing: [WorkspaceSession] {
        guard !createsProject else { return [] }
        return (workspace.onOpenSessions?() ?? workspace.sessions).filter { session in
            guard session.directory.standardizedFileURL == directory.standardizedFileURL else { return false }
            if let harness {
                return session.customHarness?.id == harness.id || (session.customHarness == nil && harness.integration == session.profile.rawValue)
            }
            return selectedID == "shell" && session.profile == .shell
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(createsProject ? "New Project" : "Open Agent").font(.title2)
                Spacer()
                Button("Manage Agents…") { showsManager = true }
            }
            HStack {
                Picker("Agent", selection: $selectedID) {
                    Text("Choose an agent").tag("")
                    ForEach(harnesses) { Text($0.name).tag($0.id.uuidString) }
                    Divider()
                    Text("Shell").tag("shell")
                }
            }
            if harnesses.isEmpty {
                Text("Add an installed agent in Manage Agents, or add your own executable.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Picker("Project", selection: $createsProject) {
                Text("Existing Project").tag(false)
                Text("New Project").tag(true)
            }.pickerStyle(.segmented)
            if createsProject {
                TextField("Project name", text: $projectName)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Projects folder").font(.caption).foregroundStyle(.secondary)
                        Text(root.path).font(.callout).lineLimit(2).textSelection(.enabled)
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("Projects folder").accessibilityValue(root.path).id(root.path)
                    Spacer()
                    Button("Choose…") { chooseFolder(forRoot: true) }
                }
            } else {
                HStack {
                    Picker("Folder", selection: $directory) {
                        ForEach(Array(Set(workspace.projects + [directory, Workspace.home])).sorted { $0.path < $1.path }, id: \.self) { project in
                            Text(project == Workspace.home ? "Home" : project.lastPathComponent).tag(project)
                        }
                    }
                    Button("Browse…") { chooseFolder(forRoot: false) }
                }
                Text(directory.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).id(directory.path)
            }
            if !existing.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Existing Sessions").font(.headline)
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(existing) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.displayTitle).lineLimit(1)
                                        Text((session.terminal != nil && session.state.exitCode == nil ? "Running" : "Stopped") + (session.workspace === workspace ? " · This window" : " · Another window"))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Open") { workspace.openExistingSession(session) }
                                        .accessibilityLabel("Open existing " + session.displayTitle)
                                }
                            }
                        }
                    }.frame(maxHeight: 130)
                }
                Divider()
            }
            if selectedID == "shell" || harness != nil {
                DisclosureGroup("New session options", isExpanded: $showsOptions) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(harness?.executable ?? ShellConfiguration.load().executable)
                            .font(.caption.monospaced()).textSelection(.enabled)
                        let arguments = harness?.arguments ?? ShellConfiguration.load().arguments
                        Text(arguments.isEmpty ? "No saved arguments" : arguments.map { String(reflecting: $0) }.joined(separator: " "))
                            .font(.caption).textSelection(.enabled)
                        if showsOptions && supportsModel {
                            AgentModelPicker(profile: profile, directory: directory, modelID: $modelID, reasoning: $reasoning)
                        }
                        if supportsResume {
                            Toggle("Resume an agent history", isOn: $resumeHistory)
                            if resumeHistory { TextField("History ID", text: $historyID) }
                            Toggle("Enable project memory tools", isOn: $memoryEnabled)
                        }
                    }.padding(.top, 8)
                }
            }
            if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button("Cancel") { workspace.showsNewSession = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(createsProject ? "Create Project & Start" : "Start New Session", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedID != "shell" && harness == nil || createsProject && projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 560)
        .task { reload(); if errorMessage == nil { loadOptions() } }
        .onReceive(NotificationCenter.default.publisher(for: CustomHarnessStore.didChange)) { _ in reload() }
        .onChange(of: selectedID) { loadOptions() }
        .onChange(of: profile) { loadOptions() }
        .sheet(isPresented: $showsManager) {
            VStack {
                HStack { Text("My Agents").font(.title2); Spacer(); Button("Done") { showsManager = false } }.padding()
                if let store = try? CustomHarnessStore.appManaged() {
                    CustomHarnessView(store: store, onLaunch: { selectedID = $0.id.uuidString; showsManager = false })
                } else { Text("Agent storage is unavailable.") }
            }
        }
    }

    private func loadOptions() {
        memoryEnabled = false; resumeHistory = false; historyID = ""; errorMessage = nil
        modelID = UserDefaults.standard.string(forKey: profile.rawValue + "LaunchModel") ?? ""
        reasoning = UserDefaults.standard.string(forKey: profile.rawValue + "LaunchReasoning") ?? ""
    }

    private func reload() {
        do {
            harnesses = try CustomHarnessStore.appManaged().load()
            if selectedID.isEmpty {
                selectedID = (harnesses.first { $0.integration == workspace.newSessionProfile.rawValue } ?? harnesses.first)?.id.uuidString ?? ""
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func chooseFolder(forRoot: Bool) {
        let panel = NSOpenPanel()
        panel.title = forRoot ? "Choose Projects Folder" : "Choose Project"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = forRoot ? root : directory
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                if forRoot { try ProjectDirectory.setRoot(url); rootPath = ProjectDirectory.root().path }
                else { directory = url.resolvingSymlinksInPath().standardizedFileURL }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func start() {
        do {
            let executable = try harness?.validated().executable ?? ShellConfiguration.load().launchExecutable()
            let url = URL(fileURLWithPath: executable).resolvingSymlinksInPath()
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                  FileManager.default.isExecutableFile(atPath: url.path) else {
                throw CustomHarness.Failure("The saved executable is unavailable. Update it in Manage Agents.")
            }
            var arguments = harness?.arguments ?? ShellConfiguration.load().arguments
            let settings = supportsModel ? SessionLaunchSettings(model: modelID.trimmingCharacters(in: .whitespacesAndNewlines), reasoning: reasoning, historyID: supportsResume && resumeHistory ? historyID : nil) : nil
            arguments += try settings?.arguments(for: profile) ?? []
            if createsProject {
                directory = try ProjectDirectory.createProject(named: projectName, root: root)
                createsProject = false // A failed process launch must never create the folder twice.
            }
            guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw CustomHarness.Failure("This project folder is unavailable. Choose another folder.")
            }
            workspace.prepareProject(directory)
            workspace.startSession(harness == nil ? .shell : .custom, arguments: arguments,
                                   memoryEnabled: memoryEnabled && supportsResume, launchSettings: settings, customHarness: harness)
        } catch { errorMessage = error.localizedDescription }
    }
}
