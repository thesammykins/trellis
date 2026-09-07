import Foundation

@main struct Check {
    static func main() async throws {
        let parsed = try PersistentSessions.parse("$12|123|2|0|build machine")
        precondition(parsed.first?.name == "build machine")
        let delimitedName = try PersistentSessions.parse("$14|123|1|0|build|machine")
        precondition(delimitedName.first?.name == "build|machine")
        let human = try PersistentSessions.parse("$13|123|1|0|trellis-UX6-dogfood").first!
        precondition(human.readableName == "trellis-UX6-dogfood")
        for invalid in ["$1;kill|123|2|0|bad", "$1|0|2|0|bad", "$1|123|2|0|x\n$1|123|2|0|y"] {
            do { _ = try PersistentSessions.parse(invalid); preconditionFailure("accepted invalid session") } catch {}
        }
        let executable = try MultiplexerProfile.executable(searchPath: AgentInstallation.searchPath)
        let name = "trellis-" + UUID().uuidString
        func command(_ args: [String]) throws {
            let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
            try p.run(); p.waitUntilExit(); precondition(p.terminationStatus == 0)
        }
        try command(["new-session", "-d", "-s", name, "/bin/sh"])
        defer {
            let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = ["kill-session", "-t", "=" + name]
            p.standardError = FileHandle.nullDevice; try? p.run(); p.waitUntilExit()
        }
        let service = PersistentSessions(host: nil, executable: executable)
        let before = try await service.list()
        guard let fixture = before.first(where: { $0.name == name }) else { fatalError("fixture absent") }
        let staleProfile = try MultiplexerProfile(sessionName: fixture.id, sessionCreated: fixture.created + 1)
        let staleAttach = Process(); staleAttach.executableURL = URL(fileURLWithPath: executable)
        staleAttach.arguments = try staleProfile.arguments(create: false, directory: FileManager.default.temporaryDirectory)
        staleAttach.standardOutput = FileHandle.nullDevice; staleAttach.standardError = FileHandle.nullDevice
        try staleAttach.run(); staleAttach.waitUntilExit()
        precondition(staleAttach.terminationStatus == 73)
        let afterRefusal = try await service.list()
        precondition(afterRefusal.contains { $0.id == fixture.id && $0.created == fixture.created })
        try await service.end(fixture)
        let after = try await service.list()
        precondition(!after.contains { $0.name == name })
        precondition(Set(before.filter { $0.name != name }.map(\.id)).isSubset(of: Set(after.map(\.id))))
        do { try await service.end(fixture); preconditionFailure("stale end accepted") } catch {}
        print("PASS session discovery, exact end, stale selection and unrelated session preservation")
    }
}
