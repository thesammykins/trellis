import AppKit
import Carbon
import GhosttyKit
import OSLog

/// M0 native host. Ghostty owns the PTY; the runtime owns this view's lifetime.
@MainActor
final class TerminalView: NSView, @MainActor NSTextInputClient, NSMenuItemValidation {
    private let app: ghostty_app_t
    private let workingDirectory: String
    private let command: String
    private let envelopePath: String
    private let environment: [String: String]
    private var stopped = false
    private var focusWhenAttached = false
    private var attemptedCreation = false
    private var markedText = ""
    private var accumulatedText: [String]?
    private var tracking: NSTrackingArea?
    private var windowObservers: [NSObjectProtocol] = []
    private(set) var surface: ghostty_surface_t?
    var canShareContext: (() -> Bool)?
    var onClose: (() -> Void)?
    var onSessionFocused: (() -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    var onSearchRequested: (() -> Void)?
    private let logger = Logger(subsystem: "in.sammyk.trellis.dev", category: "TerminalView")

    init(app: ghostty_app_t, workingDirectory: String, command: String, envelopePath: String, environment: [String: String] = [:]) {
        self.app = app
        self.workingDirectory = workingDirectory
        self.command = command
        self.envelopePath = envelopePath
        self.environment = environment
        super.init(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowChanges()
        guard let window, !stopped else { updateFocus(); return }
        var createdSurface = false
        if !attemptedCreation {
            attemptedCreation = true
            var configuration = ghostty_surface_config_new()
            configuration.platform_tag = GHOSTTY_PLATFORM_MACOS
            configuration.platform.macos.nsview = Unmanaged.passUnretained(self).toOpaque()
            configuration.userdata = Unmanaged.passUnretained(self).toOpaque()
            configuration.scale_factor = window.backingScaleFactor
            surface = workingDirectory.withCString { directory in
                command.withCString { command in
                    configuration.working_directory = directory
                    configuration.command = command
                    var environment = self.environment
                    environment["TRELLIS_LAUNCH_ENVELOPE"] = envelopePath
                    environment["PATH"] = AgentInstallation.searchPath
                    let entries = environment.sorted { $0.key < $1.key }
                    let strings = entries.flatMap { [strdup($0.key), strdup($0.value)] }
                    defer { strings.forEach { free($0) } }
                    guard strings.allSatisfy({ $0 != nil }) else { return nil }
                    var variables = entries.indices.map { index in
                        ghostty_env_var_s(key: UnsafePointer(strings[index * 2]!), value: UnsafePointer(strings[index * 2 + 1]!))
                    }
                    return variables.withUnsafeMutableBufferPointer { buffer in
                        configuration.env_vars = buffer.baseAddress
                        configuration.env_var_count = buffer.count
                        return ghostty_surface_new(app, &configuration)
                    }
                }
            }
            if surface == nil {
                attemptedCreation = false
                logger.error("Ghostty surface creation failed")
                let alert = NSAlert()
                alert.messageText = "The terminal could not start"
                alert.informativeText = "Ghostty could not create its surface. Check the development log and packaged resources."
                alert.beginSheetModal(for: window)
                return
            }
            createdSurface = true
        }
        updateGeometry()
        updateOcclusion()
        updateFocus()
        if createdSurface || focusWhenAttached {
            focusWhenAttached = false
            window.makeFirstResponder(self)
        }
    }

    func requestFocus() {
        focusWhenAttached = true
        if let window {
            focusWhenAttached = false
            window.makeFirstResponder(self)
        }
    }

    /// Called before the runtime frees its Ghostty app. Detaching the view is not stopping a session.
    func shutdown() {
        guard !stopped else { return }
        stopped = true
        removeWindowObservers()
        if let surface {
            self.surface = nil
            ghostty_surface_free(surface)
        }
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateGeometry()
    }

    private func observeWindowChanges() {
        removeWindowObservers()
        guard let window else { return }
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateGeometry() }
            },
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateOcclusion() }
            },
        ]
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateFocus() }
            })
        }
        updateOcclusion()
    }

    private func updateFocus() {
        let focused = window?.isKeyWindow == true && window?.firstResponder === self
        if let surface { ghostty_surface_set_focus(surface, focused) }
        onFocusChanged?(focused)
        if focused { onSessionFocused?() }
    }

    private func removeWindowObservers() {
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
    }

    private func updateOcclusion() {
        guard let surface, let window else { return }
        ghostty_surface_set_occlusion(surface, window.occlusionState.contains(.visible))
    }

    private func updateGeometry() {
        guard let surface, let window else { return }
        let pixels = convertToBacking(bounds).size
        guard pixels.width.isFinite, pixels.height.isFinite,
              pixels.width > 0, pixels.height > 0,
              pixels.width < Double(UInt32.max), pixels.height < Double(UInt32.max) else { return }
        ghostty_surface_set_content_scale(surface, window.backingScaleFactor, window.backingScaleFactor)
        ghostty_surface_set_size(surface, UInt32(pixels.width), UInt32(pixels.height))
        if let display = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            ghostty_surface_set_display_id(surface, display.uint32Value)
        }
        ghostty_surface_refresh(surface)
    }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        let focused = window?.isKeyWindow == true
        if let surface { ghostty_surface_set_focus(surface, focused) }
        onFocusChanged?(focused)
        if focused { onSessionFocused?() }
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        if let surface { ghostty_surface_set_focus(surface, false) }
        onFocusChanged?(false)
        return true
    }

    private func modifiers(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var result: UInt32 = 0
        for (flag, value) in [(NSEvent.ModifierFlags.shift, GHOSTTY_MODS_SHIFT),
                              (.control, GHOSTTY_MODS_CTRL), (.option, GHOSTTY_MODS_ALT),
                              (.command, GHOSTTY_MODS_SUPER), (.capsLock, GHOSTTY_MODS_CAPS)] {
            if flags.contains(flag) { result |= value.rawValue }
        }
        return ghostty_input_mods_e(rawValue: result)
    }

    override func keyDown(with event: NSEvent) {
        guard let surface else { return }
        let translated = ghostty_surface_key_translation_mods(surface, modifiers(event.modifierFlags))
        var flags = event.modifierFlags
        for (flag, value) in [(NSEvent.ModifierFlags.shift, GHOSTTY_MODS_SHIFT),
                              (.control, GHOSTTY_MODS_CTRL), (.option, GHOSTTY_MODS_ALT),
                              (.command, GHOSTTY_MODS_SUPER)] {
            if translated.rawValue & value.rawValue != 0 { flags.insert(flag) }
            else { flags.remove(flag) }
        }
        // Preserve the original NSEvent when possible; AppKit composition depends on its identity.
        let inputEvent = flags == event.modifierFlags ? event : NSEvent.keyEvent(
            with: event.type, location: event.locationInWindow, modifierFlags: flags,
            timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
            characters: event.characters(byApplyingModifiers: flags) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat, keyCode: event.keyCode) ?? event
        accumulatedText = []
        defer { accumulatedText = nil }
        let wasComposing = hasMarkedText()
        let keyboardLayoutBefore = wasComposing ? nil : Self.keyboardLayoutID
        interpretKeyEvents([inputEvent])
        guard wasComposing || keyboardLayoutBefore == Self.keyboardLayoutID else { return }
        syncPreedit()
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        if let accumulatedText, !accumulatedText.isEmpty {
            for text in accumulatedText { sendKey(event, action: action, text: text, translatedFlags: flags) }
        } else {
            sendKey(event, action: action, composing: wasComposing || hasMarkedText(), translatedFlags: flags)
        }
    }

    private static var keyboardLayoutID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return unsafeBitCast(value, to: CFString.self) as String
    }

    override func keyUp(with event: NSEvent) { sendKey(event, action: GHOSTTY_ACTION_RELEASE) }

    override func flagsChanged(with event: NSEvent) {
        guard !hasMarkedText() else { return }
        let flag: NSEvent.ModifierFlags
        switch event.keyCode {
        case 56, 60: flag = .shift
        case 59, 62: flag = .control
        case 58, 61: flag = .option
        case 55, 54: flag = .command
        case 57: flag = .capsLock
        default: return
        }
        sendKey(event, action: event.modifierFlags.contains(flag) ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE)
    }

    private func sendKey(_ event: NSEvent, action: ghostty_input_action_e,
                         text: String? = nil, composing: Bool = false,
                         translatedFlags: NSEvent.ModifierFlags? = nil) {
        guard let surface else { return }
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(event.keyCode)
        key.mods = modifiers(event.modifierFlags)
        key.consumed_mods = modifiers((translatedFlags ?? event.modifierFlags).subtracting([.control, .command]))
        key.composing = composing
        if event.type == .keyDown || event.type == .keyUp {
            key.unshifted_codepoint = event.characters(byApplyingModifiers: [])?.unicodeScalars.first?.value ?? 0
        }
        if let text, let first = text.unicodeScalars.first,
           first.value >= 0x20, !(0xF700...0xF8FF).contains(first.value) {
            text.withCString { key.text = $0; _ = ghostty_surface_key(surface, key) }
        } else {
            _ = ghostty_surface_key(surface, key)
        }
    }

    override func doCommand(by selector: Selector) {
        // Control keys are encoded by Ghostty after AppKit's input interpretation.
    }

    func hasMarkedText() -> Bool { !markedText.isEmpty }
    func markedRange() -> NSRange {
        hasMarkedText() ? NSRange(location: 0, length: markedText.utf16.count) : NSRange(location: NSNotFound, length: 0)
    }
    func selectedRange() -> NSRange {
        guard let surface else { return NSRange(location: NSNotFound, length: 0) }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return NSRange(location: NSNotFound, length: 0) }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
    }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let text = (string as? NSAttributedString)?.string ?? string as? String else { return }
        markedText = text
        if accumulatedText == nil { syncPreedit() }
    }
    func unmarkText() { markedText = ""; syncPreedit() }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard range.length > 0 else { return nil }
        guard let text = accessibilitySelectedText(), !text.isEmpty else { return nil }
        let selection = selectedRange()
        guard selection.location != NSNotFound else { return nil }
        actualRange?.pointee = selection
        return NSAttributedString(string: text)
    }
    // ponytail: cursor-only hit testing for M0; add range hit testing when implementing Quick Look.
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface, let window else { return .zero }
        var x = 0.0, y = 0.0, width = 0.0, height = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        actualRange?.pointee = range
        if range.length == 0 { width = 0 }
        let rectangle = NSRect(x: x, y: bounds.height - y, width: width, height: height)
        return window.convertToScreen(convert(rectangle, to: nil))
    }
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = (string as? NSAttributedString)?.string ?? string as? String else { return }
        unmarkText()
        if accumulatedText != nil { accumulatedText?.append(text) }
        else if let surface { text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) } }
    }
    private func syncPreedit() {
        guard let surface else { return }
        if markedText.isEmpty { ghostty_surface_preedit(surface, nil, 0) }
        else { markedText.withCString { ghostty_surface_preedit(surface, $0, UInt(markedText.utf8.count)) } }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
    }
    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, modifiers(event.modifierFlags))
    }
    private func mouseButton(_ event: NSEvent, _ state: ghostty_input_mouse_state_e, _ button: ghostty_input_mouse_button_e) {
        guard let surface else { return }
        if state == GHOSTTY_MOUSE_PRESS { window?.makeFirstResponder(self) }
        mouseMoved(with: event)
        _ = ghostty_surface_mouse_button(surface, state, button, modifiers(event.modifierFlags))
    }
    override func mouseDown(with event: NSEvent) { mouseButton(event, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT) }
    override func mouseUp(with event: NSEvent) { mouseButton(event, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT) }
    override func rightMouseDown(with event: NSEvent) { mouseButton(event, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT) }
    override func rightMouseUp(with event: NSEvent) { mouseButton(event, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT) }
    override func otherMouseDown(with event: NSEvent) { mouseButton(event, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_MIDDLE) }
    override func otherMouseUp(with event: NSEvent) { mouseButton(event, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE) }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func otherMouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        let momentum: Int32
        switch event.momentumPhase {
        case .began: momentum = 1
        case .stationary: momentum = 2
        case .changed: momentum = 3
        case .ended: momentum = 4
        case .cancelled: momentum = 5
        case .mayBegin: momentum = 6
        default: momentum = 0
        }
        let precision: Int32 = event.hasPreciseScrollingDeltas ? 1 : 0
        ghostty_surface_mouse_scroll(surface, event.scrollingDeltaX, event.scrollingDeltaY, precision | momentum << 1)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        do {
            insertText(try Self.quotedDropText(urls), replacementRange: NSRange(location: NSNotFound, length: 0))
            return true
        } catch {
            let alert = NSAlert(error: error)
            if let window { alert.beginSheetModal(for: window) }
            else { alert.runModal() }
            return false
        }
    }

    static func quotedDropText(_ urls: [URL]) throws -> String {
        let paths = urls.map { $0.standardizedFileURL.path }
        guard !paths.contains(where: { path in
            path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }) else { throw DropError.controlCharacter }
        let result = paths.map(shellQuote).joined(separator: " ")
        guard result.utf8.count <= 65_536 else { throw DropError.tooLarge }
        return result
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private enum DropError: LocalizedError {
        case controlCharacter
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .controlCharacter: "A dropped file path contains a control character and cannot be inserted safely."
            case .tooLarge: "The dropped file paths are too large to insert safely."
            }
        }
    }

    @IBAction func copy(_ sender: Any?) { performBinding("copy_to_clipboard") }
    @IBAction func paste(_ sender: Any?) { performBinding("paste_from_clipboard") }
    @IBAction override func selectAll(_ sender: Any?) { performBinding("select_all") }
    @IBAction func performFindPanelAction(_ sender: Any?) { onSearchRequested?() }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let surface else { return false }
        switch item.action {
        case #selector(copy(_:)):
            return ghostty_surface_has_selection(surface)
        case #selector(paste(_:)):
            return NSPasteboard.general.canReadItem(withDataConformingToTypes: ["public.utf8-plain-text"])
        case #selector(selectAll(_:)):
            return true
        case #selector(performFindPanelAction(_:)):
            return onSearchRequested != nil
        default:
            return false
        }
    }
    func performBinding(_ action: String) {
        guard let surface else { return }
        if !action.withCString({ ghostty_surface_binding_action(surface, $0, UInt(action.utf8.count)) }) {
            logger.notice("Terminal binding was not handled: \(action, privacy: .public)")
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityLabel() -> String? { "Terminal" }
    override func accessibilitySelectedTextRange() -> NSRange { selectedRange() }
    override func accessibilitySelectedText() -> String? {
        guard let surface else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }
    /// Capture only the currently visible viewport after an explicit UI request.
    func agentContextText() -> String? {
        guard canShareContext?() == true, let surface else { return nil }
        var selection = ghostty_selection_s()
        selection.top_left.tag = GHOSTTY_POINT_VIEWPORT
        selection.top_left.coord = GHOSTTY_POINT_COORD_TOP_LEFT
        selection.bottom_right.tag = GHOSTTY_POINT_VIEWPORT
        selection.bottom_right.coord = GHOSTTY_POINT_COORD_BOTTOM_RIGHT
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        let value = String(cString: text.text)
        return String(decoding: value.utf8.prefix(16_384), as: UTF8.self)
    }

    override func accessibilityValue() -> Any? {
        guard let surface else { return nil }
        var selection = ghostty_selection_s()
        selection.top_left.tag = GHOSTTY_POINT_SCREEN
        selection.top_left.coord = GHOSTTY_POINT_COORD_TOP_LEFT
        selection.bottom_right.tag = GHOSTTY_POINT_SCREEN
        selection.bottom_right.coord = GHOSTTY_POINT_COORD_BOTTOM_RIGHT
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }
}
