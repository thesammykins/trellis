import Darwin
import Foundation

@main struct AgentInstructionsCheck {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-instructions-" + UUID().uuidString)
        let home = root.appendingPathComponent("home"), project = root.appendingPathComponent("project/subfolder")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: URL, _ text: String) throws {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: path)
        }
        let global = home.appendingPathComponent(".agents/AGENTS.md")
        let target = root.appendingPathComponent("dotfiles/AGENTS.md")
        try write(target, "Global fixture guidance")
        try FileManager.default.createDirectory(at: global.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: global, withDestinationURL: target)
        try write(root.appendingPathComponent("project/AGENTS.md"), "Parent guidance")
        try write(project.appendingPathComponent("AGENTS.md"), "Project guidance")
        let skill = home.appendingPathComponent(".agents/skills/check/SKILL.md")
        try write(skill, "---\nname: check\ndescription: \"Review a fixture\"\n---\nBody retained only when selected")
        try write(home.appendingPathComponent(".agents/project-skills-library/archived/SKILL.md"), "---\nname: archived\ndescription: Archive\n---\nArchive body")
        try write(project.appendingPathComponent(".agents/skills/local/SKILL.md"), "---\nname: local\ndescription: 'Project skill'\n---\nLocal body")
        try write(project.appendingPathComponent(".agents/skills/bad/SKILL.md"), "---\nname: bad\nname: repeated\ndescription: Invalid\n---\nbody")
        try write(project.appendingPathComponent(".agents/skills/large/SKILL.md"), String(repeating: "x", count: AgentInstructions.maximumSourceBytes + 1))
        let snapshot = try AgentInstructions.discover(project: project, home: home)
        let sources = snapshot.instructions.filter { $0.declaredPath.hasPrefix(root.path) }
        precondition(sources.count == 3)
        precondition(sources.map(\.text) == ["Global fixture guidance", "Parent guidance", "Project guidance"])
        precondition(sources[0].declaredPath == global.path && sources[0].resolvedPath == target.resolvingSymlinksInPath().path)
        precondition(snapshot.skills.map(\.name) == ["check", "local"])
        precondition(snapshot.diagnostics.count == 2)
        let selected = snapshot.skills[0]
        let loaded = try snapshot.readSkill(id: selected.id)
        precondition(loaded.text.contains("Body retained only when selected") && loaded.sha256.count == 64)
        let reference = skill.deletingLastPathComponent().appendingPathComponent("references/guide.md")
        try write(reference, "Referenced fixture guidance")
        let referenceBody = try snapshot.readSkill(id: selected.id, path: "references/guide.md")
        precondition(referenceBody.text == "Referenced fixture guidance" && referenceBody.resolvedPath == reference.resolvingSymlinksInPath().path)
        expectFailure { _ = try snapshot.readSkill(id: selected.id, path: "../AGENTS.md") }
        expectFailure { _ = try snapshot.readSkill(id: selected.id, path: reference.path) }
        let outsideLink = skill.deletingLastPathComponent().appendingPathComponent("outside.md")
        try FileManager.default.createSymbolicLink(at: outsideLink, withDestinationURL: target)
        expectFailure { _ = try snapshot.readSkill(id: selected.id, path: "outside.md") }
        let resourceFIFO = skill.deletingLastPathComponent().appendingPathComponent("blocked")
        precondition(mkfifo(resourceFIFO.path, 0o600) == 0)
        expectFailure { _ = try snapshot.readSkill(id: selected.id, path: "blocked") }
        let oversized = skill.deletingLastPathComponent().appendingPathComponent("oversized.md")
        try write(oversized, String(repeating: "x", count: AgentInstructions.maximumSourceBytes + 1))
        expectFailure { _ = try snapshot.readSkill(id: selected.id, path: "oversized.md") }
        let again = try AgentInstructions.discover(project: project, home: home)
        precondition(again.skills[0].id == selected.id)
        let homeSnapshot = try AgentInstructions.discover(project: home, home: home)
        precondition(homeSnapshot.skills.count == 1 && homeSnapshot.skills[0].scope == home.path)
        precondition(homeSnapshot.skills[0].id == selected.id)
        let alias = project.appendingPathComponent(".agents/skills/global-alias/SKILL.md")
        try FileManager.default.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: skill)
        let aliased = try AgentInstructions.discover(project: project, home: home)
        precondition(aliased.skills.count == 2)
        let projectDeclaration = aliased.skills.first { $0.name == "check" }!
        precondition(projectDeclaration.scope == project.path && projectDeclaration.declaredPath == alias.path)
        precondition(projectDeclaration.resolvedPath == selected.resolvedPath)
        let aliasedBody = try aliased.readSkill(id: projectDeclaration.id)
        precondition(aliasedBody.sha256 == loaded.sha256)
        let aliasReference = try aliased.readSkill(id: projectDeclaration.id, path: "references/guide.md")
        precondition(aliasReference.sha256 == referenceBody.sha256)
        try FileManager.default.removeItem(at: alias)
        expectFailure { _ = try snapshot.readSkill(id: skill.path) }
        try write(skill, "---\nname: changed\ndescription: New metadata\n---\nBody")
        expectFailure { _ = try snapshot.readSkill(id: selected.id) }
        expectFailure { _ = try snapshot.readSkill(id: selected.id, path: "references/guide.md") }
        try write(project.appendingPathComponent("AGENTS.md"), "bad\0text")
        let invalid = try AgentInstructions.discover(project: project, home: home)
        precondition(invalid.diagnostics.contains { $0.contains("NUL") })
        let lazy = project.appendingPathComponent(".agents/skills/lazy/SKILL.md")
        try write(lazy, "---\nname: lazy\ndescription: Lazy body fixture\n---\n")
        let handle = try FileHandle(forWritingTo: lazy)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([255])); try handle.close()
        let lazySnapshot = try AgentInstructions.discover(project: project, home: home)
        let lazyID = lazySnapshot.skills.first { $0.name == "lazy" }!.id
        expectFailure { _ = try lazySnapshot.readSkill(id: lazyID) }
        try FileManager.default.removeItem(at: lazy)
        try FileManager.default.createSymbolicLink(at: lazy, withDestinationURL: target)
        expectFailure { _ = try lazySnapshot.readSkill(id: lazyID) }
        let fifo = project.appendingPathComponent(".agents/skills/fifo/SKILL.md")
        try FileManager.default.createDirectory(at: fifo.deletingLastPathComponent(), withIntermediateDirectories: true)
        precondition(mkfifo(fifo.path, 0o600) == 0)
        let special = try AgentInstructions.discover(project: project, home: home)
        precondition(special.diagnostics.contains { $0.contains("regular file") })
        print("Agent instructions: scoped ancestors, global symlink, catalog, lazy read, stable IDs, changed metadata and bounds passed")
    }
    private static func expectFailure(_ operation: () throws -> Void) {
        do { try operation(); preconditionFailure("Expected rejection") } catch {}
    }
}
