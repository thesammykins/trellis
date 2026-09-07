import SwiftUI
import GhosttyKit

@MainActor
final class WorkspaceSession: Identifiable {
    let id: UUID
    let directory: URL
    let profile: LaunchProfile
    let memoryEnabled: Bool
    let remote: RemoteProfile?
    let multiplexer: MultiplexerProfile?
    let customHarness: CustomHarness?
    var nickname: String?
    var favourite = false
    var displayTitle: String { nickname ?? (state.title.isEmpty ? profile.title : state.title) }
    let launchSettings: SessionLaunchSettings?
    let shellConfiguration: ShellConfiguration?
    private(set) var terminal: TerminalView?
    let state = TerminalState()
    private(set) var envelopeDirectory: URL?

    init(id: UUID = UUID(), directory: URL, profile: LaunchProfile = .shell, memoryEnabled: Bool = false, remote: RemoteProfile? = nil, launchSettings: SessionLaunchSettings? = nil, customHarness: CustomHarness? = nil, multiplexer: MultiplexerProfile? = nil, shellConfiguration: ShellConfiguration? = nil) {
        self.id = id
        self.directory = directory
        self.profile = profile
        self.memoryEnabled = memoryEnabled
        self.remote = remote
        self.launchSettings = launchSettings
        self.customHarness = customHarness
        self.multiplexer = multiplexer
        self.shellConfiguration = profile == .shell ? (shellConfiguration ?? .load()) : nil
        state.title = customHarness?.name ?? profile.title
    }

    func start(runtime: TerminalRuntime, arguments: [String]? = nil, createRemote: Bool = false, createMultiplexer: Bool = false) throws {
        guard terminal == nil else { return }
        state.exitCode = nil; state.isSearching = false; state.query = ""
        state.focused = false; state.secureInputRequested = false; state.secureInputActive = false
        state.title = remote.map { "SSH · " + $0.hostAlias } ?? customHarness?.name ?? profile.title
        let executable = try shellConfiguration?.launchExecutable() ?? customHarness?.validated().executable ?? profile.executable(searchPath: ProcessInfo.processInfo.environment["PATH"] ?? "")
        guard let helper = Bundle.main.path(forAuxiliaryExecutable: "SessionLaunch") else {
            throw TerminalRuntime.Failure("SessionLaunch is missing from the app bundle")
        }
        let integration = memoryEnabled ? try MemoryIntegration(project: directory).launch(profile: profile) : (arguments: [], environment: [:])
        let envelopeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-launch-\(id)-\(UUID())")
        try FileManager.default.createDirectory(at: envelopeDirectory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        let envelope = envelopeDirectory.appendingPathComponent("launch.json")
        do {
            let data = try JSONSerialization.data(withJSONObject: [
                "executable": executable, "arguments": integration.arguments + (try remote?.arguments(create: createRemote) ?? multiplexer?.arguments(create: createMultiplexer, directory: directory) ?? arguments ?? shellConfiguration?.arguments ?? customHarness?.arguments ?? launchSettings?.arguments(for: profile) ?? profile.arguments), "workingDirectory": directory.path
            ])
            guard FileManager.default.createFile(atPath: envelope.path, contents: data,
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw TerminalRuntime.Failure("Could not create the launch envelope")
            }
        } catch {
            try? FileManager.default.removeItem(at: envelopeDirectory)
            throw error
        }
        let command = "'" + helper.replacingOccurrences(of: "'", with: "'\\''") + "'"
        var environment = integration.environment
        if profile == .shell, let resources = Bundle.main.resourceURL?.appendingPathComponent("ghostty") {
            let inherited = ProcessInfo.processInfo.environment
            let integrated = ShellIntegration.env(for: executable, resourceDirectory: resources, inherited: inherited)
            for (key, value) in integrated where inherited[key] != value { environment[key] = value }
        }
        let terminal = TerminalView(app: runtime.app, workingDirectory: directory.path,
                                    command: command, envelopePath: envelope.path, environment: environment)
        self.envelopeDirectory = envelopeDirectory
        terminal.canShareContext = { [weak state] in state.map { !$0.secureInputRequested } ?? false }
        self.terminal = terminal
        runtime.register(terminal, state: state)
    }

    func stop(runtime: TerminalRuntime) {
        guard let terminal else { return }
        runtime.unregister(terminal)
        terminal.shutdown()
        self.terminal = nil
        if let envelopeDirectory { try? FileManager.default.removeItem(at: envelopeDirectory) }
        envelopeDirectory = nil
    }
}

@MainActor
final class Workspace: ObservableObject {
    @Published private(set) var projects: [URL] = []
    @Published var showsWelcome = false
    @Published var showsSidebar = true
    @Published var showsSessions = false
    @Published var showsSessionSwitcher = false
    var pendingSwitcherLaunch: String?
    @Published var showsCustomization = false
    @Published var showsCodexTask = false
    lazy var organization = SessionOrganization(workspaceID: id)
    lazy var workspaceAppearance = WorkspaceAppearanceStore(project: selectedProject)
    lazy var identities = SessionIdentityStore(workspaceID: id)
    let nativeAgentDraft = NativeAgentDraft()
    @Published var showsNewSession = false
    var newSessionProfile: LaunchProfile = .codex
    @Published var showsMemory = false
    @Published var inspectorSection = "context"
    @Published var destination = "terminal"
    @Published var nativeAgent: NativeAgentRuntime?
    var nativeAgentRoute = ""
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL }
    @Published var selectedProject: URL?
    @Published private(set) var sessions: [WorkspaceSession] = []
    @Published private(set) var selectedSessionID: UUID?
    @Published private(set) var layouts: [PaneLayout] = []
    @Published private(set) var storageError: String?
    let runtime: TerminalRuntime
    let id: UUID
    var onChange: (() -> Void)?
    var onRegisterProject: ((URL) -> Void)?
    weak var window: NSWindow?
    var selectedSession: WorkspaceSession? { sessions.first { $0.id == selectedSessionID } }
    var needsStopConfirmation: Bool {
        nativeAgent?.state == .working || nativeAgent?.state == .waitingApproval || sessions.contains { $0.terminal?.surface.map(ghostty_surface_needs_confirm_quit) ?? false }
    }

