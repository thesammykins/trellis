import Foundation

struct MultiplexerProfile: Codable, Equatable {
    let sessionName: String
    let sessionCreated: Int?

    init() {
        sessionName = "trellis-\(UUID().uuidString)"
        sessionCreated = nil
    }

    init(sessionName: String, sessionCreated: Int? = nil) throws {
        try Self.validate(sessionName: sessionName, sessionCreated: sessionCreated)
        self.sessionName = sessionName
        self.sessionCreated = sessionCreated
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let name = try values.decode(String.self, forKey: .sessionName)
        let created = try values.decodeIfPresent(Int.self, forKey: .sessionCreated)
        // Legacy discovered records remain readable, but arguments() refuses to attach
        // until discovery supplies the missing identity guard.
        try Self.validate(sessionName: name, sessionCreated: Self.isServerID(name) && created == nil ? 1 : created)
        sessionName = name
        sessionCreated = created
    }

    func arguments(create: Bool, directory: URL) throws -> [String] {
        try Self.validate(sessionName: sessionName, sessionCreated: sessionCreated)
        let path = try Self.validDirectoryPath(directory)
        guard !create || !Self.isServerID(sessionName) else { throw Failure("Cannot create an existing server identity") }
        if create { return ["new-session", "-s", sessionName, "-c", path] }
        guard let sessionCreated else { return ["attach-session", "-t", "=\(sessionName)"] }
        return ["if-shell", "-t", sessionName, "-F", "#{==:#{session_created},\(sessionCreated)}",
                "attach-session -t \(sessionName)",
                "run-shell \"printf '%s\\n' 'Session identity changed. Refresh before attaching.' >&2; exit 73\""]
    }

    static func executable(searchPath: String) throws -> String {
        var candidates = searchPath.split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0).appendingPathComponent("tmux").path }
        for fallback in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
            candidates.append(URL(fileURLWithPath: fallback).appendingPathComponent("tmux").path)
        }
        for candidate in candidates where isRegularExecutable(candidate) { return candidate }
        throw Failure("tmux is not installed or is not executable. Add it to PATH or install it yourself.")
    }

    private static func isServerID(_ value: String) -> Bool {
        value.first == "$" && (1...12).contains(value.dropFirst().count) && value.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func validate(sessionName: String, sessionCreated: Int?) throws {
        if Self.isServerID(sessionName) {
            guard let sessionCreated, sessionCreated > 0 else { throw Failure("A discovered tmux session requires its creation-time identity guard.") }
            return
        }
        guard sessionCreated == nil else { throw Failure("Creation-time guards apply only to discovered tmux server IDs.") }
        let prefix = "trellis-"
        let suffix = String(sessionName.dropFirst(prefix.count))
        guard sessionName.hasPrefix(prefix), sessionName.utf8.count <= 80,
              sessionName.unicodeScalars.allSatisfy(isSessionNameScalar),
              UUID(uuidString: suffix)?.uuidString == suffix else {
            throw Failure("tmux session must be a Trellis-owned UUID name.")
        }
    }

    private static func validDirectoryPath(_ directory: URL) throws -> String {
        let path = directory.path
        guard directory.isFileURL, path.hasPrefix("/"), path.utf8.count <= 4_096,
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw Failure("tmux directory must be an absolute local path under 4096 bytes with no control characters.")
        }
        return path
    }

    private static func isSessionNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 45, 48...57, 65...90, 95, 97...122: true
        default: false
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
