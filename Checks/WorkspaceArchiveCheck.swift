import Foundation

@main
enum WorkspaceArchiveCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("workspace.json")
        let project = URL(fileURLWithPath: "/tmp/Project with spaces — ツ")
        let sessionID = UUID()
        let removedShell = try ShellConfiguration(executable: "/private/tmp/trellis-removed-shell", arguments: ["-l"])
        let archive = WorkspaceArchive(
            projects: [project],
            sessions: [.init(id: sessionID, directory: project.path, profile: "shell", shellConfiguration: removedShell)],
            selectedProject: project,
            selectedSessionID: sessionID
        )
        try archive.save(to: file)
        let restored = try WorkspaceArchive.load(from: file)
        assert(restored == archive)
        assert(restored?.sessions.first?.shellConfiguration == removedShell)

        let legacyJSON = """
        {"version":1,"projects":["\(project.path)"],"sessions":[
          {"id":"\(sessionID)","directory":"\(project.path)","profile":"shell"}],
         "selectedProject":"\(project.path)","selectedSessionID":"\(sessionID)"}
        """
        let legacyData = Data(legacyJSON.utf8)
        let migrated = try JSONDecoder().decode(WorkspaceArchive.self, from: legacyData).validated()
        let migratedAgain = try JSONDecoder().decode(WorkspaceArchive.self, from: legacyData)
        assert(migrated.version == 2 && migrated.windows.count == 1)
        assert(migrated == migratedAgain && migrated.sessions.first?.id == sessionID)
        try migrated.save(to: file)
        let migratedRoundTrip = try WorkspaceArchive.load(from: file)
        assert(migratedRoundTrip == migrated)

        let second = WorkspaceArchive.WindowRecord(id: UUID(),
            sessions: [.init(id: UUID(), directory: project.path, profile: "shell")],
            selectedProject: project.path, selectedSessionID: nil)
        let multiple = WorkspaceArchive(projects: [project], windows: migrated.windows + [second])
        try multiple.save(to: file)
        let multipleRestored = try WorkspaceArchive.load(from: file)
        assert(multipleRestored == multiple && multipleRestored?.sessions.count == 2)
        let duplicateWindow = WorkspaceArchive(projects: [project], windows: [second, second])
        do { _ = try duplicateWindow.validated(); assertionFailure("Duplicate windows were accepted") }
        catch {}
        let duplicateSession = WorkspaceArchive.WindowRecord(id: UUID(), sessions: migrated.sessions,
            selectedProject: project.path, selectedSessionID: sessionID)
        do {
            _ = try WorkspaceArchive(projects: [project], windows: migrated.windows + [duplicateSession]).validated()
            assertionFailure("A session was shared between windows")
        } catch {}
        let foreignSelection = WorkspaceArchive.WindowRecord(id: UUID(), sessions: second.sessions,
            selectedProject: project.path, selectedSessionID: sessionID)
        do {
            _ = try WorkspaceArchive(projects: [project], windows: migrated.windows + [foreignSelection]).validated()
            assertionFailure("A window selected another window's session")
        } catch {}

        try Data("not json".utf8).write(to: file)
        do { _ = try WorkspaceArchive.load(from: file); assertionFailure("Corrupt JSON was accepted") }
        catch {
            let preserved = try String(contentsOf: file, encoding: .utf8)
            assert(preserved == "not json")
        }

        let invalidJSON = """
        {"version":1,"projects":["relative"],"sessions":[
          {"id":"\(sessionID)","directory":"/tmp/one","profile":"shell"},
          {"id":"\(sessionID)","directory":"/tmp/two","profile":"shell"}],
         "selectedProject":null,"selectedSessionID":"\(UUID())"}
        """
        let invalid = try JSONDecoder().decode(WorkspaceArchive.self, from: Data(invalidJSON.utf8))
        do { _ = try invalid.validated(); assertionFailure("Invalid identifiers and paths were accepted") }
        catch {}

        let missingProject = WorkspaceArchive(
            projects: [project],
            sessions: [.init(id: UUID(), directory: "/tmp/not-listed", profile: "shell")],
            selectedProject: project,
            selectedSessionID: nil
        )
        do { _ = try missingProject.validated(); assertionFailure("A session outside the project list was accepted") }
        catch {}

        let oversized = root.appendingPathComponent("oversized.json")
        try Data(repeating: 0x20, count: 1_048_577).write(to: oversized)
        do { _ = try WorkspaceArchive.load(from: oversized); assertionFailure("An oversized archive was accepted") }
        catch {}

        let target = root.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        let symlink = root.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        do { _ = try WorkspaceArchive.load(from: symlink); assertionFailure("A symlink archive was accepted") }
        catch {}
        do { try archive.save(to: symlink); assertionFailure("A symlink archive was overwritten") }
        catch {
            let targetData = try Data(contentsOf: target)
            assert(targetData == Data("{}".utf8))
        }
        print("workspace archive checks passed")
    }
}
