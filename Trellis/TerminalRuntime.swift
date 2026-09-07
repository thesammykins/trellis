import AppKit
import GhosttyKit
import Carbon
import OSLog

@MainActor
final class TerminalRuntime {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    private static weak var current: TerminalRuntime?
    private(set) var app: ghostty_app_t!
    private var states: [ObjectIdentifier: TerminalState] = [:]
    private let secureInput = SecureInputController()
    private let logger = Logger(subsystem: "in.sammyk.trellis.dev", category: "TerminalRuntime")
    private struct PendingPaste {
        let surface: ghostty_surface_t
        let state: UnsafeMutableRawPointer?
        let text: String
    }
    private var keyboardObserver: NSObjectProtocol?
    private var pendingPastes: [ObjectIdentifier: PendingPaste] = [:]

    init() throws {
        guard let resources = Bundle.main.resourcePath else { throw Failure("Missing resources") }
        setenv("GHOSTTY_RESOURCES_DIR", resources + "/ghostty", 1)
        setenv("TERMINFO", resources + "/terminfo", 1)
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            throw Failure("Ghostty initialization failed")
        }
        guard let config = ghostty_config_new() else { throw Failure("Ghostty configuration failed") }
        defer { ghostty_config_free(config) }
        (resources + "/terminal.config").withCString { ghostty_config_load_file(config, $0) }
        try Self.loadPreferences(TerminalPreferences.load(), into: config)
        try Self.loadAppTheme(ThemeState.shared.theme, into: config)
        ghostty_config_finalize(config)
        let count = ghostty_config_diagnostics_count(config)
        guard count == 0 else {
            let diagnostic = ghostty_config_get_diagnostic(config, 0)
            throw Failure(diagnostic.message.map { String(cString: $0) } ?? "Invalid terminal configuration")
        }
        var callbacks = ghostty_runtime_config_s()
        callbacks.supports_selection_clipboard = false
        callbacks.wakeup_cb = { _ in
            DispatchQueue.main.async {
                if let app = TerminalRuntime.current?.app { ghostty_app_tick(app) }
            }
        }
        callbacks.action_cb = { _, target, action in
            MainActor.assumeIsolated { TerminalRuntime.current?.handle(target, action) ?? false }
        }
        callbacks.read_clipboard_cb = { userdata, clipboard, state in
            MainActor.assumeIsolated {
                guard clipboard == GHOSTTY_CLIPBOARD_STANDARD,
                      let view = TerminalRuntime.view(userdata), let surface = view.surface,
                      let text = NSPasteboard.general.string(forType: .string) else { return false }
                guard !text.utf8.contains(0) else {
                    TerminalRuntime.current?.states[ObjectIdentifier(view)]?.warning = "Clipboard text contains a NUL character and was not pasted."
                    return false
                }
                text.withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, false) }
                return true
            }
        }
        callbacks.confirm_read_clipboard_cb = { userdata, text, state, _ in
            MainActor.assumeIsolated {
                guard let view = TerminalRuntime.view(userdata) else { return }
                TerminalRuntime.current?.confirmPaste(view, text: text.map { String(cString: $0) } ?? "", state: state)
            }
        }
        callbacks.write_clipboard_cb = { _, clipboard, content, count, confirm in
            MainActor.assumeIsolated {
                // The development policy denies terminal-originated writes. Explicit Copy remains supported.
                guard !confirm, clipboard == GHOSTTY_CLIPBOARD_STANDARD, let content else { return }
                for index in 0..<count {
                    guard let mime = content[index].mime, String(cString: mime) == "text/plain",
                          let value = content[index].data else { continue }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(String(cString: value), forType: .string)
                    break
                }
            }
        }
        callbacks.close_surface_cb = { userdata, _ in
            MainActor.assumeIsolated {
                guard let view = TerminalRuntime.view(userdata) else { return }
                DispatchQueue.main.async { [weak view] in view?.onClose?() }
            }
        }
        guard let app = ghostty_app_new(&callbacks, config) else { throw Failure("Ghostty app creation failed") }
        self.app = app
        ThemeState.shared.applyTerminal = { [weak self] theme in try self?.applyPreferences(TerminalPreferences.load(), appTheme: theme) }
        Self.current = self
        keyboardObserver = NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if let app = self?.app { ghostty_app_keyboard_changed(app) }
            }
        }
        ghostty_app_set_focus(app, NSApp.isActive)
    }

    private static func loadPreferences(_ preferences: TerminalPreferences, into config: ghostty_config_t) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-config-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("preferences.config")
        try preferences.ghosttyConfiguration().write(to: file, atomically: true, encoding: .utf8)
        file.path.withCString { ghostty_config_load_file(config, $0) }
    }

    private static func loadAppTheme(_ theme: AppTheme?, into config: ghostty_config_t) throws {
        guard let theme else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-theme-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("theme.config")
        try theme.ghosttyColorConfiguration().write(to: file, atomically: true, encoding: .utf8)
        file.path.withCString { ghostty_config_load_file(config, $0) }
    }

    func applyPreferences(_ preferences: TerminalPreferences, appTheme: AppTheme? = ThemeState.shared.theme) throws {
        guard let app, let resources = Bundle.main.resourcePath, let config = ghostty_config_new() else {
            throw Failure("Terminal configuration is unavailable")
        }
        defer { ghostty_config_free(config) }
        (resources + "/terminal.config").withCString { ghostty_config_load_file(config, $0) }
        try Self.loadPreferences(preferences, into: config)
        try Self.loadAppTheme(appTheme, into: config)
        ghostty_config_finalize(config)
        guard ghostty_config_diagnostics_count(config) == 0 else {
            throw Failure(ghostty_config_get_diagnostic(config, 0).message.map { String(cString: $0) } ?? "Invalid terminal preferences")
        }
        ghostty_app_update_config(app, config)
    }

    private static func view(_ userdata: UnsafeMutableRawPointer?) -> TerminalView? {
        userdata.map { Unmanaged<TerminalView>.fromOpaque($0).takeUnretainedValue() }
    }

    func register(_ view: TerminalView, state: TerminalState) {
        let id = ObjectIdentifier(view)
        states[id] = state
        view.onFocusChanged = { [weak self, weak state] focused in
            state?.focused = focused
            self?.updateSecureInput()
        }
        view.onSearchRequested = { [weak state] in state?.isSearching = true }
    }

    func unregister(_ view: TerminalView) {
        let id = ObjectIdentifier(view)
        finishPaste(id, allowed: false)
        states.removeValue(forKey: id)
        view.onFocusChanged = nil
        updateSecureInput()
    }

    func setAppFocus(_ focused: Bool) {
        if let app { ghostty_app_set_focus(app, focused) }
        updateSecureInput(appActive: focused)
    }

    private func updateSecureInput(appActive: Bool = NSApp.isActive) {
        let requested = appActive && states.values.contains { $0.focused && $0.secureInputRequested }
        let status = secureInput.update(requested: requested)
        for state in states.values {
            state.secureInputActive = secureInput.enabled && state.focused && state.secureInputRequested
            if status != noErr { state.warning = "Secure keyboard entry failed (\(status))." }
        }
        if status != noErr { logger.error("Secure input update failed: \(status)") }
    }

    private func handle(_ target: ghostty_target_s, _ action: ghostty_action_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface,
              let view = Self.view(ghostty_surface_userdata(surface)),
              let state = states[ObjectIdentifier(view)] else { return false }
        switch action.tag {
        case GHOSTTY_ACTION_START_SEARCH:
            let query = action.action.start_search.needle.map { String(cString: $0) }
            DispatchQueue.main.async { [weak state] in
                if let query, !query.isEmpty { state?.query = query }
                state?.isSearching = true
            }
        case GHOSTTY_ACTION_END_SEARCH:
            DispatchQueue.main.async { [weak state] in state?.isSearching = false }
        case GHOSTTY_ACTION_SEARCH_TOTAL:
            let total = action.action.search_total.total
            DispatchQueue.main.async { [weak state] in state?.matchCount = total >= 0 ? total : nil }
        case GHOSTTY_ACTION_SEARCH_SELECTED:
            let selected = action.action.search_selected.selected
            DispatchQueue.main.async { [weak state] in state?.selectedMatch = selected >= 0 ? selected : nil }
        case GHOSTTY_ACTION_PWD:
            if let pwd = action.action.pwd.pwd {
                let path = String(cString: pwd)
                if path.hasPrefix("/"), path.utf8.count <= 4096 { state.workingDirectory = path }
            }
        case GHOSTTY_ACTION_SET_TITLE:
            if let title = action.action.set_title.title {
                state.title = String(cString: title)
            }
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            state.exitCode = action.action.child_exited.exit_code
        case GHOSTTY_ACTION_SECURE_INPUT:
            switch action.action.secure_input {
            case GHOSTTY_SECURE_INPUT_ON: state.secureInputRequested = true
            case GHOSTTY_SECURE_INPUT_OFF: state.secureInputRequested = false
            case GHOSTTY_SECURE_INPUT_TOGGLE: state.secureInputRequested.toggle()
            default: return false
            }
            updateSecureInput()
        case GHOSTTY_ACTION_RING_BELL: NSSound.beep()
        case GHOSTTY_ACTION_CLOSE_WINDOW, GHOSTTY_ACTION_CLOSE_TAB:
            DispatchQueue.main.async { [weak view] in view?.onClose?() }
        default: return false
        }
        return true
    }

    private func confirmPaste(_ view: TerminalView, text: String, state: UnsafeMutableRawPointer?) {
        guard let surface = view.surface else { return }
        let id = ObjectIdentifier(view)
        guard let window = view.window, window.attachedSheet == nil, pendingPastes[id] == nil else {
            "".withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, true) }
            return
        }
        pendingPastes[id] = PendingPaste(surface: surface, state: state, text: text)
        let alert = NSAlert()
        alert.messageText = "Paste multiple lines into this terminal?"
        alert.informativeText = "Pasted line breaks may execute commands. Review the clipboard contents before continuing."
        let preview = NSTextField(wrappingLabelWithString: String(text.prefix(1000)))
        preview.isSelectable = true
        preview.frame = NSRect(x: 0, y: 0, width: 380, height: 100)
        alert.accessoryView = preview
        alert.addButton(withTitle: "Paste")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.finishPaste(id, allowed: response == .alertFirstButtonReturn)
        }
    }

    private func finishPaste(_ id: ObjectIdentifier, allowed: Bool) {
        guard let request = pendingPastes.removeValue(forKey: id) else { return }
        let text = allowed ? request.text : ""
        text.withCString { ghostty_surface_complete_clipboard_request(request.surface, $0, request.state, true) }
    }

    func shutdown() {
        guard let app else { return }
        for id in Array(pendingPastes.keys) { finishPaste(id, allowed: false) }
        states.removeAll()
        updateSecureInput(appActive: false)
        if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
        keyboardObserver = nil
        self.app = nil
        Self.current = nil
        ghostty_app_free(app)
    }
}
