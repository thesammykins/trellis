import AppKit

@main
enum DragPathCheck {
    static func main() throws {
        let quoted = try TerminalView.quotedDropText([
            URL(fileURLWithPath: "/tmp/a b/../it's.txt"),
            URL(fileURLWithPath: "/tmp/plain"),
        ])
        precondition(quoted == "'/tmp/it'\\''s.txt' '/tmp/plain'")

        assertThrows { try TerminalView.quotedDropText([URL(fileURLWithPath: "/tmp/bad\nname")]) }
        assertThrows { try TerminalView.quotedDropText([URL(fileURLWithPath: "/" + String(repeating: "a", count: 65_536))]) }

        let command = "printf '%s' 'reviewed 👋'; pwd"
        let validated = try TerminalView.validatedAgentCommand(command)
        precondition(validated == command)
        for invalid in ["", "  ", "echo first\necho second", "echo\r", "echo\t", "\u{1b}[A", "a\u{2028}b", String(repeating: "a", count: 4_097)] {
            assertThrows { try TerminalView.validatedAgentCommand(invalid) }
        }
        try checkReviewedCommandAuthorization()
    }

    @MainActor
    private static func checkReviewedCommandAuthorization() throws {
        // Without a window this view never creates a Ghostty surface or uses the placeholder app handle.
        let app = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { app.deallocate() }
        let terminal = TerminalView(app: app, workingDirectory: "/tmp", command: "", envelopePath: "")
        var inputCount = 0
        terminal.onUserInput = { inputCount += 1 }
        let command = "printf reviewed"
        let confirmation = "Confirm the empty shell prompt again"
        assertThrows(containing: confirmation) { try terminal.runReviewedCommand(command) }
        try terminal.authorizeReviewedCommand(command)
        assertThrows(containing: confirmation) { try terminal.runReviewedCommand("printf different") }
        assertThrows(containing: confirmation) { try terminal.runReviewedCommand(command) }
        try terminal.authorizeReviewedCommand(command)
        assertThrows { try terminal.authorizeReviewedCommand("bad\ncommand") }
        assertThrows(containing: confirmation) { try terminal.runReviewedCommand(command) }

        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7)!
        let mouse = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        let edits: [() -> Void] = [
            { terminal.keyDown(with: key) },
            { terminal.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0)) },
            { terminal.setMarkedText("x", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)) },
            { terminal.paste(nil) },
            { terminal.mouseDown(with: mouse) },
            { terminal.mouseUp(with: mouse) },
            { terminal.mouseDragged(with: mouse) },
            { terminal.scrollWheel(with: mouse) },
        ]
        for edit in edits {
            try terminal.authorizeReviewedCommand(command)
            edit()
            assertThrows(containing: confirmation) { try terminal.runReviewedCommand(command) }
        }
        precondition(inputCount == edits.count)
        try terminal.authorizeReviewedCommand(command)
        assertThrows(containing: "live and visible") { try terminal.runReviewedCommand(command) }
        assertThrows(containing: confirmation) { try terminal.runReviewedCommand(command) }
    }

    private static func assertThrows(containing message: String? = nil, _ operation: () throws -> Any) {
        do {
            _ = try operation()
            Swift.preconditionFailure("Expected rejected terminal input")
        } catch {
            if let message { precondition(error.localizedDescription.contains(message), error.localizedDescription) }
        }
    }
}