    init(runtime: TerminalRuntime, id: UUID, projects: [URL], restored: WorkspaceArchive.WindowRecord?) throws {
        self.runtime = runtime
        self.id = id
        self.projects = projects
        if let restored {
            sessions = try restored.sessions.map { record in
                guard let profile = LaunchProfile(rawValue: record.profile) else {
                    throw WorkspaceArchive.Failure("Unsupported launch profile")
                }
                let session = WorkspaceSession(id: record.id, directory: URL(fileURLWithPath: record.directory),
                                        profile: profile, memoryEnabled: record.memoryEnabled ?? false, remote: record.remote, launchSettings: record.launchSettings, customHarness: record.customHarness, multiplexer: record.multiplexer, shellConfiguration: record.shellConfiguration)
                session.nickname = record.nickname; session.favourite = record.favourite ?? false
                return session
            }
            selectedProject = restored.selectedProject.map(URL.init(fileURLWithPath:))
            selectedSessionID = restored.selectedSessionID
            layouts = restored.layouts ?? sessions.map { .terminal($0.id) }
        }
    }

    func updateProjects(_ projects: [URL]) { self.projects = projects }
    func reportStorageError(_ message: String?) { storageError = message }
    var snapshot: WorkspaceArchive.WindowRecord {
        .init(id: id, sessions: sessions.map {
            .init(id: $0.id, directory: $0.directory.standardizedFileURL.path, profile: $0.profile.rawValue,
                  nickname: $0.nickname, favourite: $0.favourite, memoryEnabled: $0.memoryEnabled, remote: $0.remote, launchSettings: $0.launchSettings, customHarness: $0.customHarness, multiplexer: $0.multiplexer, shellConfiguration: $0.shellConfiguration)
        }, selectedProject: selectedProject?.standardizedFileURL.path, selectedSessionID: selectedSessionID, layouts: layouts)
    }

