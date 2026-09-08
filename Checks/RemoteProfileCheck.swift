import Foundation

@main
enum RemoteProfileCheck {
    static func main() throws {
        let session = "trellis-\(UUID().uuidString)"
        let directory = "/srv/Artist's Work — 東京"
        let profile = try RemoteProfile(hostAlias: "studio-prod_1", directory: directory, sessionName: session)
        assert(profile.mode == .tmux && profile.isPersistent)

        let create = try profile.arguments(create: true)
        assert(create == [
            "-t", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10", "-o", "ForwardAgent=no",
            "--", "studio-prod_1", "env TERM=xterm-256color tmux new-session -s '\(session)' -c '/srv/Artist'\\''s Work — 東京'",
        ])

        let attach = try profile.arguments(create: false)
        assert(attach.last == "env TERM=xterm-256color tmux attach-session -t '=\(session)'")
        assert(!attach.contains("-A"))
        assert(!attach.joined(separator: " ").contains("new-session"))
        let discovered = try RemoteProfile(hostAlias: "host", directory: "/srv", sessionName: "$3", sessionCreated: 123)
        let guardedAttach = try discovered.arguments(create: false)
        assert(guardedAttach.last?.contains("if-shell -t '$3' -F '#{==:#{session_created},123}'") == true)
        assert(guardedAttach.last?.contains("attach-session -t") == true)
        assert(guardedAttach.last?.contains("exit 73") == true)
        assertThrows { try RemoteProfile(hostAlias: "host", directory: "/srv", sessionName: "$3") }
        assertThrows { try RemoteProfile(hostAlias: "host", directory: "/srv", sessionName: session, sessionCreated: 123) }

        let customTmux = "/opt/Tmux Tools/tmux'3.7c"
        let customProfile = try RemoteProfile(hostAlias: "host", directory: directory, sessionName: session,
                                              tmuxExecutable: customTmux)
        let customCreate = try customProfile.arguments(create: true)
        assert(customCreate.last ==
               "env TERM=xterm-256color '/opt/Tmux Tools/tmux'\\''3.7c' new-session -s '\(session)' -c '/srv/Artist'\\''s Work — 東京'")
        let customAttach = try customProfile.arguments(create: false)
        assert(customAttach.last ==
               "env TERM=xterm-256color '/opt/Tmux Tools/tmux'\\''3.7c' attach-session -t '=\(session)'")

        let userHost = try RemoteProfile(hostAlias: "devmac@devmac", directory: "/srv", sessionName: session)
        let userHostArguments = try userHost.arguments(create: false)
        assert(userHostArguments.contains("devmac@devmac"))
        for alias in ["-option", "-user@host", "user@-host", "@host", "user@", "user@@host", "host name", "host\nname", "東京"] {
            assertThrows { try RemoteProfile(hostAlias: alias, directory: "/srv", sessionName: session) }
        }
        for path in ["relative/path", "/srv/control\u{0000}character", "/srv/new\nline", String(repeating: "a", count: 4_097)] {
            assertThrows { try RemoteProfile(hostAlias: "host", directory: path, sessionName: session) }
        }
        assertThrows { try RemoteProfile(hostAlias: "host", directory: "/srv", sessionName: "trellis-not-a-uuid") }
        for tmux in ["relative/tmux", "/opt/tmux\u{0000}", "/opt/new\nline"] {
            assertThrows { try RemoteProfile(hostAlias: "host", directory: "/srv", sessionName: session, tmuxExecutable: tmux) }
        }

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(RemoteProfile.self, from: data)
        assert(decoded.hostAlias == profile.hostAlias)
        assert(decoded.directory == profile.directory)
        assert(decoded.sessionName == profile.sessionName)
        assert(decoded.tmuxExecutable == nil)
        assert(decoded.sessionCreated == nil)
        let oldRecord = #"{"hostAlias":"host","directory":"/srv","sessionName":"\#(session)"}"#
        let decodedOld = try JSONDecoder().decode(RemoteProfile.self, from: Data(oldRecord.utf8))
        assert(decodedOld.mode == .tmux && decodedOld.isPersistent)
        assert(decodedOld.tmuxExecutable == nil)
        assert(decodedOld.sessionCreated == nil)
        let legacyDiscovered = try JSONDecoder().decode(RemoteProfile.self,
            from: Data(#"{"hostAlias":"host","directory":"/srv","sessionName":"$3"}"#.utf8))
        assertThrows { try legacyDiscovered.arguments(create: false) }
        let invalid = #"{"hostAlias":"host","directory":"relative","sessionName":"trellis-00000000-0000-0000-0000-000000000000"}"#
        assertThrows { try JSONDecoder().decode(RemoteProfile.self, from: Data(invalid.utf8)) }

        let plain = try RemoteProfile(hostAlias: "user@host")
        let plainArguments = try plain.arguments(create: false)
        assert(plain.mode == .shell && !plain.isPersistent && plain.sessionName.isEmpty)
        assert(plainArguments == ["-t", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
                                  "-o", "ForwardAgent=no", "--", "user@host"])
        let plainRoundTrip = try JSONDecoder().decode(RemoteProfile.self, from: JSONEncoder().encode(plain))
        assert(plainRoundTrip == plain)
        assertThrows { try RemoteProfile(hostAlias: "host", directory: "/", sessionName: session, mode: .shell) }
        assertThrows { try RemoteProfile(hostAlias: "host", directory: "/", sessionName: "", tmuxExecutable: "tmux", mode: .shell) }
        assertThrows { try RemoteProfile(hostAlias: "host", directory: "relative") }
        try checkPlainDirectory()

        print("remote profile checks passed")
    }

    private static func checkPlainDirectory() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Trellis-SSHDirectory-\(UUID())")
        defer { try? manager.removeItem(at: root) }
        let directory = root.appendingPathComponent("literal ' $(unchanged) — 東京")
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let shell = root.appendingPathComponent("fixture-shell")
        let output = root.appendingPathComponent("working-directory")
        try Data("#!/bin/sh\nprintf '%s' \"$PWD\" > \"$CAPTURE_PATH\"\n".utf8).write(to: shell)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shell.path)
        let profile = try RemoteProfile(hostAlias: "fixture", directory: directory.path)
        let arguments = try profile.arguments(create: false)
        assert(!arguments.joined().contains("tmux"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", arguments.last!]
        process.environment = ["PATH": "/usr/bin:/bin", "SHELL": shell.path, "CAPTURE_PATH": output.path]
        try process.run(); process.waitUntilExit()
        assert(process.terminationStatus == 0)
        let actual = try String(contentsOf: output, encoding: .utf8)
        assert(actual == directory.path, "Ordinary SSH must enter the exact quoted directory without interpreting its name")
    }

    private static func assertThrows(_ operation: () throws -> Any) {
        do {
            _ = try operation()
            preconditionFailure("Expected validation failure")
        } catch {}
    }
}
