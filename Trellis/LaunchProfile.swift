import Foundation

enum LaunchProfile: String, CaseIterable, Identifiable {
    case shell
    case codex
    case opencode
    case pi
    case claude
    case gemini
    case tmux
    case custom
    case remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shell: "Shell"
        case .codex: "Codex"
        case .opencode: "OpenCode"
        case .pi: "Pi"
        case .claude: "Claude Code"
        case .gemini: "Gemini CLI"
        case .tmux: "tmux"
        case .custom: "Custom Agent"
        case .remote: "SSH"
        }
    }

    var arguments: [String] {
        self == .shell ? ["-l"] : []
    }

    func executable(searchPath: String,
                    fallbackDirectories: [String] = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]) throws -> String {
        if self == .remote { return "/usr/bin/ssh" }
        if self == .shell {
            guard Self.isRegularExecutable("/bin/zsh") else { throw MissingExecutable(profile: title) }
            return "/bin/zsh"
        }
        let name = rawValue
        var candidates = searchPath.split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
        candidates += fallbackDirectories
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }

        for candidate in candidates where Self.isRegularExecutable(candidate) {
            return candidate
        }
        throw MissingExecutable(profile: title)
    }

    private static func isRegularExecutable(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let manager = FileManager.default
        guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else { return false }
        return manager.isExecutableFile(atPath: resolved.path)
    }
}

private struct MissingExecutable: LocalizedError {
    let profile: String
    var errorDescription: String? {
        "\(profile) is not installed or is not executable. Add it to PATH or install it yourself."
    }
}