    func chooseProject() {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Open Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let directory = panel.url else { return }
            self?.openProject(directory)
        }
    }

    func openProject(_ directory: URL) {
        let directory = directory.standardizedFileURL
        if !projects.contains(directory) { onRegisterProject?(directory) }
        selectedProject = directory
        if let existing = sessions.first(where: { $0.directory == directory }) { select(existing) }
        else { selectedSessionID = nil; newShell() }
        save()
    }

    func showRegisteredProject(path: String, memory: Bool) {
        guard let project = projects.first(where: { $0.standardizedFileURL.path == path }) else { return }
        window?.makeFirstResponder(nil)
        selectedProject = project
        selectedSessionID = sessions.first(where: { $0.directory == project })?.id
        if memory { destination = "pages" }
        else { selectedSession?.terminal?.requestFocus() }
        save()
    }

    func requestNewSession() { requestAgent(.codex) }

    func requestAgent(_ profile: LaunchProfile) {
        if selectedProject == nil { selectedProject = Self.home }
        newSessionProfile = profile
        showsNewSession = true
    }

    func newShell() { startSession(.shell) }

    func startWindowShell() {
        // Reopening supplies a fresh process in an existing shell tab, never reruns an agent.
        let directory = selectedProject ?? Self.home
        if let shell = sessions.first(where: { $0.directory == directory && $0.profile == .shell }) {
            startAgain(shell)
        } else { newShell() }
    }

    var selectedLayout: PaneLayout? {
        selectedSessionID.flatMap { id in layouts.first { $0.leaves.contains(id) } }
    }
    var tabSessions: [WorkspaceSession] {
        layouts.compactMap { layout in
            guard let first = layout.leaves.first else { return nil }
            return sessions.first { $0.id == first && $0.directory == selectedProject }
        }
    }
    func split(vertical: Bool) {
        guard let layout = selectedLayout, layout.leaves.count < 8 else { return }
        startSession(.shell, splitVertical: vertical)
    }
    private func observeFocus(_ session: WorkspaceSession) {
        session.terminal?.onSessionFocused = { [weak self, weak session] in
            guard let self, let session, selectedSessionID != session.id else { return }
            selectedSessionID = session.id
            save()
        }
    }

    func openHome() { openProject(Self.home) }

    func navigate(_ destination: String) {
        if destination == "agent" {
            self.destination = "terminal"; inspectorSection = "agent"; showsMemory = true
            return
        }
        self.destination = destination
        if destination == "terminal" { selectedSession?.terminal?.requestFocus() }
    }

    func selectAdjacentSession(_ offset: Int) {
        let visible = tabSessions
        guard let first = selectedLayout?.leaves.first,
              let index = visible.firstIndex(where: { $0.id == first }), !visible.isEmpty else { return }
        select(visible[(index + offset + visible.count) % visible.count])
    }

    @discardableResult
    func startSession(_ profile: LaunchProfile, arguments: [String]? = nil, memoryEnabled: Bool = false, launchSettings: SessionLaunchSettings? = nil, splitVertical: Bool? = nil, customHarness: CustomHarness? = nil) -> Bool {
        let directory = selectedProject ?? Self.home
        if !projects.contains(directory) { onRegisterProject?(directory) }
        do {
            try launchSettings?.validate()
            let session = WorkspaceSession(directory: directory, profile: profile, memoryEnabled: memoryEnabled, launchSettings: launchSettings, customHarness: customHarness, multiplexer: profile == .tmux ? MultiplexerProfile() : nil)
            try session.start(runtime: runtime, arguments: arguments, createMultiplexer: profile == .tmux)
            session.terminal?.onClose = { [weak self, weak session] in
                if let session { self?.terminalDidClose(session) }
            }
            sessions.append(session)
            if let splitVertical, let selectedSessionID,
               let index = layouts.firstIndex(where: { $0.leaves.contains(selectedSessionID) }) {
                layouts[index] = layouts[index].splitting(selectedSessionID, adding: session.id, vertical: splitVertical)
            } else { layouts.append(.terminal(session.id)) }
            observeFocus(session)
            showsNewSession = false
            select(session)
            save()
            return true
        } catch { show(error); return false }
    }

    func startRemote(_ profile: RemoteProfile, create: Bool, nickname: String? = nil) -> Bool {
        guard let directory = selectedProject else { return false }
        do {
            let session = WorkspaceSession(directory: directory, profile: .remote, remote: profile)
            guard nickname == nil || (nickname!.utf8.count <= 128 && !nickname!.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)) else {
                storageError = "Session name must be under 128 bytes with no control characters."; return false
            }
            session.nickname = nickname ?? "Remote · " + profile.hostAlias
            try session.start(runtime: runtime, createRemote: create)
            session.terminal?.onClose = { [weak self, weak session] in
                if let session { self?.terminalDidClose(session) }
            }
            sessions.append(session)
            layouts.append(.terminal(session.id))
            observeFocus(session)
            select(session)
            return true
        } catch { storageError = error.localizedDescription; return false }
    }

    func attachLocal(_ profile: MultiplexerProfile, nickname: String) -> Bool {
        do {
            let session = WorkspaceSession(directory: selectedProject ?? Self.home, profile: .tmux, multiplexer: profile)
            session.nickname = nickname
            try session.start(runtime: runtime)
            session.terminal?.onClose = { [weak self, weak session] in if let session { self?.terminalDidClose(session) } }
            sessions.append(session); layouts.append(.terminal(session.id)); observeFocus(session); select(session)
            return true
        } catch { show(error); return false }
    }

    func rename(_ session: WorkspaceSession) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = "Rename Session"
        let field = NSTextField(string: session.nickname ?? session.displayTitle)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.utf8.count <= 128, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                self?.reportStorageError("Session name must be under 128 bytes and contain no control characters."); return
            }
            session.nickname = name.isEmpty ? nil : name
            self?.objectWillChange.send(); self?.save()
        }
    }
    func toggleFavourite(_ session: WorkspaceSession) {
        session.favourite.toggle(); objectWillChange.send(); save()
    }

    private func terminalDidClose(_ session: WorkspaceSession) {
        if session.remote != nil || session.multiplexer != nil { detach(session) }
        else { requestClose(session) }
    }
    func detach(_ session: WorkspaceSession) {
        session.stop(runtime: runtime)
        objectWillChange.send()
        save()
    }

    func reconnect(_ session: WorkspaceSession) {
        session.stop(runtime: runtime)
        startAgain(session)
    }

    func startAgain(_ session: WorkspaceSession) {
        do {
            try session.start(runtime: runtime)
            observeFocus(session)
            session.terminal?.onClose = { [weak self, weak session] in
                if let session { self?.terminalDidClose(session) }
            }
            select(session)
        } catch { show(error) }
    }

    func select(_ session: WorkspaceSession) {
        // Clear engine focus before detaching; view lifetime is the session lifetime.
        window?.makeFirstResponder(nil)
        selectedProject = session.directory
        destination = "terminal"
        selectedSessionID = session.id
        DispatchQueue.main.async { [weak session] in session?.terminal?.requestFocus() }
        save()
    }

    func requestClose(_ session: WorkspaceSession) {
        guard sessions.contains(where: { $0.id == session.id }), let window,
              window.attachedSheet == nil else { return }
        guard session.terminal?.surface.map(ghostty_surface_needs_confirm_quit) ?? false else {
            close(session); return
        }
        let alert = NSAlert()
        let persistent = session.remote != nil || session.multiplexer != nil
        alert.messageText = persistent ? "Close this attachment?" : "Stop this session?"
        alert.informativeText = persistent ? "The tmux workload will keep running, but this tab’s saved attachment will be removed. Use Detach to keep it for reconnection." : "Its local process will stop. Other sessions will keep running."
        alert.addButton(withTitle: persistent ? "Close Tab" : "Stop Session")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self, weak session] response in
            if response == .alertFirstButtonReturn, let session { self?.close(session) }
        }
    }

    func requestCloseTab(_ session: WorkspaceSession) {
        guard let layout = layouts.first(where: { $0.leaves.contains(session.id) }) else { return }
        let members = sessions.filter { layout.leaves.contains($0.id) }
        guard members.count > 1 else { requestClose(session); return }
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Close all \(members.count) panes in this tab?"
        alert.informativeText = "Local processes will stop. Any tmux workloads keep running, but their saved attachments will be removed."
        alert.addButton(withTitle: "Close Tab"); alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { for member in members { self?.close(member) } }
        }
    }

    private func close(_ session: WorkspaceSession) {
        let wasSelected = selectedSessionID == session.id
        if wasSelected { window?.makeFirstResponder(nil) }
        session.stop(runtime: runtime)
        sessions.removeAll { $0.id == session.id }
        layouts = layouts.compactMap { $0.removing(session.id) }
        if wasSelected {
            selectedSessionID = nil
            if let next = sessions.last(where: { $0.directory == selectedProject }) { select(next) }
        }
        save()
    }

    func closeStoppedSessions() {
        let stopped = sessions.filter { $0.directory == selectedProject && ($0.terminal == nil || $0.state.exitCode != nil) && $0.remote == nil && $0.multiplexer == nil }
        for session in stopped { close(session) }
    }

    func shutdown() {
        nativeAgent?.cancel()
        save()
        for session in sessions { session.stop(runtime: runtime) }
    }

    func moveEarlier(_ session: WorkspaceSession) { move(session, offset: -1) }
    func moveLater(_ session: WorkspaceSession) { move(session, offset: 1) }

    func moveTab(source: UUID, to target: UUID) -> Bool {
        guard let a = sessions.first(where: { $0.id == source }),
              let b = sessions.first(where: { $0.id == target }), a.directory == b.directory,
              a.favourite == b.favourite,
              let from = layouts.firstIndex(where: { $0.leaves.contains(source) }),
              let to = layouts.firstIndex(where: { $0.leaves.contains(target) }), from != to else { return false }
        let item = layouts.remove(at: from)
        layouts.insert(item, at: to)
        save(); return true
    }

    func movePane(source: UUID, target: UUID, position: PaneDropPosition) -> Bool {
        guard let a = sessions.first(where: { $0.id == source }),
              let b = sessions.first(where: { $0.id == target }), a.directory == b.directory else { return false }
        do {
            layouts = try PaneLayout.moving(source, to: target, position: position, in: layouts)
            select(a)
            return true
        } catch { show(error); return false }
    }

    private func move(_ session: WorkspaceSession, offset: Int) {
        let groupIndices = layouts.indices.filter { index in
            layouts[index].leaves.contains { id in sessions.contains { $0.id == id && $0.directory == session.directory } }
        }
        guard let position = groupIndices.firstIndex(where: { layouts[$0].leaves.contains(session.id) }),
              groupIndices.indices.contains(position + offset) else { return }
        layouts.swapAt(groupIndices[position], groupIndices[position + offset])
        save()
    }

    private func save() { onChange?() }

    private func show(_ error: Error) {
        if let window, window.attachedSheet == nil { NSAlert(error: error).beginSheetModal(for: window) }
        else { NSAlert(error: error).runModal() }
    }
}

