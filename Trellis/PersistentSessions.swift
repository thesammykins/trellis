import Foundation

struct PersistentSession: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let created: Int
    let windows: Int
    let attached: Int
    var readableName: String {
        let suffix = String(name.dropFirst("trellis-".count))
        return name.hasPrefix("trellis-") && UUID(uuidString: suffix)?.uuidString == suffix
            ? "Terminal · " + Date(timeIntervalSince1970: Double(created)).formatted(date: .abbreviated, time: .shortened)
            : name
    }
}

struct PersistentSessions: Sendable {
    let host: String?
    let executable: String
    static let format = "#{session_id}|#{session_created}|#{session_windows}|#{session_attached}|#{session_name}"

    func list() async throws -> [PersistentSession] {
        let text = try await run(["list-sessions", "-F", Self.format])
        return try Self.parse(text)
    }

    func end(_ session: PersistentSession) async throws {
        // Match server identity and creation time again. A stale selection cannot
        // kill a different session after the server has restarted.
        guard try await list().contains(where: { $0.id == session.id && $0.created == session.created }) else { throw Failure("Session changed. Refresh before ending it.") }
        _ = try await run(["if-shell", "-t", session.id, "-F", "#{==:#{session_created},\(session.created)}",
                           "kill-session -t \(session.id)"])
        guard !(try await list()).contains(where: { $0.id == session.id && $0.created == session.created }) else {
            throw Failure("Session is still running. Refresh and try again.")
        }
    }

    private func run(_ arguments: [String]) async throws -> String {
        let localExecutable: String
        let argv: [String]
        if let host {
            // Reuse validation and strict OpenSSH policy from the attachment route.
            _ = try RemoteProfile(hostAlias: host, directory: "/", sessionName: "trellis-00000000-0000-0000-0000-000000000000", tmuxExecutable: executable)
            let command = ([executable] + arguments).map(Self.quote).joined(separator: " ")
            // A stopped tmux server is a successful empty catalogue; all other
            // diagnostics remain errors. Force C locale only for this command.
            let wrapped = "out=$(LC_ALL=C " + command + " 2>&1); code=$?; if [ \"$code\" = 0 ]; then printf '%s' \"$out\"; elif [ \"$code\" = 1 ] && { case \"$out\" in 'no server running on '*|'error connecting to '*': No such file or directory') true;; *) false;; esac; }; then :; else printf '%s' \"$out\" >&2; exit \"$code\"; fi"
            localExecutable = "/usr/bin/ssh"
            argv = ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10", "-o", "ForwardAgent=no", "--", host, wrapped]
        } else {
            localExecutable = "/bin/sh"
            let command = ([executable] + arguments).map(Self.quote).joined(separator: " ")
            argv = ["-c", "out=$(LC_ALL=C " + command + " 2>&1); code=$?; if [ \"$code\" = 0 ]; then printf '%s' \"$out\"; elif [ \"$code\" = 1 ] && { case \"$out\" in 'no server running on '*|'error connecting to '*': No such file or directory') true;; *) false;; esac; }; then :; else printf '%s' \"$out\" >&2; exit \"$code\"; fi"]
        }
        return try await Task.detached(priority: .utility) {
            try AgentInstallation.probe(executable: localExecutable, arguments: argv, timeout: 15, outputLimit: 65_536, allowEmpty: true)
        }.value
    }

    static func parse(_ text: String) throws -> [PersistentSession] {
        guard text.utf8.count <= 65_536 else { throw Failure("Session list is too large") }
        let lines = text.split(separator: "\n")
        guard lines.count <= 1024 else { throw Failure("Too many sessions") }
        var seen = Set<String>()
        return try lines.map { line in
            let p = line.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 5, validID(p[0]), seen.insert(p[0]).inserted,
                  let created = Int(p[1]), created > 0,
                  let windows = Int(p[2]), windows > 0,
                  let attached = Int(p[3]), attached >= 0,
                  !p[4].isEmpty, p[4].utf8.count <= 256,
                  !p[4].unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Failure("Invalid tmux session list") }
            return .init(id: p[0], name: p[4], created: created, windows: windows, attached: attached)
        }
    }
    static func validID(_ value: String) -> Bool {
        value.first == "$" && (1...12).contains(value.dropFirst().count) && value.dropFirst().allSatisfy { $0.isASCII && $0.isNumber }
    }
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    struct Failure: LocalizedError { let errorDescription: String?; init(_ value: String) { errorDescription = value } }
}
