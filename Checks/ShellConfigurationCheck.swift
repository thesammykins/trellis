import Foundation

@main
enum ShellConfigurationCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-shell-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let shell = root.appendingPathComponent("fish shell")
        guard FileManager.default.createFile(atPath: shell.path, contents: Data("#!/bin/sh\n".utf8)) else {
            throw CheckError.fixture
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shell.path)
        let shellsFile = root.appendingPathComponent("shells")
        try Data("# fixture\n\(shell.path)\n/not/installed\n".utf8).write(to: shellsFile)
        precondition(ShellConfiguration.installedShells(shellsFile: shellsFile, knownCandidates: []).contains(shell.path))

        let configuration = try ShellConfiguration(executable: shell.path, arguments: ["--interactive", "two words", "$(not-a-shell)"])
        let suite = "ShellConfigurationCheck-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        configuration.save(to: defaults)
        precondition(ShellConfiguration.load(from: defaults) == configuration)

        let missing = try ShellConfiguration(executable: root.appendingPathComponent("removed-shell").path, arguments: [])
        precondition(missing.validationError == nil)
        assertThrows { try missing.launchExecutable() }

        assertThrows { try ShellConfiguration(executable: "relative/fish", arguments: []) }
        assertThrows { try ShellConfiguration(executable: shell.path + "\n", arguments: []) }
        assertThrows { try ShellConfiguration(executable: shell.path, arguments: ["bad\0arg"]) }
        print("PASS shell discovery, direct argv validation and UserDefaults round trip")
    }

    private static func assertThrows(_ operation: () throws -> Any) {
        do {
            _ = try operation()
            preconditionFailure("Expected validation failure")
        } catch {}
    }

    enum CheckError: Error { case fixture }
}