struct WorkspaceView: View {
    @ObservedObject private var themeState = ThemeState.shared
    private var appTheme: AppTheme? { themeState.theme }
    @Environment(\.colorScheme) private var colorScheme
    @State private var arrangingPanes = false
    @State private var identitySession: WorkspaceSession?
    @State private var showsHarnesses = false
    @State private var customHarnesses: [CustomHarness] = []
    @State private var harnessError: String?
    @State private var showsRemote = false
    @AppStorage("nativeAgentName") private var nativeAgentName = "Trellis Agent"
    @AppStorage("collapsedTabs") private var collapsedTabs = false
    @AppStorage("verticalTabs") private var verticalTabs = false
    @AppStorage("appearance") private var appearance = "system"
    @ObservedObject var workspace: Workspace
    @ObservedObject var scheduler: DreamingScheduler
    @ObservedObject private var organization: SessionOrganization
    @ObservedObject private var layoutSettings: WorkspaceAppearanceStore
    @ObservedObject private var identities: SessionIdentityStore

    init(workspace: Workspace, scheduler: DreamingScheduler) {
        self.workspace = workspace; self.scheduler = scheduler
        organization = workspace.organization
        layoutSettings = workspace.workspaceAppearance
        identities = workspace.identities
    }

    private var orderedTabs: [WorkspaceSession] {
        workspace.tabSessions.sorted { a, b in
            if a.favourite != b.favourite { return a.favourite }
            switch organization.sort {
            case .manual: return false
            case .title: return a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending
            case .harness: return a.profile.title.localizedStandardCompare(b.profile.title) == .orderedAscending
            case .directory: return a.directory.path.localizedStandardCompare(b.directory.path) == .orderedAscending
            }
        }
    }

