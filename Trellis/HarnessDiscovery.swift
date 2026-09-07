import Foundation

enum HarnessDiscovery {
    static var searchPath: String {
        let userDirectory = FileManager.default.homeDirectoryForCurrentUser
        let defaults = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            + [".local/bin", ".opencode/bin", ".bun/bin"].map { userDirectory.appendingPathComponent($0).path }
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var paths: [String] = []
        // Finder launches do not inherit the user's interactive shell PATH.
        for path in inherited + defaults where path.hasPrefix("/") && !path.utf8.contains(0) && !paths.contains(path) {
            paths.append(path)
        }
        return paths.joined(separator: ":")
    }

    private static let presets: [(name: String, command: String, integration: String?)] = [
        ("Codex", "codex", "codex"),
        ("OpenCode", "opencode", "opencode"),
        ("Pi", "pi", "pi"),
        ("Claude Code", "claude", "claude"),
        ("Gemini CLI", "gemini", "gemini"),
        // The terminal CLI is agy; an IDE launcher does not establish terminal support.
        // https://antigravity.google/docs/cli/install/
        ("Antigravity CLI", "agy", nil),
    ]

    /// Finds launch candidates without executing them or reading account state.
    static func discover(searchPath: String, excluding: [CustomHarness] = []) -> [CustomHarness] {
        let directories = searchPath.split(separator: ":").filter {
            $0.hasPrefix("/") && $0.utf8.count <= CustomHarness.maximumPathBytes && !$0.utf8.contains(0)
        }
        let integrations = Set(excluding.compactMap(\.integration))
        var executables = Set(excluding.map {
            URL(fileURLWithPath: $0.executable).resolvingSymlinksInPath().standardizedFileURL.path
        })
        var discovered: [CustomHarness] = []
        for preset in presets {
            if let integration = preset.integration, integrations.contains(integration) { continue }
            for directory in directories {
                let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(preset.command).standardizedFileURL
                let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
                guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true,
                      FileManager.default.isExecutableFile(atPath: resolved.path) else { continue }
                // PATH selects the first installed command, including when it is already saved under an alias.
                guard !executables.contains(resolved.path),
                      let harness = try? CustomHarness(name: preset.name, executable: candidate.path,
                          arguments: [], integration: preset.integration) else { break }
                discovered.append(harness)
                executables.insert(resolved.path)
                break
            }
        }
        return discovered
    }
}
