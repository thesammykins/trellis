import SwiftUI
import Security

// Shared by Settings search and direct links from the agent pane.
enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance, terminal, workspace, agent, team, accounts, shells, automations, learning
    static let openAgentNotification = Notification.Name("TrellisOpenAgentSettings")
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .terminal: "Terminal"
        case .workspace: "Workspace"
        case .agent: "Trellis Agent"
        case .team: "Agent Team"
        case .accounts: "Accounts & Agents"
        case .shells: "Shells"
        case .automations: "Automations"
        case .learning: "Learning & Dreaming"
        }
    }
    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .terminal: "terminal"
        case .workspace: "sidebar.left"
        case .agent: "sparkles"
        case .team: "person.3"
        case .accounts: "person.crop.circle"
        case .shells: "apple.terminal"
        case .automations: "clock.arrow.circlepath"
        case .learning: "moon"
        }
    }
    private var keywords: String {
        switch self {
        case .appearance: "theme color light dark system import ghostty"
        case .terminal: "font size keyboard keybinding shortcut option alt google download"
        case .workspace: "tabs vertical horizontal collapsed sidebar layout density inspector presets"
        case .agent: "native chat direct api endpoint url key credentials model reasoning name connection responses completions"
        case .team: "subagents delegate escalate routing model cache tokens budget context specialist coding explore writing review"
        case .accounts: "codex chatgpt opencode go zen pi claude gemini login sign in installation executable model default"
        case .shells: "shell executable arguments login zsh bash fish"
        case .automations: "schedule cron timer interval daily command task background"
        case .learning: "learning dreaming model route overnight schedule proposals automation"
        }
    }
    func matches(_ query: String) -> Bool {
        let text = title + " " + keywords
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedStandardContains($0) }
    }
}

struct AppSettings: View {
    @ObservedObject private var themeState = ThemeState.shared
    @StateObject private var teamDraft = AgentTeamSettingsDraft()
    let onLaunchAgent: (LaunchProfile, [String]) -> Void
    var fontWarnings: [String] = []
    var onImportPreferences: (TerminalPreferences, AppTheme?) throws -> Void = { _, _ in }
    var onTerminalPreferences: (TerminalPreferences) -> Void = { _ in }
    var onShellConfiguration: (ShellConfiguration) -> Void = { _ in }
    var onCustomizeWorkspace: () -> Void = {}
    var onDreaming: () -> Void = {}
    var onAutomations: () -> Void = {}
    @AppStorage("settingsPage") private var page = SettingsPage.appearance.rawValue
    @State private var search = ""
    @State private var showsImport = false
    @State private var showsGoogleFonts = false
    @State private var selectedFont = TerminalPreferences.load().fontFamily
    @State private var terminalRevision = UUID()
    @State private var showsThemeBrowser = false
    @State private var themeError: String?

    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("verticalTabs") private var verticalTabs = false
    @AppStorage("collapsedTabs") private var collapsedTabs = false
    @AppStorage("nativeAgentName") private var agentName = "Trellis Agent"
    @AppStorage("modelRoute") private var route = "codex"
    @AppStorage("apiBaseURL") private var baseURL = "https://api.openai.com/v1"
    @AppStorage("apiModel") private var model = ""
    @AppStorage("apiKind") private var api = "responses"
    @AppStorage("apiReasoningEffort") private var reasoningEffort = ""
    @AppStorage("codexLaunchModel") private var codexLaunchModel = ""
    @AppStorage("opencodeLaunchModel") private var opencodeLaunchModel = ""
    @State private var credentialRevision = UUID()
    @State private var codexStatus: CodexAccountStatus = .checking
    @State private var installations: [LaunchProfile: String] = [:]

