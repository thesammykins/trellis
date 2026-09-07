import Foundation

@main
enum CustomHarnessCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CustomHarnessStore(fileURL: root.appendingPathComponent("custom-harnesses.json"))
        let profile = try CustomHarness(
            name: "Review tool",
            executable: "/usr/bin/env",
            arguments: ["printf", "%s\\n", "$(touch /tmp/never-ran)", "semi;colon", "two words", "—"]
        )

        try store.save([profile])
        let loaded = try store.load()
        assert(loaded == [profile])

        let exported = try store.exportData(profile)
        let preview = try store.importPreview(from: exported)
        assert(preview == profile)
        assert(preview.arguments[2] == "$(touch /tmp/never-ran)")

        assertThrows { try CustomHarness(name: "", executable: "/bin/echo", arguments: []) }
        assertThrows { try CustomHarness(name: "bad\nname", executable: "/bin/echo", arguments: []) }
        assertThrows { try CustomHarness(name: "relative", executable: "bin/echo", arguments: []) }
        assertThrows { try CustomHarness(name: "dot path", executable: "/bin/../bin/echo", arguments: []) }
        assertThrows { try CustomHarness(name: "nul", executable: "/bin/echo", arguments: ["bad\0arg"]) }
        assertThrows {
            try CustomHarness(name: "many", executable: "/bin/echo",
                              arguments: Array(repeating: "x", count: CustomHarness.maximumArguments + 1))
        }

        assertThrows { try store.importPreview(from: Data("not json".utf8)) }
        let wrongVersion = String(decoding: exported, as: UTF8.self)
            .replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
        assertThrows { try store.importPreview(from: Data(wrongVersion.utf8)) }

        let target = root.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        let linked = root.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: target)
        assertThrows { try CustomHarnessStore(fileURL: linked).save([profile]) }
        let targetContents = try String(contentsOf: target, encoding: .utf8)
        assert(targetContents == "{}")

        print("custom harness checks passed")
    }

    private static func assertThrows(_ operation: () throws -> Any) {
        do {
            _ = try operation()
            preconditionFailure("Expected validation failure")
        } catch {}
    }
}
