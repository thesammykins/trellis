import Foundation

@main
enum MultiplexerProfileCheck {
    static func main() throws {
        let session = "trellis-\(UUID().uuidString)"
        let profile = try MultiplexerProfile(sessionName: session)
        let tmux = try MultiplexerProfile.executable(searchPath: ProcessInfo.processInfo.environment["PATH"] ?? "")
        precondition(FileManager.default.isExecutableFile(atPath: tmux))
        let directory = URL(fileURLWithPath: "/tmp/Artist's Work — 東京")
        let create = try profile.arguments(create: true, directory: directory)
        assert(create ==
               ["new-session", "-s", session, "-c", directory.path])
        let attach = try profile.arguments(create: false, directory: directory)
        assert(attach ==
               ["attach-session", "-t", "=\(session)"])
        let discovered = try MultiplexerProfile(sessionName: "$7", sessionCreated: 123)
        let guarded = try discovered.arguments(create: false, directory: directory)
        assert(guarded == ["if-shell", "-t", "$7", "-F", "#{==:#{session_created},123}",
                           "attach-session -t $7",
                           "run-shell \"printf '%s\\n' 'Session identity changed. Refresh before attaching.' >&2; exit 73\""])
        assertThrows { try MultiplexerProfile(sessionName: "$7") }
        assertThrows { try MultiplexerProfile(sessionName: session, sessionCreated: 123) }
        for name in ["other-\(UUID().uuidString)", "trellis-not-a-uuid", "trellis-\(UUID().uuidString)-extra", "trellis-\(UUID().uuidString)\n"] {
            assertThrows { try MultiplexerProfile(sessionName: name) }
        }
        assertThrows { try profile.arguments(create: true, directory: URL(string: "https://example.com")!) }
        assertThrows { try profile.arguments(create: true, directory: URL(fileURLWithPath: "/tmp/new\nline")) }
        let decoded = try JSONDecoder().decode(MultiplexerProfile.self, from: JSONEncoder().encode(profile))
        assert(decoded == profile)
        let decodedDiscovered = try JSONDecoder().decode(MultiplexerProfile.self, from: JSONEncoder().encode(discovered))
        assert(decodedDiscovered == discovered)
        let legacyDiscovered = try JSONDecoder().decode(MultiplexerProfile.self, from: Data(#"{"sessionName":"$7"}"#.utf8))
        assertThrows { try legacyDiscovered.arguments(create: false, directory: directory) }
        print("PASS tmux argv, persistence, Unicode path, attach-only and malformed-name validation")
    }

    private static func assertThrows(_ operation: () throws -> Any) {
        do {
            _ = try operation()
            preconditionFailure("Expected validation failure")
        } catch {}
    }
}
