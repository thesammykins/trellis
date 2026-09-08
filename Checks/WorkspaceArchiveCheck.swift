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
        assert(migrated.activeWindowID == nil, "Legacy archives have no saved active window")
        assert(migrated == migratedAgain && migrated.sessions.first?.id == sessionID)
        try migrated.save(to: file)
        let migratedRoundTrip = try WorkspaceArchive.load(from: file)
        assert(migratedRoundTrip == migrated)

        let harness = try CustomHarness(id: UUID(uuidString: "B2B945B3-2DD0-41A6-A69F-F77AC030187C")!,
            name: "Fixture Codex", executable: "/usr/local/bin/fixture-codex",
            arguments: ["--config", "literal=two words", "$(unchanged)"], integration: "codex")
        let settings = SessionLaunchSettings(model: "saved-model", reasoning: "high")
        let customLegacyJSON = """
        {"version":1,"projects":["\(project.path)"],"sessions":[
          {"id":"\(sessionID)","directory":"\(project.path)","profile":"custom",
           "nickname":"Saved agent","favourite":true,"memoryEnabled":true,
           "launchSettings":{"model":"saved-model","reasoning":"high"},
           "customHarness":{"id":"\(harness.id)","name":"Fixture Codex",
             "executable":"/usr/local/bin/fixture-codex",
             "arguments":["--config","literal=two words","$(unchanged)"],"integration":"codex"}}],
         "selectedProject":"\(project.path)","selectedSessionID":"\(sessionID)"}
        """
        let customMigrated = try JSONDecoder().decode(WorkspaceArchive.self, from: Data(customLegacyJSON.utf8)).validated()
        let customSession = customMigrated.sessions[0]
        assert(customMigrated.version == 2 && customSession.profile == "custom" && customSession.id == sessionID)
        assert(customSession.customHarness == harness && customSession.launchSettings == settings)
        assert(customSession.launchSettings?.historyID == nil, "Old settings without historyID must still decode")
        assert(customSession.nickname == "Saved agent" && customSession.favourite == true && customSession.memoryEnabled == true)
        let integration = LaunchProfile(rawValue: customSession.customHarness!.integration!)!
        let arguments = try customSession.customHarness!.arguments + customSession.launchSettings!.arguments(for: integration)
        assert(arguments == ["--config", "literal=two words", "$(unchanged)", "--model", "saved-model", "-c", "model_reasoning_effort=\"high\""])
        try customMigrated.save(to: file)
        let customRestored = try WorkspaceArchive.load(from: file)
        assert(customRestored == customMigrated)

        let historyID = "exact history; $(literal)"
        let resumedJSON = customLegacyJSON.replacingOccurrences(of: #""reasoning":"high""#,
            with: "\"reasoning\":\"high\",\"historyID\":\"\(historyID)\"")
        let resumed = try JSONDecoder().decode(WorkspaceArchive.self, from: Data(resumedJSON.utf8)).validated()
        let resumedSession = resumed.sessions[0]
        assert(resumedSession.launchSettings?.historyID == historyID)
        let resumedArguments = try resumedSession.customHarness!.arguments + resumedSession.launchSettings!.arguments(for: integration)
        assert(resumedArguments == arguments + ["resume", historyID], "Archived resume IDs must remain one exact argument after restoration")
        try resumed.save(to: file)
        let resumedRestored = try WorkspaceArchive.load(from: file)
        assert(resumedRestored == resumed)
        let restoredArguments = try resumedRestored!.sessions[0].customHarness!.arguments
            + resumedRestored!.sessions[0].launchSettings!.arguments(for: integration)
        assert(restoredArguments == resumedArguments)
        let openCodeArguments = try SessionLaunchSettings(model: "saved-model", historyID: historyID).arguments(for: .opencode)
        assert(openCodeArguments == ["--model", "saved-model", "--session", historyID])
        for invalidID in ["", "-last", "--session", "bad\nid", "bad\rid", "bad\0id", String(repeating: "x", count: 513)] {
            var invalidSession = customSession
            invalidSession.launchSettings = SessionLaunchSettings(historyID: invalidID)
            do {
                _ = try WorkspaceArchive(projects: [project], sessions: [invalidSession], selectedProject: project,
                    selectedSessionID: sessionID).validated()
                preconditionFailure("Invalid history ID was accepted by the archive")
            } catch let error as AgentResumeFailure { assert(error == .invalidID) }
        }
        for profile in LaunchProfile.allCases where profile != .codex && profile != .opencode {
            do {
                _ = try SessionLaunchSettings(historyID: historyID).arguments(for: profile)
                preconditionFailure("Unsupported integration accepted resume history")
            } catch let error as AgentResumeFailure { assert(error == .unavailable(profile.title)) }
        }
        for invalidSession in [
            WorkspaceArchive.Session(id: sessionID, directory: project.path, profile: "custom"),
            .init(id: sessionID, directory: project.path, profile: "codex", customHarness: harness),
        ] {
            do {
                _ = try WorkspaceArchive(projects: [project], sessions: [invalidSession], selectedProject: project,
                    selectedSessionID: sessionID).validated()
                assertionFailure("Only custom sessions may carry a required custom harness descriptor")
            } catch {}
        }

        let second = WorkspaceArchive.WindowRecord(id: UUID(),
            sessions: [.init(id: UUID(), directory: project.path, profile: "shell")],
            selectedProject: project.path, selectedSessionID: nil)
        let multiple = WorkspaceArchive(projects: [project], windows: migrated.windows + [second])
        try multiple.save(to: file)
        let multipleRestored = try WorkspaceArchive.load(from: file)
        assert(multipleRestored == multiple && multipleRestored?.sessions.count == 2)
        assert(multipleRestored?.activeWindowID == nil, "Version 2 archives without activation metadata must remain compatible")
        let paneIDs = (0..<8).map { _ in UUID() }
        var pane = PaneLayout.terminal(paneIDs[0])
        for index in 1..<paneIDs.count { pane = pane.splitting(paneIDs[index - 1], adding: paneIDs[index], vertical: index.isMultiple(of: 2)) }
        let lastUsed = Date(timeIntervalSince1970: 1_800_000_000)
        let codexThreadID = UUID().uuidString.lowercased()
        let savedPanes = paneIDs.enumerated().map { index, id in
            WorkspaceArchive.Session(id: id, directory: project.path, profile: "shell", lastTitle: "Saved shell \(index)", lastUsedAt: lastUsed,
                codexThreadID: index == 3 ? codexThreadID : nil)
        }
        let home = WorkspaceArchive.WindowRecord(id: UUID(), sessions: savedPanes, selectedProject: project.path,
            selectedSessionID: paneIDs[3], layouts: [pane],
            presentation: .init(destination: "home", showsSidebar: false, showsMemory: true, inspectorSection: "agent", maximizedPaneID: paneIDs[3], paneArrangementID: UUID()))
        let terminal = WorkspaceArchive.WindowRecord(id: UUID(), sessions: second.sessions, selectedProject: project.path,
            selectedSessionID: second.sessions[0].id, layouts: [.terminal(second.sessions[0].id)],
            presentation: .init(destination: "terminal", inspectorSection: "learn"))
        let presentationArchive = WorkspaceArchive(projects: [project], windows: [home, terminal], activeWindowID: home.id)
        try presentationArchive.save(to: file)
        let presentationRestored = try WorkspaceArchive.load(from: file)
        assert(presentationRestored == presentationArchive)
        assert(presentationRestored?.activeWindowID == home.id, "Active window must survive independently of archive window order")
        let validArchiveData = try Data(contentsOf: file)
        let missingActiveWindow = WorkspaceArchive(projects: [project], windows: [home, terminal], activeWindowID: UUID())
        do {
            try missingActiveWindow.save(to: file)
            preconditionFailure("A missing active window was accepted")
        } catch {}
        let preservedArchiveData = try Data(contentsOf: file)
        assert(preservedArchiveData == validArchiveData, "Invalid activation metadata must not replace the saved workspace")
        do {
            _ = try WorkspaceArchive(projects: [project], windows: [], activeWindowID: home.id).validated()
            preconditionFailure("An empty archive accepted an active window")
        } catch {}
        assert(presentationRestored?.windows[0].layouts?.first?.leaves == paneIDs)
        assert(presentationRestored?.windows[0].presentation?.destination == "home")
        assert(presentationRestored?.windows[0].sessions[3].lastTitle == "Saved shell 3")
        assert(presentationRestored?.windows[0].sessions[3].codexThreadID == codexThreadID)
        assert(migrated.windows[0].presentation == nil && migrated.sessions[0].lastUsedAt == nil && migrated.sessions[0].codexThreadID == nil)
        for invalidThreadID in ["", "has spaces", "bad\nthread", String(repeating: "x", count: 257)] {
            var invalid = savedPanes[0]
            invalid.codexThreadID = invalidThreadID
            do {
                _ = try WorkspaceArchive(projects: [project], sessions: [invalid], selectedProject: project, selectedSessionID: invalid.id).validated()
                preconditionFailure("Invalid native Codex thread identity accepted")
            } catch {}
        }
        var badPresentation = home
        badPresentation.presentation?.destination = "unrecognized"
        do { _ = try WorkspaceArchive(projects: [project], windows: [badPresentation]).validated(); preconditionFailure("Invalid destination accepted") } catch {}
        badPresentation = home
        badPresentation.presentation?.maximizedPaneID = paneIDs[0]
        do { _ = try WorkspaceArchive(projects: [project], windows: [badPresentation]).validated(); preconditionFailure("Unselected maximized pane accepted") } catch {}
        let plainSSH = try RemoteProfile(hostAlias: "lab")
        let sshRecord = WorkspaceArchive.WindowRecord(id: UUID(), sessions: [.init(id: UUID(), directory: project.path, profile: "remote", remote: plainSSH)],
            selectedProject: project.path, selectedSessionID: nil, presentation: .init(destination: "home"))
        let sshArchive = WorkspaceArchive(projects: [project], windows: [sshRecord])
        try sshArchive.save(to: file)
        let restoredSSH = try WorkspaceArchive.load(from: file)
        assert(restoredSSH?.sessions[0].remote == plainSSH && restoredSSH?.sessions[0].remote?.isPersistent == false)
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
