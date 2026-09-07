import SwiftUI
import GhosttyKit

@main
struct TrellisApp: App {
    @Environment(\.openWindow) private var openWindow
    @AppStorage("verticalTabs") private var verticalTabs = false
    @AppStorage("collapsedTabs") private var collapsedTabs = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Automations", id: "automations") { AutomationsView(scheduler: delegate.automations) }
            .defaultSize(width: 820, height: 700)
            .defaultLaunchBehavior(.suppressed)
        Settings { AppSettings(onLaunchAgent: delegate.launchAgentSetup, fontWarnings: delegate.fontWarnings, onImportPreferences: delegate.importPreferences, onTerminalPreferences: delegate.applyTerminalPreferences, onCustomizeWorkspace: delegate.customizeWorkspace, onDreaming: delegate.showDreaming, onAutomations: { openWindow(id: "automations") }) }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Previous Session") { delegate.adjacentSession(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Previous Pane") { delegate.adjacentPane(-1) }.keyboardShortcut("[", modifiers: [.command, .option])
                Button("Next Pane") { delegate.adjacentPane(1) }.keyboardShortcut("]", modifiers: [.command, .option])
                Button("Next Session") { delegate.adjacentSession(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Find in Terminal…") {
                    NSApp.sendAction(#selector(TerminalView.performFindPanelAction(_:)), to: nil, from: nil)
                }.keyboardShortcut("f")
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { delegate.toggleSidebar() }.keyboardShortcut("s", modifiers: [.command, .control])
                Button("Toggle Context & Learn") { delegate.toggleInspector() }.keyboardShortcut("i", modifiers: [.command, .option])
                Button("Switch Session…") { delegate.switchSession() }.keyboardShortcut("p")
                Button("Ask Trellis Agent") { delegate.askNativeAgent() }.keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Customize Workspace…") { delegate.customizeWorkspace() }
                Button("Show Persistent Sessions…") { delegate.showSessions() }
                Button("Automations…") { openWindow(id: "automations") }
                Button("Maximize / Restore Pane") { delegate.toggleMaximizedPane() }.keyboardShortcut(.return, modifiers: [.command, .shift])
                Button("Balance Panes as Grid") { delegate.balancePanes() }
                WindowTransferMenu(delegate: delegate)
                Menu("Tab Layout") {
                    Picker("Orientation", selection: $verticalTabs) {
                        Text("Horizontal Tabs").tag(false)
                        Text("Vertical Tabs").tag(true)
                    }.pickerStyle(.inline)
                    Button(collapsedTabs ? "Expand Vertical Tabs" : "Collapse Vertical Tabs") { collapsedTabs.toggle() }
                        .disabled(!verticalTabs)
                }
            }
            CommandGroup(replacing: .help) {
                Button("Getting Started with Trellis") { delegate.showWelcome() }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Window") { delegate.newWindow() }.keyboardShortcut("n")
                Button("Open Project…") { delegate.openProject() }.keyboardShortcut("o")
                Button("New Shell") { delegate.newTerminal() }.keyboardShortcut("t")
                Button("Ask Codex in Terminal…") { delegate.askCodex() }
                Button("New Agent Session…") { delegate.newSession() }.keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Split Right") { delegate.split(vertical: false) }.keyboardShortcut("d")
                Button("Split Down") { delegate.split(vertical: true) }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Close Stopped Sessions") { delegate.closeStoppedSessions() }
                Button("Close Session") { delegate.closeSession() }.keyboardShortcut("w")
            }
        }
    }
}