    private func droppedSession(_ values: [String]) -> UUID? {
        guard values.count == 1 else { return nil }
        let prefix = "trellis-session:" + workspace.id.uuidString + ":"
        guard values[0].hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(values[0].dropFirst(prefix.count)))
    }


    private var sessionStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(verticalTabs ? .vertical : .horizontal) {
                let layout = verticalTabs ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
                layout {
                    ForEach(orderedTabs) { session in
                        HStack(spacing: 6) {
                            Button { workspace.select(session) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        SessionIdentityIcon(session: session, store: identities)
                                        SessionStatusView(id: session.id, profileTitle: session.customHarness?.name ?? session.profile.title,
                                                          isRunning: session.terminal != nil, state: session.state, nickname: session.nickname, compact: verticalTabs && collapsedTabs, showsProfile: false)
                                        if session.favourite && !collapsedTabs { Image(systemName: "star.fill").font(.caption) }
                                    }
                                    if !verticalTabs || !collapsedTabs {
                                        SessionGitView(directory: session.directory, state: session.state,
                                            details: verticalTabs ? layoutSettings.preferences.verticalDetails : layoutSettings.preferences.horizontalDetails,
                                            host: session.remote?.hostAlias, harness: session.customHarness?.name ?? session.profile.title,
                                            model: session.launchSettings?.model ?? "")
                                    }
                                }.frame(maxWidth: verticalTabs ? .infinity : 260, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(session.displayTitle + " · " + session.profile.title)
                            if !verticalTabs || !collapsedTabs { Button { workspace.requestCloseTab(session) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain).accessibilityLabel("Close tab " + session.displayTitle) }
                        }
                        .padding(layoutSettings.preferences.density == .compact ? 5 : 8).frame(minHeight: verticalTabs && !collapsedTabs ? (layoutSettings.preferences.density == .compact ? 44 : 56) : 36).id(session.id)
                        .background(workspace.selectedLayout?.leaves.contains(session.id) == true ? (appTheme.map { Color.themeHex($0.colors.accent) } ?? Color.accentColor).opacity(0.2) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .leading) {
                            if let accent = identities.identity(for: session.id).accentHex {
                                RoundedRectangle(cornerRadius: 2).fill(Color.themeHex(accent)).frame(width: 3).padding(.vertical, 5)
                            }
                        }
                        .contextMenu {
                            Button("Rename…") { workspace.rename(session) }
                            Button("Icon & Accent…") { identitySession = session }
                            Menu("Category") {
                                Button("Uncategorized") { _ = organization.assign(session.id, to: nil) }
                                ForEach(organization.categories) { category in
                                    Button(category.name) { _ = organization.assign(session.id, to: category.id) }
                                }
                            }
                            Menu("Move Into Pane") {
                                ForEach(workspace.sessions.filter { $0.directory == session.directory && $0.id != session.id }) { target in
                                    Menu(target.displayTitle) {
                                        ForEach(PaneDropPosition.allCases) { position in
                                            Button(position.title) { _ = workspace.movePane(source: session.id, target: target.id, position: position) }
                                        }
                                    }
                                }
                            }
                            Button(session.favourite ? "Unfavourite" : "Favourite") { workspace.toggleFavourite(session) }
                            if session.remote != nil || session.multiplexer != nil {
                                Button("Detach") { workspace.detach(session) }
                                Button("Manage Persistent Sessions…") { workspace.showsSessions = true }
                            }
                            Button("Remove from Trellis") { workspace.requestCloseTab(session) }
                            Divider()
                            Button("Move Earlier") { workspace.moveEarlier(session) }
                            Button("Move Later") { workspace.moveLater(session) }
                        }
                        .onDrag { PaneDropOverlay.dragItem(workspaceID: workspace.id, source: session.id) }
                        .dropDestination(for: String.self) { values, _ in
                            guard let id = droppedSession(values), organization.sort == .manual else { return false }
                            return workspace.moveTab(source: id, to: session.id)
                        }
                    }
                }.padding(8)
            }.scrollEdgeEffectHidden()
            .onChange(of: workspace.selectedSessionID) {
                proxy.scrollTo(workspace.selectedLayout?.leaves.first)
            }
        }
        .frame(width: verticalTabs ? (collapsedTabs ? 48 : layoutSettings.preferences.verticalTabWidth) : nil, height: verticalTabs ? nil : (layoutSettings.preferences.density == .compact ? 52 : 64))
    }

    var body: some View {
        HSplitView {
            if workspace.showsSidebar {
                VStack(spacing: 0) {
                    List {
                        ForEach(layoutSettings.preferences.sidebarSections) { section in
                            Section {
                                sidebarContents(section)
                            } header: {
                                Text(section.title)
                                    .draggable("trellis-sidebar:" + section.rawValue)
                            }
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first, values.count == 1,
                                      value.hasPrefix("trellis-sidebar:"),
                                      let source = WorkspaceAppearance.SidebarSection(rawValue: String(value.dropFirst(16))) else { return false }
                                var preferences = layoutSettings.preferences
                                guard let from = preferences.sidebarSections.firstIndex(of: source),
                                      let to = preferences.sidebarSections.firstIndex(of: section), from != to else { return false }
                                preferences.sidebarSections.remove(at: from)
                                preferences.sidebarSections.insert(source, at: to)
                                do { try layoutSettings.update(preferences); return true } catch { return false }
                            }
                        }
                    }.listStyle(.sidebar).scrollContentBackground(appTheme == nil ? .visible : .hidden).buttonStyle(.plain)
                    Button { workspace.navigate("dream") } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Dreaming", systemImage: "moon")
                            Text("Proposals only").font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(16)
                    SettingsLink { Label("Accounts & Agents", systemImage: "gearshape") }.padding(.bottom, 16)
                }.background(appTheme.map { Color.themeHex($0.colors.surface) } ?? Color.clear).frame(minWidth: 220, idealWidth: 230, maxWidth: 260)
            }
            if layoutSettings.preferences.inspectorSide == .left { inspector }
            VStack(spacing: 0) {
                if arrangingPanes {
                    HStack { Text("Drag a tab onto a pane target, or use its Move Into Pane menu."); Spacer(); Button("Done") { arrangingPanes = false } }
                        .font(.caption).padding(8)
                }
                if let storageError = workspace.storageError {
                    Text(storageError).font(.caption).foregroundStyle(.orange).padding(6)
                }
                if workspace.destination == "terminal" {
                    if verticalTabs {
                        HStack(spacing: 0) { sessionStrip; Divider(); terminalContent }
                    } else {
                        sessionStrip
                        Divider()
                        terminalContent
                    }
                } else if workspace.destination == "dream" {
                    DreamingPanel(project: workspace.selectedProject ?? Workspace.home, scheduler: scheduler)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MemoryPanel(project: workspace.selectedProject ?? Workspace.home,
                                selectedText: { workspace.selectedSession?.terminal?.accessibilitySelectedText() },
                                sharingEnabled: workspace.selectedSession?.memoryEnabled ?? false,
                                initialSection: workspace.destination, onSectionChange: workspace.navigate)
                        .id(workspace.selectedProject)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                HStack {
                    Label(workspace.selectedProject?.path ?? Workspace.home.path, systemImage: "folder")
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(workspace.selectedSession?.memoryEnabled == true ? "Memory tools enabled" : "Local terminal")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 7)
            }.frame(minWidth: workspace.destination == "terminal" ? 400 : 500, maxWidth: .infinity, maxHeight: .infinity)
            if layoutSettings.preferences.inspectorSide == .right { inspector }
        }
        .background(appTheme.map { Color.themeHex($0.colors.background) } ?? Color.clear)
        .foregroundStyle(appTheme.map { Color.themeHex($0.colors.text) } ?? Color.primary)
        .tint(appTheme.map { Color.themeHex($0.colors.accent) } ?? Color.accentColor)
        .preferredColorScheme(appTheme.map { $0.appearance == .dark ? .dark : .light } ?? (appearance == "dark" ? .dark : appearance == "light" ? .light : nil))
        .sheet(isPresented: $workspace.showsWelcome) { GettingStartedView() }
        .sheet(isPresented: $workspace.showsSessions) { SessionBrowser(workspace: workspace) }
        .sheet(isPresented: $workspace.showsSessionSwitcher, onDismiss: {
            let launch = workspace.pendingSwitcherLaunch
            workspace.pendingSwitcherLaunch = nil
            if launch == "shell" { workspace.newShell() }
            else if launch == "agent" { workspace.requestNewSession() }
            else { restoreTerminalFocus() }
        }) { SessionSwitcher(workspace: workspace, organization: organization) }
        .sheet(isPresented: $workspace.showsCustomization) { WorkspaceAppearanceView(store: layoutSettings) }
        .sheet(item: $identitySession) { session in SessionIdentityView(session: session, store: identities) }
        .onChange(of: workspace.selectedProject) { layoutSettings.switchProject(workspace.selectedProject) }
        .toolbar {
            if verticalTabs { ToolbarItem { Button { collapsedTabs.toggle() } label: {
                Label(collapsedTabs ? "Expand Tabs" : "Collapse Tabs", systemImage: collapsedTabs ? "sidebar.right" : "sidebar.left")
            } } }

            ToolbarItem(placement: .navigation) {
                Button { workspace.showsSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help(workspace.showsSidebar ? "Hide Sidebar" : "Show Sidebar").accessibilityLabel("Toggle Sidebar")
            }
            ToolbarItem {
                Button("Switch Session", systemImage: "magnifyingglass") { workspace.showsSessionSwitcher = true }
                    .help("Find a session · ⌘P")
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button(action: workspace.newShell) {
                        Label("New Shell", systemImage: "terminal")
                    }.help("New shell · ⌘T")
                    HarnessMenu(custom: customHarnesses, onAgent: { profile in
                        if profile == .tmux { workspace.startSession(.tmux) } else { workspace.requestAgent(profile) }
                    }, onCustom: { workspace.startSession(.custom, customHarness: $0) },
                    onManage: { showsHarnesses = true }, onRemote: { showsRemote = true })
                    .frame(width: 110, height: 26)
                }.labelStyle(.titleAndIcon)
            }
            ToolbarItem {
                Menu("Split", systemImage: "rectangle.split.2x1") {
                    Button("Split Right") { workspace.split(vertical: false) }
                    Button("Split Down") { workspace.split(vertical: true) }
                    Divider()
                    Button(arrangingPanes ? "Finish Arranging Panes" : "Arrange Existing Panes…") { arrangingPanes.toggle() }
                }.disabled(workspace.selectedLayout == nil || (workspace.selectedLayout?.leaves.count ?? 0) >= 8)
            }
            ToolbarItem {
                Button("Ask " + (nativeAgentName.isEmpty ? "Trellis Agent" : nativeAgentName), systemImage: "sparkles") { workspace.navigate("agent") }
                    .help("Open agent chat · ⇧⌘A")
            }

        }
        .onChange(of: [verticalTabs, collapsedTabs, workspace.showsSidebar]) { restoreTerminalFocus() }
        .onChange(of: workspace.showsMemory) { if !workspace.showsMemory { workspace.selectedSession?.terminal?.requestFocus() } }
        .task { reloadHarnesses() }
        .sheet(isPresented: $showsRemote) { RemoteSessionView(workspace: workspace) }
        .sheet(isPresented: $showsHarnesses) {
            VStack {
                HStack { Text("Custom Agents").font(.title2); Spacer(); Button("Done") { showsHarnesses = false } }.padding()
                if let store = try? CustomHarnessStore.appManaged() {
                    CustomHarnessView(store: store, onLaunch: { harness in
                        if workspace.startSession(.custom, customHarness: harness) { showsHarnesses = false }
                    }, onChange: { customHarnesses = $0 })
                } else { Text("Custom agent storage is unavailable.") }
            }
        }
        .alert("Custom agents could not load", isPresented: Binding(get: { harnessError != nil }, set: { if !$0 { harnessError = nil } })) {
            Button("OK") { harnessError = nil }
        } message: { Text(harnessError ?? "") }
        .sheet(isPresented: $workspace.showsCodexTask) { QuickTaskView(workspace: workspace) }
        .sheet(isPresented: $workspace.showsNewSession) { NewSessionView(workspace: workspace, profile: workspace.newSessionProfile) }
    }

    private func restoreTerminalFocus() {
        if workspace.destination == "terminal" { workspace.selectedSession?.terminal?.requestFocus() }
    }

    private func reloadHarnesses() {
        do { customHarnesses = try CustomHarnessStore.appManaged().load() }
        catch { harnessError = error.localizedDescription }
    }

    private func destinationButton(_ title: String, symbol: String, destination: String) -> some View {
        Button { workspace.navigate(destination) } label: {
            Label(title, systemImage: symbol)
                .fontWeight(workspace.destination == destination ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
    }

    @ViewBuilder private func sidebarContents(_ section: WorkspaceAppearance.SidebarSection) -> some View {
        switch section {
        case .projects:
            Button { workspace.openHome() } label: { Label("Home Shell", systemImage: "house") }
            ForEach(workspace.projects.filter { $0 != Workspace.home }, id: \.self) { project in
                Button { workspace.openProject(project) } label: { Label(project.lastPathComponent, systemImage: "folder") }.help(project.path)
            }
            Button(action: workspace.chooseProject) { Label("Open Project…", systemImage: "folder.badge.plus") }
        case .sessions:
            Button { workspace.showsSessionSwitcher = true } label: { Label("Find Session…", systemImage: "magnifyingglass") }
            if workspace.sessions.contains(where: { $0.favourite || organization.category(for: $0.id) != nil }) {
                SessionQuickLinks(workspace: workspace, organization: organization)
            }
            Button { workspace.showsSessions = true } label: { Label("Local & SSH Sessions…", systemImage: "network") }
        case .knowledge:
            destinationButton("Terminal", symbol: "terminal", destination: "terminal")
            destinationButton("Project Memory", symbol: "books.vertical", destination: "pages")
            destinationButton("Review Changes", symbol: "checkmark.bubble", destination: "review")
            Button { workspace.destination = "terminal"; workspace.inspectorSection = "context"; workspace.showsMemory = true } label: { Label("Context & Learn", systemImage: "sidebar.right") }
        }
    }

    @ViewBuilder private var inspector: some View {
        if workspace.showsMemory && workspace.destination == "terminal" {
            VStack(spacing: 0) {
                HStack {
                    Picker("Inspector", selection: $workspace.inspectorSection) {
                        Text("Chat").tag("agent"); Text("Context").tag("context"); Text("Learn").tag("learn")
                    }.pickerStyle(.segmented)
                    Button { workspace.showsMemory = false } label: { Image(systemName: "xmark") }.accessibilityLabel("Close Inspector")
                }.padding(10)
                if workspace.inspectorSection == "agent" { NativeAgentPanel(workspace: workspace) }
                else if workspace.inspectorSection == "learn" { LearningPanel(workspace: workspace, project: workspace.selectedProject ?? Workspace.home) }
                else { MemoryPanel(project: workspace.selectedProject ?? Workspace.home, selectedText: { workspace.selectedSession?.terminal?.accessibilitySelectedText() }, sharingEnabled: workspace.selectedSession?.memoryEnabled ?? false, initialSection: "context").id(workspace.selectedProject) }
            }.frame(minWidth: 340, idealWidth: 400, maxWidth: 560)
        }
    }

    @ViewBuilder private var terminalContent: some View {
        if let layout = workspace.selectedLayout { pane(layout) }
        else {
            ContentUnavailableView("New terminal", systemImage: "terminal",
                                   description: Text("Start a shell here, or choose an agent from New Agent."))
            Button("New Shell", action: workspace.newShell).padding()
        }
    }

    @ViewBuilder private func paneMoveActions(_ session: WorkspaceSession) -> some View {
        ForEach(workspace.sessions.filter { $0.directory == session.directory && $0.id != session.id }) { target in
            Menu(target.displayTitle) {
                ForEach(PaneDropPosition.allCases) { position in
                    Button(position.title) { _ = workspace.movePane(source: session.id, target: target.id, position: position) }
                }
            }
        }
    }

    private func pane(_ layout: PaneLayout) -> AnyView {
        switch layout {
        case .terminal(let id):
            guard let session = workspace.sessions.first(where: { $0.id == id }) else { return AnyView(EmptyView()) }
            return AnyView(VStack(spacing: 0) {
                if let terminal = session.terminal {
                    TerminalPane(terminal: terminal, state: session.state, showsHeader: (workspace.selectedLayout?.leaves.count ?? 0) > 1, onClose: { workspace.requestClose(session) },
                        onDetach: session.remote != nil || session.multiplexer != nil ? { workspace.detach(session) } : nil)
                } else {
                    let persistent = session.remote != nil || session.multiplexer != nil
                    ContentUnavailableView(persistent ? "Session detached" : "Session stopped", systemImage: "stop.circle",
                        description: Text(persistent ? "Reconnect attaches to the same tmux session. Missing sessions are never silently replaced." : "Start Again opens a new process with this session’s saved model settings."))
                    if persistent { Text(session.displayTitle).font(.headline) }
                    Button(persistent ? "Reconnect" : "Start Again") { workspace.startAgain(session) }.padding()
                    Button("Close Pane") { workspace.requestClose(session) }.padding(.bottom)
                }
            }.overlay(alignment: .top) {
                Rectangle().fill(workspace.selectedSessionID == id ? (appTheme.map { Color.themeHex($0.colors.accent) } ?? Color.accentColor) : Color.clear).frame(height: 2)
            }.overlay {
                if arrangingPanes {
                    VStack(spacing: 6) {
                        HStack {
                            Label(session.displayTitle, systemImage: "line.3.horizontal")
                                .lineLimit(1)
                                .padding(6)
                                .contentShape(Rectangle())
                                .onDrag { PaneDropOverlay.dragItem(workspaceID: workspace.id, source: id) }
                                .accessibilityLabel("Drag pane " + session.displayTitle)
                                .contextMenu { paneMoveActions(session) }
                            Spacer(minLength: 0)
                            Menu("Move Into Pane") { paneMoveActions(session) }
                                .accessibilityLabel("Move pane " + session.displayTitle)
                        }.padding(6).background(.regularMaterial)
                        PaneDropOverlay(workspace: workspace, target: id)
                    }
                }
            }.frame(minWidth: 200, idealWidth: 500, maxWidth: .infinity, minHeight: 100, idealHeight: 400, maxHeight: .infinity).id(id))
        case .split(let vertical, let first, let second):
            if vertical { return AnyView(VSplitView { pane(first); pane(second) }.frame(minWidth: 200, idealWidth: 500, maxWidth: .infinity, minHeight: 100, idealHeight: 400, maxHeight: .infinity)) }
            return AnyView(HSplitView { pane(first); pane(second) }.frame(minWidth: 200, idealWidth: 500, maxWidth: .infinity, minHeight: 100, idealHeight: 400, maxHeight: .infinity))
        }
    }
}
