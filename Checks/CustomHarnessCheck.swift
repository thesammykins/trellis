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
        assert(preview.integration == nil)

        let legacyProfile = #"{"id":"471B1A48-B41D-4986-ACDC-50CD095ED302","name":"Legacy tool","executable":"/bin/echo","arguments":["two words","$(unchanged)"]}"#
        let legacy = try store.importPreview(from: Data("{\"version\":1,\"profile\":\(legacyProfile)}".utf8))
        assert(legacy.integration == nil && legacy.id.uuidString == "471B1A48-B41D-4986-ACDC-50CD095ED302")
        assert(legacy.name == "Legacy tool" && legacy.executable == "/bin/echo" && legacy.arguments == ["two words", "$(unchanged)"])
        let legacyRoundTrip = try store.importPreview(from: store.exportData(legacy))
        assert(legacyRoundTrip == legacy)
        try Data("{\"version\":1,\"profiles\":[\(legacyProfile)]}".utf8).write(to: store.fileURL)
        let legacyLoaded = try store.load()
        assert(legacyLoaded == [legacy] && CustomHarnessStore.currentVersion == 1)
        let nativeProfiles = try ["codex", "opencode", "pi", "claude", "gemini"].map {
            try CustomHarness(name: $0, executable: "/bin/echo", arguments: ["literal argument"], integration: $0)
        }
        try store.save([legacy] + nativeProfiles)
        let nativeLoaded = try store.load()
        assert(nativeLoaded == [legacy] + nativeProfiles)
        for native in nativeProfiles {
            let restored = try store.importPreview(from: store.exportData(native))
            assert(restored == native)
        }
        for invalid in ["", "Codex", "antigravity", "arbitrary", "codex\0"] {
            assertThrows { try CustomHarness(name: "Invalid integration", executable: "/bin/echo", arguments: [], integration: invalid) }
        }
        let invalidIntegration = legacyProfile.dropLast() + ",\"integration\":\"unknown\"}"
        assertThrows { try store.importPreview(from: Data("{\"version\":1,\"profile\":\(invalidIntegration)}".utf8)) }

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
