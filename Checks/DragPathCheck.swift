import Foundation

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
    }

    private static func assertThrows(_ operation: () throws -> Any) {
        do {
            _ = try operation()
            Swift.preconditionFailure("Expected rejected drop path")
        } catch {}
    }
}
