import SwiftUI
import Security

struct AppSettings: View {
    @ObservedObject private var themeState = ThemeState.shared
    let onLaunchAgent: (LaunchProfile, [String]) -> Void
    var fontWarnings: [String] = []
    var onImportPreferences: (TerminalPreferences, AppTheme?) throws -> Void = { _, _ in }
    @State private var showsImport = false
    @State private var showsGoogleFonts = false
    @State private var selectedFont = TerminalPreferences.load().fontFamily
    var onTerminalPreferences: (TerminalPreferences) -> Void = { _ in }
    var onShellConfiguration: (ShellConfiguration) -> Void = { _ in }
    @State private var showsThemeBrowser = false
    @State private var themeError: String?
    @State private var showsTerminalPreferences = false
    @State private var showsShellConfiguration = false

    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("modelRoute") private var route = "codex"
    @AppStorage("apiBaseURL") private var baseURL = "https://api.openai.com/v1"
    @AppStorage("apiModel") private var model = ""
    @AppStorage("apiKind") private var api = "responses"
    @AppStorage("codexLaunchModel") private var codexLaunchModel = ""
    @AppStorage("opencodeLaunchModel") private var opencodeLaunchModel = ""
    @State private var key = ""
    @State private var status = ""
    @State private var codexStatus: CodexAccountStatus = .checking
    @State private var installations: [LaunchProfile: String] = [:]

    var body: some View {
        Form {
            Section("Appearance") {
                Button("Import Ghostty Settings…") { showsImport = true }
                Button("App Themes…") { showsThemeBrowser = true }
                Button("Terminal Font, Theme & Keys…") { showsTerminalPreferences = true }
                Button("Download Google Fonts…") { selectedFont = TerminalPreferences.load().fontFamily; showsGoogleFonts = true }
                ForEach(fontWarnings, id: \.self) { warning in Text(warning).font(.caption).foregroundStyle(.orange) }
                Button("Shells…") { showsShellConfiguration = true }
                if themeState.theme == nil {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                } else { Text("Appearance follows your app theme. Use System Appearance in App Themes to restore the separate setting.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Accounts") {
                LabeledContent("Codex · ChatGPT account", value: codexStatus.label)
                HStack {
                    Button("Sign in with ChatGPT") { onLaunchAgent(.codex, ["login"]) }
                    Button("Refresh Status") { Task { await refreshCodexStatus() } }
                }
                Text("Sign-in runs in a Codex terminal session. Codex owns the browser flow and credentials; Trellis checks only the supported CLI status.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("OpenCode Go", value: "Managed by OpenCode")
                LabeledContent("OpenCode Zen", value: "Managed by OpenCode")
                Button("Set Up OpenCode Account") { onLaunchAgent(.opencode, ["auth", "login"]) }
                Text("Go and Zen are separate OpenCode account routes. Configure either through OpenCode's supported provider flow.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Learning and Dreaming") {
                Picker("Model route", selection: $route) {
                    Text("Codex account").tag("codex")
                    Text("Direct API").tag("direct")
                }
                if route == "codex" {
                    Text("Codex owns sign-in and credentials. Interactive sessions use its supported CLI; unattended Dreaming requires the direct no-tools route.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Native Chat & Direct API") {
                    TextField("API base URL", text: $baseURL)
                    Picker("API", selection: $api) {
                        Text("Responses").tag("responses")
                        Text("Chat Completions").tag("chatCompletions")
                    }
                    TextField("Model identifier", text: $model)
                    SecureField("API key (leave blank to keep stored key)", text: $key)
                    HStack {
                        Button("Save Key for This Endpoint") {
                            do {
                                guard !key.isEmpty else { status = "Enter a key to save."; return }
                                try EndpointKey.save(key, endpoint: baseURL)
                                key = ""
                                status = "Key saved in Keychain for this endpoint."
                            } catch { status = error.localizedDescription }
                        }
                        Button("Remove Stored Key") {
                            do { try EndpointKey.remove(endpoint: baseURL); status = "Stored key removed." }
                            catch { status = error.localizedDescription }
                        }
                    }
                    Text("Requests send only the context you review. Nothing is sent when these settings change.")
                        .font(.caption).foregroundStyle(.secondary)
                Text("Trellis Chat uses this endpoint independently of the Learning route above.")
                    .font(.caption).foregroundStyle(.secondary)
                if !status.isEmpty { Text(status).font(.caption) }
            }
            Section("Agents") {
                TextField("Codex model default (optional)", text: $codexLaunchModel)
                TextField("OpenCode provider/model default (optional)", text: $opencodeLaunchModel)
                Text("Blank uses the agent’s own model setting. You can override it in New Session.").font(.caption).foregroundStyle(.secondary)
                ForEach([LaunchProfile.codex, .opencode, .pi, .claude, .gemini]) { profile in
                    LabeledContent(profile.title, value: installations[profile] ?? "Checking…")
                }
                HStack {
                    Link("Codex setup", destination: URL(string: "https://developers.openai.com/codex/auth")!)
                    Link("OpenCode setup", destination: URL(string: "https://opencode.ai/docs/cli/")!)
                    Link("Pi setup", destination: URL(string: "https://pi.dev/")!)
                    Link("Claude Code", destination: URL(string: "https://code.claude.com/docs/en/setup")!)
                    Link("Gemini CLI", destination: URL(string: "https://geminicli.com/docs/get-started/")!)
                }
                Text("Agents inherit their own user and project configuration when Trellis launches them. Trellis does not copy credentials or rewrite agent settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showsGoogleFonts) {
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
        .sheet(isPresented: $showsTerminalPreferences) {
            VStack {
                HStack { Text("Terminal Preferences").font(.title2); Spacer(); Button("Done") { showsTerminalPreferences = false } }.padding()
                TerminalPreferencesView(onChange: onTerminalPreferences)
            }.frame(height: 580)
        }
        .sheet(isPresented: $showsShellConfiguration) {
            VStack {
                HStack { Text("Shells").font(.title2); Spacer(); Button("Done") { showsShellConfiguration = false } }.padding()
                ShellConfigurationView(onChange: onShellConfiguration)
            }.frame(height: 580)
        }
        .sheet(isPresented: $showsImport) {
            VStack {
                HStack { Spacer(); Button("Done") { showsImport = false }.keyboardShortcut(.cancelAction) }.padding([.top, .trailing])
                GhosttyImportView(baselineTheme: themeState.theme, onApply: onImportPreferences)
            }.frame(width: 780, height: 620)
        }
        .sheet(isPresented: $showsThemeBrowser) {
            VStack {
                HStack { Text("App Themes").font(.title2); Spacer(); Button("Use System Appearance") { do { try ThemeState.shared.reset() } catch { themeError = error.localizedDescription } }; Button("Done") { showsThemeBrowser = false } }.padding()
                ThemeBrowser(catalog: ThemeCatalog.load(customDirectory: ThemeCatalog.customThemesDirectory)) { theme, _ in
                    try ThemeState.shared.apply(theme)
                }
                if let themeError { Text(themeError).foregroundStyle(.orange) }
            }.frame(width: 980, height: 720)
        }
        .formStyle(.grouped).padding()
        .tint(themeState.theme.map { Color.themeHex($0.colors.accent) } ?? .accentColor)
        .preferredColorScheme(themeState.theme.map { $0.appearance == .dark ? .dark : .light })
        .frame(width: 620)
        .frame(minHeight: 600, maxHeight: 760)
        .task {
            await refreshCodexStatus()
            await refreshInstallations()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshCodexStatus() }
        }
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
