import Foundation

@main
enum LaunchProfileCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Trellis-launch-profile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let originalDirectory = FileManager.default.currentDirectoryPath
        defer { FileManager.default.changeCurrentDirectoryPath(originalDirectory) }
        let tools = root.appendingPathComponent("tool dir ' 東京")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)

        let codex = tools.appendingPathComponent("codex")
        try Data("#!/bin/sh\n".utf8).write(to: codex)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        let resolvedCodex = try LaunchProfile.codex.executable(searchPath: tools.path)
        assert(resolvedCodex == codex.path)

        for profile in [LaunchProfile.claude, .gemini] {
            let executable = tools.appendingPathComponent(profile.rawValue)
            try Data("#!/bin/sh\n".utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            let resolved = try profile.executable(searchPath: tools.path, fallbackDirectories: [])
            assert(resolved == executable.path)
        }

        let pi = tools.appendingPathComponent("pi")
        try Data("#!/bin/sh\n".utf8).write(to: pi)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: pi.path)
        assertThrows { try LaunchProfile.pi.executable(searchPath: tools.path, fallbackDirectories: []) }

        let relative = root.appendingPathComponent("relative")
        try FileManager.default.createDirectory(at: relative, withIntermediateDirectories: false)
        let relativeCodex = relative.appendingPathComponent("codex")
        try Data("#!/bin/sh\n".utf8).write(to: relativeCodex)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: relativeCodex.path)
        assert(FileManager.default.changeCurrentDirectoryPath(root.path))
        assertThrows { try LaunchProfile.codex.executable(searchPath: "relative", fallbackDirectories: []) }
        assertThrows { try LaunchProfile.opencode.executable(searchPath: root.path, fallbackDirectories: []) }
        let shell = try LaunchProfile.shell.executable(searchPath: "relative", fallbackDirectories: [])
        assert(shell == "/bin/zsh")
        assert(LaunchProfile.shell.arguments == ["-l"])
        assert(LaunchProfile.codex.arguments.isEmpty)
        print("PASS launch profiles resolve exact executable paths and reject missing, relative, and nonexecutable candidates")
    }

    private static func assertThrows(_ operation: () throws -> Any) {
        do {
            _ = try operation()
            preconditionFailure("Expected missing executable")
        } catch {}
    }
}
