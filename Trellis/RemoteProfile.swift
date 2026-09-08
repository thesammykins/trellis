import Foundation

struct RemoteProfile: Codable, Sendable, Equatable {
    enum Mode: String, Codable, CaseIterable, Sendable { case shell, tmux }
    let mode: Mode
    let hostAlias: String
    let directory: String
    let sessionName: String
    /// `nil` uses tmux from the remote login PATH for older saved profiles.
    let tmuxExecutable: String?
    let sessionCreated: Int?

    init(hostAlias: String, directory: String, sessionName: String, tmuxExecutable: String? = nil,
         sessionCreated: Int? = nil, mode: Mode = .tmux) throws {
        try Self.validate(hostAlias: hostAlias, directory: directory, sessionName: sessionName,
                          tmuxExecutable: tmuxExecutable, sessionCreated: sessionCreated, mode: mode)
        self.mode = mode
        self.hostAlias = hostAlias
        self.directory = directory
        self.sessionName = sessionName
        self.tmuxExecutable = tmuxExecutable
        self.sessionCreated = sessionCreated
    }

    init(hostAlias: String, directory: String = "") throws {
        try self.init(hostAlias: hostAlias, directory: directory, sessionName: "", mode: .shell)
    }

    var isPersistent: Bool { mode == .tmux }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let host = try values.decode(String.self, forKey: .hostAlias)
        let directory = try values.decode(String.self, forKey: .directory)
        let name = try values.decode(String.self, forKey: .sessionName)
        let tmux = try values.decodeIfPresent(String.self, forKey: .tmuxExecutable)
        let created = try values.decodeIfPresent(Int.self, forKey: .sessionCreated)
        let mode = try values.decodeIfPresent(Mode.self, forKey: .mode) ?? .tmux
        // Decode legacy records so workspace restoration survives upgrades. The
        // attach boundary still refuses an unguarded discovered server ID.
        try Self.validate(hostAlias: host, directory: directory, sessionName: name, tmuxExecutable: tmux,
                          sessionCreated: Self.isServerID(name) && created == nil ? 1 : created, mode: mode)
        self.mode = mode
        hostAlias = host
        self.directory = directory
        sessionName = name
        tmuxExecutable = tmux
        sessionCreated = created
    }

    func arguments(create: Bool) throws -> [String] {
        try Self.validate(hostAlias: hostAlias, directory: directory, sessionName: sessionName,
                          tmuxExecutable: tmuxExecutable, sessionCreated: sessionCreated, mode: mode)
        let connection = ["-t", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
                          "-o", "ForwardAgent=no", "--", hostAlias]
        if mode == .shell {
            // Omitting a remote command requests the server's ordinary login shell.
            guard !directory.isEmpty else { return connection }
            let login = "cd " + Self.shellQuote(directory) + " && exec \"${SHELL:-/bin/sh}\" -l"
            return connection + ["env TERM=xterm-256color /bin/sh -c " + Self.shellQuote(login)]
        }
        let tmux = tmuxExecutable.map(Self.shellQuote) ?? "tmux"
        let command: String
        if create {
            guard !Self.isServerID(sessionName) else { throw Failure("Choose Create New to generate a new session identity.") }
            command = "\(tmux) new-session -s \(Self.shellQuote(sessionName)) -c \(Self.shellQuote(directory))"
        } else if let sessionCreated {
            let format = "#{==:#{session_created},\(sessionCreated)}"
            let attach = "attach-session -t \(Self.shellQuote(sessionName))"
            let refuse = "run-shell \(Self.shellQuote("printf '%s\\n' 'Session identity changed. Refresh before attaching.' >&2; exit 73"))"
            command = "\(tmux) if-shell -t \(Self.shellQuote(sessionName)) -F \(Self.shellQuote(format)) \(Self.shellQuote(attach)) \(Self.shellQuote(refuse))"
        } else {
            command = "\(tmux) attach-session -t \(Self.shellQuote(Self.isServerID(sessionName) ? sessionName : "=\(sessionName)"))"
        }
        return connection + [
            // Remote hosts often lack Ghostty terminfo; use the widely installed
            // compatible entry for this attachment without installing remote files.
            "env TERM=xterm-256color " + command,
        ]
    }

    private static func isServerID(_ value: String) -> Bool {
        value.first == "$" && (1...12).contains(value.dropFirst().count) && value.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func validate(hostAlias: String, directory: String, sessionName: String, tmuxExecutable: String?,
                                 sessionCreated: Int?, mode: Mode) throws {
        let hostParts = hostAlias.split(separator: "@", omittingEmptySubsequences: false)
        guard (1...2).contains(hostParts.count), hostParts.allSatisfy(isSafeHostComponent),
              hostAlias.utf8.count <= 255 else {
            throw Failure("Remote host must be an existing SSH alias or user@host using only ASCII letters, digits, dots, underscores, and hyphens.")
        }
        guard (mode == .shell && directory.isEmpty) || directory.hasPrefix("/"),
              directory.utf8.count <= 4_096,
              !directory.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw Failure("Remote directory must be an absolute path under 4096 bytes with no control characters.")
        }
        if mode == .shell {
            guard sessionName.isEmpty, tmuxExecutable == nil, sessionCreated == nil else {
                throw Failure("An ordinary SSH connection cannot carry a tmux session identity.")
            }
            return
        }
        let prefix = "trellis-"
        let suffix = String(sessionName.dropFirst(prefix.count))
        guard Self.isServerID(sessionName) || (sessionName.hasPrefix(prefix) &&
              sessionName.utf8.count <= 80 &&
              sessionName.unicodeScalars.allSatisfy(isSessionNameScalar) &&
              UUID(uuidString: suffix)?.uuidString == suffix) else {
            throw Failure("Remote tmux session must be a Trellis-owned UUID name.")
        }
        if Self.isServerID(sessionName) {
            guard let sessionCreated, sessionCreated > 0 else { throw Failure("A discovered remote session requires its creation-time identity guard.") }
        } else if sessionCreated != nil {
            throw Failure("Creation-time guards apply only to discovered tmux server IDs.")
        }
        if let tmuxExecutable {
            guard tmuxExecutable == "tmux" ||
                    (tmuxExecutable.hasPrefix("/") && tmuxExecutable.utf8.count <= 4_096 &&
                     !tmuxExecutable.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) &&
                     URL(fileURLWithPath: tmuxExecutable).standardizedFileURL.path == tmuxExecutable) else {
                throw Failure("Remote tmux executable must be tmux or a normalized absolute path with no control characters.")
            }
        }
    }

    private static func isHostAliasScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 45, 46, 48...57, 65...90, 95, 97...122: true
        default: false
        }
    }

    private static func isSafeHostComponent(_ component: Substring) -> Bool {
        !component.isEmpty && component.first != "-" && component.unicodeScalars.allSatisfy(isHostAliasScalar)
    }

    private static func isSessionNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 45, 48...57, 65...90, 95, 97...122: true
        default: false
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