private struct WindowTransferMenu: View {
    @ObservedObject var delegate: AppDelegate
    var body: some View {
        Menu("Move Tab to Window") {
            Button("New Window") { delegate.moveTabToNewWindow() }
            Divider()
            ForEach(delegate.windowChoices) { choice in
                Button(choice.title) { delegate.moveTab(to: choice.id) }.disabled(choice.isCurrent)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    struct WindowChoice: Identifiable {
        let id: UUID
        let title: String
        let isCurrent: Bool
    }
    @Published private(set) var windowChoices: [WindowChoice] = []
    let automations = AutomationScheduler()
    private(set) var fontWarnings: [String] = []
    private var runtime: TerminalRuntime?
    private let scheduler = DreamingScheduler()
    private var workspaces: [UUID: Workspace] = [:]
    private var windows: [UUID: NSWindow] = [:]
    private var lastWorkspaceID: UUID?
    private var projects: [URL] = []
    private var archiveFile: URL?
    private var storageError: String?
    private var restoring = true
    private var terminating = false

    private var activeWorkspace: Workspace? {
        if let key = NSApp.keyWindow, let id = windows.first(where: { $0.value === key })?.key {
            return workspaces[id]
        }
        return lastWorkspaceID.flatMap { workspaces[$0] } ?? workspaces.values.first
    }

    private var commandWorkspace: Workspace? {
        guard let key = NSApp.keyWindow, key.attachedSheet == nil,
              let id = windows.first(where: { $0.value === key })?.key else { return nil }
        return workspaces[id]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            NSWindow.allowsAutomaticWindowTabbing = false
            NSApp.setActivationPolicy(.regular)
            fontWarnings = GoogleFontsStore.registerInstalled().failures
            runtime = try TerminalRuntime()
            var records: [WorkspaceArchive.WindowRecord] = []
            do {
                archiveFile = try WorkspaceArchive.defaultFile()
                if let archiveFile, let archive = try WorkspaceArchive.load(from: archiveFile) {
                    projects = archive.projectURLs
                    records = archive.windows
                }
            } catch { storageError = error.localizedDescription }
            if records.isEmpty { try makeWindow(restored: nil) }
            else { for record in records { try makeWindow(restored: record) } }
            if !UserDefaults.standard.bool(forKey: "didReadGettingStarted") { activeWorkspace?.showsWelcome = true }
            restoring = false
            save()
            NotificationCenter.default.addObserver(self, selector: #selector(openRegisteredProject(_:)),
                                                   name: .TrellisOpenRegisteredProject, object: nil)
            scheduler.start()
            automations.start()
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    private func makeWindow(restored: WorkspaceArchive.WindowRecord?, startShell: Bool = true) throws {
        guard let runtime else { return }
        let id = restored?.id ?? UUID()
        let workspace = try Workspace(runtime: runtime, id: id, projects: projects, restored: restored)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        workspaces[id] = workspace
        windows[id] = window
        lastWorkspaceID = id
        workspace.window = window
        workspace.reportStorageError(storageError)
        workspace.onChange = { [weak self] in self?.save() }
        workspace.onOpenSessions = { [weak self] in
            self?.workspaces.values.sorted { $0.id.uuidString < $1.id.uuidString }.flatMap(\.sessions) ?? []
        }
        workspace.onRegisterProject = { [weak self] project in
            guard let self, !projects.contains(project) else { return }
            projects.append(project)
            for workspace in workspaces.values { workspace.updateProjects(projects) }
        }
        window.tabbingMode = .disallowed
        window.title = "Trellis"
        window.minSize = NSSize(width: 1000, height: 680)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: WorkspaceView(workspace: workspace, scheduler: scheduler))
        let frameName = "TrellisWorkspace-" + id.uuidString
        window.setFrameAutosaveName(frameName)
        if !window.setFrameUsingName(frameName) {
            window.setContentSize(NSSize(width: 1280, height: 800))
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        // Restore identities without rerunning agents; always provide a usable shell.
        if startShell { workspace.startWindowShell() }
        refreshWindowChoices()

    }

    func importPreferences(_ preferences: TerminalPreferences, theme: AppTheme?) throws {
        guard let runtime else { throw TerminalRuntime.Failure("Terminal configuration is unavailable") }
        let previous = TerminalPreferences.load()
        var importedTheme = theme
        if importedTheme?.id == "ghostty.import" {
            importedTheme?.id = "custom." + UUID().uuidString
            if let importedTheme { _ = try ThemeCatalog.saveCustom(importedTheme) }
        }
        try runtime.applyPreferences(preferences, appTheme: importedTheme ?? ThemeState.shared.theme)
        preferences.save()
        do { if let importedTheme { try ThemeState.shared.apply(importedTheme) } }
        catch {
            previous.save()
            try runtime.applyPreferences(previous)
            throw error
        }
    }

    func applyTerminalPreferences(_ preferences: TerminalPreferences) {
        do { try runtime?.applyPreferences(preferences) }
        catch { NSAlert(error: error).runModal() }
    }

    func newWindow() {
        do { try makeWindow(restored: nil); save() }
        catch { NSAlert(error: error).runModal() }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            lastWorkspaceID = windows.first(where: { $0.value === window })?.key
            refreshWindowChoices()
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { runtime?.setAppFocus(true) }
    func applicationDidResignActive(_ notification: Notification) { runtime?.setAppFocus(false) }

    @objc private func openRegisteredProject(_ notification: Notification) {
        guard let path = notification.userInfo?["path"] as? String,
              projects.contains(where: { $0.standardizedFileURL.path == path }) else { return }
        let workspace = workspaces.values.first(where: { $0.selectedProject?.path == path }) ?? activeWorkspace
        workspace?.showRegisteredProject(path: path, memory: notification.userInfo?["memory"] as? Bool ?? false)
        workspace?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showWelcome() {
        guard let workspace = activeWorkspace, let window = workspace.window, window.attachedSheet == nil else { return }
        window.makeKeyAndOrderFront(nil)
        workspace.showsWelcome = true
    }
    func toggleSidebar() { commandWorkspace?.showsSidebar.toggle() }
    func toggleInspector() { commandWorkspace?.showsMemory.toggle() }
    func switchSession() { commandWorkspace?.showsSessionSwitcher = true }
    func askNativeAgent() { commandWorkspace?.navigate("agent") }
    func customizeWorkspace() {
        guard let workspace = activeWorkspace, let window = workspace.window, window.attachedSheet == nil else { return }
        window.makeKeyAndOrderFront(nil)
        workspace.showsCustomization = true
    }
    func showDreaming() {
        guard let workspace = activeWorkspace, let window = workspace.window, window.attachedSheet == nil else { return }
        window.makeKeyAndOrderFront(nil)
        workspace.navigate("dream")
    }
    func askCodex() { commandWorkspace?.showsCodexTask = true }
    func showSessions() { commandWorkspace?.showsSessions = true }
    func openProject() { commandWorkspace?.chooseProject() }
    func newSession() {
        commandWorkspace?.window?.makeKeyAndOrderFront(nil)
        commandWorkspace?.requestNewSession()
    }
    func newTerminal() {
        commandWorkspace?.window?.makeKeyAndOrderFront(nil)
        commandWorkspace?.newShell()
    }
    func split(vertical: Bool) { commandWorkspace?.split(vertical: vertical) }
    func toggleMaximizedPane() { commandWorkspace?.toggleMaximizedPane() }
    func balancePanes() { commandWorkspace?.balancePanes() }
    func moveTabToNewWindow() {
        guard let source = commandWorkspace, source.selectedLayout != nil else { return }
        do {
            try makeWindow(restored: nil, startShell: false)
            guard let destination = activeWorkspace, destination !== source else { return }
            if source.moveSelectedTab(to: destination) { destination.window?.makeKeyAndOrderFront(nil); save() }
            else { destination.window?.close(); source.window?.makeKeyAndOrderFront(nil) }
        } catch { NSAlert(error: error).runModal() }
    }
    func moveTab(to id: UUID) {
        guard let source = commandWorkspace, let destination = workspaces[id] else { return }
        if source.moveSelectedTab(to: destination) { destination.window?.makeKeyAndOrderFront(nil); save() }
    }
    private func refreshWindowChoices() {
        windowChoices = workspaces.values.sorted { $0.id.uuidString < $1.id.uuidString }.enumerated().map { index, workspace in
            let title = (workspace.selectedProject?.lastPathComponent ?? "Home") + " · Window \(index + 1)"
            workspace.window?.title = title + " — Trellis"
            return WindowChoice(id: workspace.id, title: title, isCurrent: workspace.id == lastWorkspaceID)
        }
    }
    func adjacentPane(_ offset: Int) { commandWorkspace?.selectAdjacentPane(offset) }
    func adjacentSession(_ offset: Int) { commandWorkspace?.selectAdjacentSession(offset) }
    func launchAgentSetup(_ profile: LaunchProfile, _ arguments: [String]) {
        if activeWorkspace == nil { newWindow() }
        activeWorkspace?.window?.makeKeyAndOrderFront(nil)
        activeWorkspace?.startSession(profile, arguments: arguments)
    }
    func closeStoppedSessions() { commandWorkspace?.closeStoppedSessions() }
    func closeSession() {
        guard let key = NSApp.keyWindow, let id = windows.first(where: { $0.value === key })?.key else {
            NSApp.keyWindow?.performClose(nil); return
        }
        if let session = workspaces[id]?.selectedSession { workspaces[id]?.requestClose(session) }
        else { key.performClose(nil) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let id = windows.first(where: { $0.value === sender })?.key,
              workspaces[id]?.needsStopConfirmation == true else { return true }
        requestStop(window: sender, all: false) { [weak sender] allowed in
            if allowed { sender?.close() }
        }
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard workspaces.values.contains(where: \.needsStopConfirmation) else {
            save(); terminating = true; return .terminateNow
        }
        guard let window = activeWorkspace?.window, window.attachedSheet == nil else { return .terminateCancel }
        requestStop(window: window, all: true) { [weak self] allowed in
            if allowed { self?.save(); self?.terminating = true }
            sender.reply(toApplicationShouldTerminate: allowed)
        }
        return .terminateLater
    }
    private func requestStop(window: NSWindow, all: Bool, completion: @escaping (Bool) -> Void) {
        guard window.attachedSheet == nil else { completion(false); return }
        let alert = NSAlert()
        alert.messageText = all ? "Stop sessions in all windows?" : "Stop sessions in this window?"
        alert.informativeText = "Local processes and Trellis tasks stop; tmux attachments disconnect. Persistent tmux workloads keep running."
        alert.addButton(withTitle: "Stop Sessions")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in completion(response == .alertFirstButtonReturn) }
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        // Retain the last window's stopped identities for the next launch.
        workspaces[id]?.shutdown()
        windows.removeValue(forKey: id)
        workspaces.removeValue(forKey: id)
        refreshWindowChoices()
        if !workspaces.isEmpty { save() }
    }
    private func save() {
        refreshWindowChoices()
        guard !restoring, !terminating, storageError == nil, let archiveFile, !workspaces.isEmpty else { return }
        let archive = WorkspaceArchive(projects: projects, windows: workspaces.values.map(\.snapshot).sorted { $0.id.uuidString < $1.id.uuidString })
        do { try archive.save(to: archiveFile) }
        catch {
            storageError = error.localizedDescription
            for workspace in workspaces.values { workspace.reportStorageError(storageError) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        scheduler.stop()
        automations.stop()
        for workspace in workspaces.values { workspace.shutdown() }
        workspaces.removeAll()
        runtime?.shutdown()
    }
}

struct TerminalPane: View {
    @ObservedObject private var themeState = ThemeState.shared
    let terminal: TerminalView
    @ObservedObject var state: TerminalState
    var showsHeader = true
    var onClose: (() -> Void)? = nil
    var onDetach: (() -> Void)? = nil
    var onSplit: ((Bool) -> Void)? = nil
    var onToggleMaximize: (() -> Void)? = nil
    var isMaximized = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
            HStack {
                Label(state.title, systemImage: "terminal").lineLimit(1)
                Spacer()
                if state.secureInputActive { Label("Secure input", systemImage: "lock.fill").font(.caption) }
                Button { state.isSearching = true } label: { Image(systemName: "magnifyingglass") }
                    .help("Find in Terminal").accessibilityLabel("Find in Terminal")
                Menu {
                    if let onSplit {
                        Button("Split Right") { onSplit(false) }
                        Button("Split Down") { onSplit(true) }
                    }
                    if let onToggleMaximize {
                        Button(isMaximized ? "Restore All Panes" : "Maximize Pane", action: onToggleMaximize)
                    }
                    if let onDetach { Button("Detach", action: onDetach) }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Pane Actions")
                if let onClose { Button("Close Pane", systemImage: "xmark", action: onClose).labelStyle(.iconOnly) }
            }.font(.callout).padding(10)
            }
            if state.isSearching {
                HStack {
                    TextField("Find in terminal", text: $state.query)
                        .focused($searchFocused)
                        .onSubmit { terminal.performBinding("navigate_search:next") }
                        .onExitCommand(perform: closeSearch)
                    Text(matchLabel).font(.caption).monospacedDigit()
                    Button("Previous", systemImage: "chevron.up") { terminal.performBinding("navigate_search:previous") }
                        .labelStyle(.iconOnly)
                    Button("Next", systemImage: "chevron.down") { terminal.performBinding("navigate_search:next") }
                        .labelStyle(.iconOnly)
                    Button("Close Search", systemImage: "xmark", action: closeSearch).labelStyle(.iconOnly)
                }.padding(8)
                .onAppear {
                    search()
                    DispatchQueue.main.async { searchFocused = true }
                }
            }
            Divider()
            TerminalHost(terminal: terminal)
            if let exitCode = state.exitCode {
                Text("Process exited (\(exitCode)). Close this session or start a new one.")
                    .font(.caption).padding(6)
            }
            if let warning = state.warning { Text(warning).font(.caption).foregroundStyle(.orange).padding(6) }
        }
        .background(themeState.theme.map { Color.themeHex($0.colors.surface) } ?? Color(red: 16 / 255, green: 23 / 255, blue: 25 / 255))
        .environment(\.colorScheme, themeState.theme?.appearance == .light ? .light : .dark)
        .onChange(of: state.query) { search() }
    }
    private var matchLabel: String {
        guard let total = state.matchCount else { return state.query.isEmpty ? "" : "Searching…" }
        return "\(state.selectedMatch.map { String($0 + 1) } ?? "–") / \(total)"
    }
    private func search() {
        guard state.isSearching else { return }
        guard !state.query.utf8.contains(0), state.query.utf8.count <= 4096 else {
            state.warning = "Search text must be under 4 KiB and contain no NUL characters."
            return
        }
        state.matchCount = nil
        state.selectedMatch = nil
        terminal.performBinding("search:" + state.query)
    }
    private func closeSearch() {
        terminal.performBinding("end_search")
        state.isSearching = false
        terminal.window?.makeFirstResponder(terminal)
    }
}

private struct TerminalHost: NSViewRepresentable {
    let terminal: TerminalView
    func makeNSView(context: Context) -> TerminalView { terminal }
    func updateNSView(_ nsView: TerminalView, context: Context) {}
}