    private var pages: [SettingsPage] { SettingsPage.allCases.filter { $0.matches(search) } }
    private var selectedPage: SettingsPage? {
        pages.first { $0.rawValue == page } ?? pages.first
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    TextField("Search Settings", text: $search).textFieldStyle(.roundedBorder)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear Settings Search")
                    }
                }.padding(12)
                List(selection: Binding(get: { selectedPage?.rawValue }, set: { if let value = $0 { page = value } })) {
                    ForEach(pages) { item in
                        Label(item.title, systemImage: item.symbol).tag(item.rawValue)
                    }
                }.listStyle(.sidebar)
            }.frame(minWidth: 210, idealWidth: 220, maxWidth: 250)

            if let selectedPage {
                VStack(alignment: .leading, spacing: 0) {
                    Text(selectedPage.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
                    settingsContent(selectedPage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView.search(text: search)
            }
        }
        .sheet(isPresented: $showsGoogleFonts, onDismiss: { terminalRevision = UUID() }) {
            VStack(spacing: 0) {
                HStack { Text("Google Fonts").font(.title2); Spacer(); Button("Done") { showsGoogleFonts = false }.keyboardShortcut(.cancelAction) }.padding()
                GoogleFontsView(selectedFamily: selectedFont) { family in
                    var preferences = TerminalPreferences.load()
                    preferences.fontFamily = family
                    preferences.save()
                    selectedFont = family
                    onTerminalPreferences(preferences)
                }
            }.frame(width: 600, height: 600)
        }
        .sheet(isPresented: $showsImport, onDismiss: { terminalRevision = UUID() }) {
            VStack {
                HStack { Spacer(); Button("Done") { showsImport = false }.keyboardShortcut(.cancelAction) }.padding([.top, .trailing])
                GhosttyImportView(baselineTheme: themeState.theme, onApply: onImportPreferences)
            }.frame(width: 780, height: 620)
        }
        .sheet(isPresented: $showsThemeBrowser) {
            VStack {
                HStack { Text("App Themes").font(.title2); Spacer(); Button("Use System Appearance", action: resetTheme); Button("Done") { showsThemeBrowser = false }.keyboardShortcut(.cancelAction) }.padding()
                ThemeBrowser(catalog: ThemeCatalog.load(customDirectory: ThemeCatalog.customThemesDirectory)) { theme, _ in
                    try ThemeState.shared.apply(theme)
                }
                if let themeError { Text(themeError).foregroundStyle(.orange) }
            }.frame(width: 980, height: 720)
        }
        .tint(themeState.theme.map { Color.themeHex($0.colors.accent) } ?? .accentColor)
        .preferredColorScheme(themeState.theme.map { $0.appearance == .dark ? .dark : .light }
            ?? (appearance == "dark" ? .dark : appearance == "light" ? .light : nil))
        .frame(minWidth: 880, idealWidth: 940, minHeight: 620, idealHeight: 700)
        .task(id: selectedPage) {
            guard selectedPage == .accounts else { return }
            await refreshCodexStatus()
            await refreshInstallations()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if selectedPage == .accounts { Task { await refreshCodexStatus() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: SettingsPage.openAgentNotification)) { _ in
            search = ""
        }
        .onChange(of: page) { search = "" }
    }

    @ViewBuilder private func settingsContent(_ page: SettingsPage) -> some View {
        switch page {
        case .appearance: appearancePage
        case .terminal:
            VStack(spacing: 0) {
                TerminalPreferencesView(onChange: onTerminalPreferences).id(terminalRevision)
                HStack {
                    Button("Download Google Fonts…") {
                        selectedFont = TerminalPreferences.load().fontFamily
                        showsGoogleFonts = true
                    }
                    Spacer()
                }.padding(.horizontal, 24).padding(.bottom, 20)
                ForEach(fontWarnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange).padding(.horizontal, 24) }
            }
        case .workspace: workspacePage
        case .agent: agentPage
        case .team:
            AgentTeamSettingsView(store: .shared, draft: teamDraft) { self.page = SettingsPage.agent.rawValue }
        case .accounts: accountsPage
        case .shells: ShellConfigurationView(onChange: onShellConfiguration)
        case .learning: learningPage
        case .automations:
            Form {
                Section("Scheduled Commands") {
                    Text("Run reviewed commands on an interval or daily schedule while Trellis is open. Manage timing, permissions and results in Automations.")
                    Button("Open Automations…", action: onAutomations)
                }
                Section("Project Maintenance") {
                    Text("Dreaming produces memory proposals using its own model and schedule.")
                    Button("Open Project Dreaming…", action: onDreaming)
                }
            }.formStyle(.grouped)
        }
    }

    private var appearancePage: some View {
        Form {
            Section("App Appearance") {
                LabeledContent("Theme", value: themeState.theme?.name ?? "System appearance")
                HStack {
                    Button("Browse App Themes…") { showsThemeBrowser = true }
                    if themeState.theme != nil { Button("Use System Appearance", action: resetTheme) }
                }
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.disabled(themeState.theme != nil)
                if themeState.theme != nil {
                    Text("The selected theme controls appearance. Use System Appearance to choose Light or Dark independently.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let themeError { Text(themeError).foregroundStyle(.orange) }
            }
            Section("Import") {
                Button("Import Ghostty Settings…") { showsImport = true }
                Text("Preview fonts, colors and supported keybindings before applying them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var workspacePage: some View {
        Form {
            Section("Session Tabs") {
                Picker("Tab position", selection: $verticalTabs) {
                    Text("Top").tag(false)
                    Text("Side").tag(true)
                }
                Toggle("Collapse side tabs", isOn: $collapsedTabs).disabled(!verticalTabs)
                Text("Narrow windows also compact side tabs to keep the terminal usable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Layout & Presets") {
                Button("Customize Current Workspace…", action: onCustomizeWorkspace)
                Text("Choose tab details, density, sidebar sections and inspector position. Save a preset or set a project override in the workspace.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Navigation Shortcuts") {
                LabeledContent("Find session", value: "⌘P")
                LabeledContent("New shell", value: "⌘T")
                LabeledContent("New agent session", value: "⇧⌘T")
                LabeledContent("Trellis Agent", value: "⇧⌘A")
                LabeledContent("Toggle sidebar", value: "⌃⌘S")
            }
        }.formStyle(.grouped)
    }

    private var agentPage: some View {
        Form {
            Section("Conversation") {
                TextField("Assistant name", text: $agentName, prompt: Text("Trellis Agent"))
                Text("Connection changes apply to new conversations. Active conversations keep their current connection.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Connection") {
                TextField("API base URL", text: $baseURL)
                Picker("API", selection: $api) {
                    Text("Responses").tag("responses")
                    Text("Chat Completions").tag("chatCompletions")
                }
                EndpointKeyControls(endpoint: baseURL) { credentialRevision = UUID() }
            }
            Section("Model") {
                TextField("Model identifier (manual entry)", text: $model)
                DirectModelCatalogPicker(baseURL: baseURL, apiKey: { try EndpointKey.read(endpoint: baseURL) }, modelID: $model, credentialRevision: credentialRevision)
                Picker("Reasoning effort", selection: $reasoningEffort) {
                    Text("Provider default").tag("")
                    ForEach(DirectModelConfiguration.reasoningEfforts, id: \.self) { Text($0.capitalized).tag($0) }
                }
                Text("Model lookup uses the saved key. Choose a reasoning effort supported by your model; discovery lists identifiers only.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Native chat uses Direct API. ChatGPT subscription sign-in is available through the Codex terminal agent.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }

    private var accountsPage: some View {
        Form {
            Section("Accounts") {
                LabeledContent("Codex · ChatGPT account", value: codexStatus.label)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Codex ChatGPT account").accessibilityValue(codexStatus.label)
                HStack {
                    Button("Sign in with ChatGPT") { onLaunchAgent(.codex, ["login"]) }
                    Button("Refresh Status") { Task { await refreshCodexStatus(); await refreshInstallations() } }
                }
                Text("Codex handles sign-in and credentials in its terminal session.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("OpenCode Go / Zen", value: "Managed by OpenCode")
                Button("Set Up OpenCode Account") { onLaunchAgent(.opencode, ["auth", "login"]) }
                Text("Go and Zen are separate routes in OpenCode’s provider setup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Launch Defaults") {
                TextField("Codex model (optional)", text: $codexLaunchModel)
                TextField("OpenCode provider/model (optional)", text: $opencodeLaunchModel)
                Text("Blank uses the agent’s own setting. Override it in New Session.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Installed Agents") {
                ForEach([LaunchProfile.codex, .opencode, .pi, .claude, .gemini]) { profile in
                    LabeledContent(profile.title, value: installations[profile] ?? "Checking…")
                        .textSelection(.enabled)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(profile.title).accessibilityValue(installations[profile] ?? "Checking")
                }
                DisclosureGroup("Setup Guides") {
                    Link("Codex", destination: URL(string: "https://developers.openai.com/codex/auth")!)
                    Link("OpenCode", destination: URL(string: "https://opencode.ai/docs/cli/")!)
                    Link("Pi", destination: URL(string: "https://pi.dev/")!)
                    Link("Claude Code", destination: URL(string: "https://code.claude.com/docs/en/setup")!)
                    Link("Gemini CLI", destination: URL(string: "https://geminicli.com/docs/get-started/")!)
                }
                Text("Agents keep their own user and project configuration.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var learningPage: some View {
        Form {
            Section("Learning") {
                Picker("Model route", selection: $route) {
                    Text("Codex account").tag("codex")
                    Text("Direct API").tag("direct")
                }
                Button("Configure Direct API…") { page = SettingsPage.agent.rawValue }
                Text("Choose the connection for explanations and suggestions. Native chat always uses Direct API.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dreaming") {
                Button("Open Dreaming for Current Project…", action: onDreaming)
                Text("Review the schedule, limits and last run in your project. Unattended Dreaming requires Direct API and produces proposals for review.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private func resetTheme() {
        do { try themeState.reset(); themeError = nil }
        catch { themeError = error.localizedDescription }
    }

    private func refreshCodexStatus() async {
        codexStatus = .checking
        codexStatus = await CodexAccountStatus.refresh()
    }

    private func refreshInstallations() async {
        for profile in [LaunchProfile.codex, .opencode, .pi, .claude, .gemini] {
            do {
                let installation = try await AgentInstallation.inspect(profile)
                installations[profile] = "\(installation.version) · \(installation.executable)"
            } catch {
                installations[profile] = "Not found"
            }
        }
    }
}

struct EndpointKeyControls: View {
    let endpoint: String
    var onChange: () -> Void = {}
    @State private var key = ""
    @State private var status = ""
    @State private var credentialStatus = "Checking…"
    @State private var showsKeyEditor = false

    var body: some View {
        Group {
            LabeledContent("Saved credential", value: credentialStatus)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Saved credential").accessibilityValue(credentialStatus)
            DisclosureGroup("Manage API Key", isExpanded: $showsKeyEditor) {
                SecureField("API key (leave blank to keep stored key)", text: $key)
                ViewThatFits(in: .horizontal) {
                    HStack { keyActions }
                    VStack(alignment: .leading) { keyActions }
                }
                Text("Keys are stored in Keychain for this exact endpoint.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
        }
        .onAppear { refreshKeyPresence() }
        .onChange(of: endpoint) {
            key = ""
            status = ""
            showsKeyEditor = false
            refreshKeyPresence()
        }
        .onDisappear { key = "" }
    }

    private var keyActions: some View {
        Group {
            Button("Save Key for This Endpoint", action: saveKey).disabled(key.isEmpty)
            Button("Remove Stored Key", role: .destructive, action: removeKey)
                .disabled(credentialStatus != "Saved for this endpoint")
        }.fixedSize()
    }

    private func saveKey() {
        do {
            guard !key.isEmpty else { status = "Enter a key to save."; announce(status); return }
            try EndpointKey.save(key, endpoint: endpoint)
            key = ""
            credentialStatus = "Saved for this endpoint"; onChange()
            status = "Key saved for this endpoint."
            announce(status)
        } catch { status = error.localizedDescription; announce("Key could not be saved") }
    }

    private func removeKey() {
        do {
            try EndpointKey.remove(endpoint: endpoint)
            key = ""
            credentialStatus = "Not saved"; onChange()
            status = "Saved key removed for this endpoint."
            announce(status)
        } catch { status = error.localizedDescription; announce("Saved key could not be removed") }
    }

    private func refreshKeyPresence() {
        do {
            credentialStatus = try EndpointKey.isSaved(endpoint: endpoint) ? "Saved for this endpoint" : "Not saved"
        } catch {
            credentialStatus = "Unavailable"
            status = "Saved key status unavailable: " + error.localizedDescription
            announce("Saved key status unavailable")
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

enum EndpointKey {
    private static let service = (Bundle.main.bundleIdentifier ?? "in.sammyk.trellis") + ".endpoint"
    private static func query(_ endpoint: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: endpoint]
    }
    static func save(_ key: String, endpoint: String) throws {
        guard key.utf8.count <= 16_384, !key.utf8.contains(0), endpoint.utf8.count <= 4096 else {
            throw Failure("Invalid endpoint or key length.")
        }
        let value = Data(key.utf8)
        let status = SecItemUpdate(query(endpoint) as CFDictionary, [kSecValueData: value] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(endpoint)
            attributes[kSecValueData as String] = value
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(attributes as CFDictionary, nil))
        } else { try check(status) }
    }
    // Presence must not read secret bytes or trigger a Keychain access prompt while typing an endpoint.
    static func isSaved(endpoint: String) throws -> Bool {
        let status = SecItemCopyMatching(query(endpoint) as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }
    static func read(endpoint: String) throws -> String {
        var attributes = query(endpoint)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        try check(status)
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw Failure("The stored API key could not be decoded.")
        }
        return value
    }
    static func remove(endpoint: String) throws {
        let status = SecItemDelete(query(endpoint) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw Failure("Keychain operation failed (\(status)).") }
    }
    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
