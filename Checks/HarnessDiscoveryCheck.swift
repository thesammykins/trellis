import Darwin
import Foundation

@main
enum HarnessDiscoveryCheck {
    static func main() throws {
        let manager = FileManager.default
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"]
        defer {
            if let inheritedPath { setenv("PATH", inheritedPath, 1) }
            else { unsetenv("PATH") }
        }
        setenv("PATH", "/usr/bin:/bin", 1)
        let finderPath = HarnessDiscovery.searchPath.split(separator: ":").map(String.init)
        let userDirectory = manager.homeDirectoryForCurrentUser
        assert(Array(finderPath.prefix(2)) == ["/usr/bin", "/bin"])
        for path in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            + [".local/bin", ".opencode/bin", ".bun/bin"].map({ userDirectory.appendingPathComponent($0).path }) {
            assert(finderPath.contains(path), "Finder discovery must include \(path)")
        }
        setenv("PATH", "/custom/bin::relative:/custom/bin:/usr/bin", 1)
        let shellPath = HarnessDiscovery.searchPath.split(separator: ":").map(String.init)
        assert(Array(shellPath.prefix(2)) == ["/custom/bin", "/usr/bin"] && Set(shellPath).count == shellPath.count)
        assert(shellPath.allSatisfy { $0.hasPrefix("/") })
        let root = manager.temporaryDirectory.appendingPathComponent("Trellis-HarnessDiscovery-\(UUID())")
        defer { try? manager.removeItem(at: root) }
        let first = root.appendingPathComponent("first tools ' 空間")
        let second = root.appendingPathComponent("second")
        let targets = root.appendingPathComponent("targets")
        for directory in [first, second, targets] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let marker = root.appendingPathComponent("discovery-executed-a-command")
        let script = "#!/bin/sh\n/usr/bin/touch '" + marker.path.replacingOccurrences(of: "'", with: "'\\''") + "'\n"
        func executable(_ name: String, in directory: URL) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try Data(script.utf8).write(to: url)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        }
        let codex = try executable("codex", in: first)
        _ = try executable("codex", in: second)
        let openCodeTarget = try executable("opencode-real", in: targets)
        let opencode = first.appendingPathComponent("opencode")
        try manager.createSymbolicLink(at: opencode, withDestinationURL: openCodeTarget)
        try manager.createDirectory(at: first.appendingPathComponent("pi"), withIntermediateDirectories: false)
        let pi = try executable("pi", in: second)
        try Data(script.utf8).write(to: first.appendingPathComponent("claude"))
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: first.appendingPathComponent("claude").path)
        let claude = try executable("claude", in: second)
        try manager.createSymbolicLink(at: first.appendingPathComponent("gemini"), withDestinationURL: targets.appendingPathComponent("missing"))
        let gemini = try executable("gemini", in: second)
        let agyTarget = try executable("agy-real", in: targets)
        let agy = first.appendingPathComponent("agy")
        try manager.createSymbolicLink(at: agy, withDestinationURL: agyTarget)
        _ = try executable("antigravity", in: first)

        let path = ":relative:.:~/bin:\(root.appendingPathComponent("missing").path):\(first.path):\(first.path):\(second.path)"
        let found = HarnessDiscovery.discover(searchPath: path)
        assert(found.map(\.name) == ["Codex", "OpenCode", "Pi", "Claude Code", "Gemini CLI", "Antigravity CLI"])
        assert(found.map(\.executable) == [codex, opencode, pi, claude, gemini, agy].map { $0.standardizedFileURL.path })
        assert(found.map(\.integration) == ["codex", "opencode", "pi", "claude", "gemini", nil])
        assert(found.allSatisfy { $0.arguments.isEmpty } && Set(found.map(\.id)).count == found.count)
        assert(HarnessDiscovery.discover(searchPath: path, excluding: found).isEmpty)
        assert(HarnessDiscovery.discover(searchPath: "relative::.:~/bin").isEmpty)

        let savedIntegration = try CustomHarness(name: "Saved Codex", executable: "/bin/echo", arguments: ["custom"], integration: "codex")
        let savedAlias = try CustomHarness(name: "Saved alias", executable: openCodeTarget.standardizedFileURL.path, arguments: [])
        let remaining = HarnessDiscovery.discover(searchPath: path, excluding: [savedIntegration, savedAlias])
        assert(remaining.map(\.name) == ["Pi", "Claude Code", "Gemini CLI", "Antigravity CLI"])
        let savedFirst = try CustomHarness(name: "Legacy Codex", executable: codex.standardizedFileURL.path, arguments: [])
        assert(!HarnessDiscovery.discover(searchPath: path, excluding: [savedFirst]).contains { $0.integration == "codex" },
               "Saving the first PATH command must not offer its shadowed installation")

        try manager.removeItem(at: agy)
        try manager.createSymbolicLink(at: agy, withDestinationURL: codex)
        let aliased = HarnessDiscovery.discover(searchPath: path)
        assert(aliased.count == 5 && !aliased.contains { $0.name == "Antigravity CLI" }, "Executable aliases must not create duplicate presets")
        assert(!manager.fileExists(atPath: marker.path), "Discovery must never execute a detected command")
        print("harness discovery checks passed: PATH order, executable files, symlinks, exclusions, aliases and no execution")
    }
}
