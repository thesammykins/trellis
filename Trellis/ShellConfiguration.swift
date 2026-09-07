import Foundation

struct ShellConfiguration: Codable, Equatable, Sendable {
    static let defaultsKey = "shellConfiguration"
    static let maximumStoredBytes = 16_384
    static let maximumArguments = 128
    static let maximumPathBytes = 4_096
    static let maximumArgumentBytes = 4_096
    static let `default` = ShellConfiguration(uncheckedExecutable: "/bin/zsh", arguments: ["-l"])

    var executable: String
    var arguments: [String]

    init(executable: String = "/bin/zsh", arguments: [String] = ["-l"]) throws {
        self.executable = executable
        self.arguments = arguments
        try validateStructure()
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(executable: values.decode(String.self, forKey: .executable),
                      arguments: values.decode([String].self, forKey: .arguments))
    }

    static func load(from defaults: UserDefaults = .standard) -> ShellConfiguration {
        guard let data = defaults.data(forKey: defaultsKey), data.count <= maximumStoredBytes,
              let configuration = try? JSONDecoder().decode(ShellConfiguration.self, from: data) else { return .default }
        return configuration
    }

    func save(to defaults: UserDefaults = .standard) {
        guard (try? validated()) != nil, let data = try? JSONEncoder().encode(self),
              data.count <= Self.maximumStoredBytes else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func validated() throws -> ShellConfiguration {
        try validateStructure()
        return self
    }

    /// Archive validation preserves a safe shell snapshot; launch checks availability separately.
    func launchExecutable() throws -> String {
        try validateStructure()
        guard Self.isRegularExecutable(executable) else {
            throw Failure("Shell executable is no longer installed or executable: \(executable)")
        }
        return executable
    }

    var validationError: String? {
        do { try validateStructure(); return nil }
        catch { return error.localizedDescription }
    }

    static func installedShells(shellsFile: URL = URL(fileURLWithPath: "/etc/shells"),
                                knownCandidates: [String] = knownShellCandidates) -> [String] {
        let listed = (try? Data(contentsOf: shellsFile, options: .mappedIfSafe))
            .flatMap { $0.count <= maximumStoredBytes ? String(data: $0, encoding: .utf8) : nil }
            .map { text in
                text.split(separator: "\n").compactMap { line -> String? in
                    let value = line.split(separator: "#", maxSplits: 1).first.map(String.init)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return value.hasPrefix("/") ? value : nil
                }
            } ?? []
        return Array(Set(listed + knownCandidates)).filter(isRegularExecutable)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func loginPresetArguments(for executable: String) -> [String]? {
        guard isRegularExecutable(executable) else { return nil }
        switch executable {
        case "/bin/zsh", "/bin/ksh", "/bin/tcsh", "/bin/csh": return ["-l"]
        case "/bin/bash": return ["--login"]
        default: return nil
        }
    }

    private static let knownShellCandidates = [
        "/bin/fish", "/usr/bin/fish", "/opt/homebrew/bin/fish",
        "/bin/bash", "/usr/bin/bash", "/opt/homebrew/bin/bash",
        "/bin/zsh", "/usr/bin/zsh", "/opt/homebrew/bin/zsh",
        "/bin/sh", "/usr/bin/sh", "/bin/dash", "/usr/bin/dash", "/bin/ksh", "/usr/bin/ksh",
        "/bin/tcsh", "/usr/bin/tcsh", "/bin/csh", "/usr/bin/csh",
        "/usr/local/bin/nu", "/opt/homebrew/bin/nu", "/usr/local/bin/pwsh", "/opt/homebrew/bin/pwsh",
        "/usr/local/bin/xonsh", "/opt/homebrew/bin/xonsh", "/usr/local/bin/elvish", "/opt/homebrew/bin/elvish",
    ]

    private init(uncheckedExecutable: String, arguments: [String]) {
        self.executable = uncheckedExecutable
        self.arguments = arguments
    }

    private func validateStructure() throws {
        guard executable.hasPrefix("/"), executable.utf8.count <= Self.maximumPathBytes,
              !executable.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              URL(fileURLWithPath: executable).standardizedFileURL.path == executable else {
            throw Failure("Shell executable must be a normalized absolute path.")
        }
        guard arguments.count <= Self.maximumArguments,
              arguments.allSatisfy({ $0.utf8.count <= Self.maximumArgumentBytes && !$0.utf8.contains(0) }) else {
            throw Failure("A shell can have at most 128 arguments, each under 4096 bytes with no NUL character.")
        }
    }

    private static func isRegularExecutable(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let manager = FileManager.default
        guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else { return false }
        return manager.isExecutableFile(atPath: resolved.path)
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
