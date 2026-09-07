import Foundation

@main
struct WorkspaceAppearanceCheck {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("appearance.json")
        let project = URL(fileURLWithPath: "/fixture/private-project")
        let first = WorkspaceAppearanceStore(project: project, file: file)
        let second = WorkspaceAppearanceStore(project: URL(fileURLWithPath: "/fixture/other"), file: file)
        var defaults = first.preferences
        defaults.verticalTabWidth = 300
        defaults.horizontalDetails = [.diff, .branch, .harness]
        try first.update(defaults)
        assert(second.preferences == defaults, "Global edits did not reach another window")
        try first.setProjectOverride(true)
        var override = defaults
        override.verticalTabWidth = 160
        override.inspectorSide = .left
        override.sidebarSections = [.knowledge, .sessions]
        try first.update(override)
        assert(first.hasProjectOverride && second.preferences == defaults)
        var otherDefaults = second.preferences
        otherDefaults.density = .compact
        try second.update(otherDefaults)
        assert(first.preferences == override, "Global edits changed a project override")
        first.switchProject(URL(fileURLWithPath: "/fixture/other"))
        assert(first.preferences == otherDefaults && !first.hasProjectOverride)
        first.switchProject(project)
        assert(first.preferences == override)
        try first.savePreset(named: "Compact review")
        assert(first.savedPresets.count == 1 && second.savedPresets.count == 1)
        let exported = try first.exportPreset()
        let text = String(decoding: exported, as: UTF8.self)
        assert(!text.contains("private-project") && !text.contains("fixture") && !text.contains("projects"))
        try second.importPreset(exported)
        assert(second.preferences == override)
        let before = try Data(contentsOf: file)
        for invalid in [Data("{}".utf8), Data(repeating: 0, count: 16_385), Data(text.replacingOccurrences(of: "160", with: "999").utf8), Data(text.replacingOccurrences(of: "\"version\":1", with: "\"version\":99").utf8)] {
            do { try first.importPreset(invalid); assertionFailure("Invalid preset accepted") } catch {}
            let after = try Data(contentsOf: file)
            assert(after == before, "Invalid import overwrote settings")
        }
        var duplicate = override
        duplicate.horizontalDetails = [.folder, .folder]
        do { try first.update(duplicate); assertionFailure("Duplicate detail accepted") } catch {}
        try first.setProjectOverride(false)
        assert(!first.hasProjectOverride && first.preferences == second.preferences)
        try first.reset()
        assert(first.preferences == WorkspaceAppearance())
        try Data("corrupt".utf8).write(to: file)
        let broken = WorkspaceAppearanceStore(project: project, file: file)
        assert(broken.error != nil)
        do { try broken.reset(); assertionFailure("Corrupt settings overwritten") } catch {}
        let preserved = try Data(contentsOf: file)
        assert(preserved == Data("corrupt".utf8))
        print("workspace appearance checks passed")
    }
}
