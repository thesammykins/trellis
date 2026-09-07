import Foundation

@main enum PaneLayoutCheck {
    static func main() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let tree = PaneLayout.terminal(a).splitting(a, adding: b, vertical: false).splitting(b, adding: c, vertical: true)
        let leaves = try tree.validatedLeaves(); assert(leaves == [a, b, c])
        assert(tree.removing(b)?.leaves == [a, c])
        assert(tree.removing(a)?.removing(b)?.removing(c) == nil)
        let encoded = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(PaneLayout.self, from: encoded); assert(decoded == tree)
        let settings = SessionLaunchSettings(model: "gpt-5.6-luna", reasoning: "max")
        let args = try settings.arguments(for: .codex); assert(args == ["--model", "gpt-5.6-luna", "-c", "model_reasoning_effort=\"max\""])
        do { _ = try PaneLayout.split(vertical: false, first: .terminal(a), second: .terminal(a)).validatedLeaves(); fatalError("duplicate accepted") } catch {}
        do { try SessionLaunchSettings(model: "bad\ncommand").validate(); fatalError("bad model accepted") } catch {}
        let directory = URL(fileURLWithPath: "/tmp")
        let archive = WorkspaceArchive(projects: [directory], windows: [.init(id: UUID(), sessions: [
            .init(id: a, directory: "/tmp", profile: "codex", launchSettings: settings),
            .init(id: b, directory: "/tmp", profile: "shell"), .init(id: c, directory: "/tmp", profile: "shell")
        ], selectedProject: "/tmp", selectedSessionID: b, layouts: [tree])])
        let roundtrip = try JSONDecoder().decode(WorkspaceArchive.self, from: JSONEncoder().encode(archive)).validated()
        assert(roundtrip == archive)
        let original = [tree, PaneLayout.terminal(UUID())]
        let source = original[1].leaves[0]
        for position in PaneDropPosition.allCases {
            let moved = try PaneLayout.moving(source, to: b, position: position, in: original)
            assert(Set(moved.flatMap(\.leaves)) == Set(original.flatMap(\.leaves)))
            assert(moved.flatMap(\.leaves).count == 4)
            assert(original[0] == tree, "Moving changed the original value")
            if position == .swap {
                assert(moved[0].leaves == [a, source, c] && moved[1].leaves == [b])
            } else {
                assert(moved.count == 1)
                assert(moved[0].leaves == (position == .left || position == .above ? [a, source, b, c] : [a, b, source, c]))
            }
        }
        let inside = try PaneLayout.moving(a, to: c, position: .below, in: [tree])
        assert(inside == [.split(vertical: true, first: .terminal(b), second: .split(vertical: true, first: .terminal(c), second: .terminal(a)))])
        let insideSwap = try PaneLayout.moving(a, to: c, position: .swap, in: [tree])
        assert(insideSwap[0].leaves == [c, b, a])
        for (sourceID, targetID, input) in [(a, a, [tree]), (UUID(), a, [tree]), (a, UUID(), [tree]), (a, b, [tree, .terminal(a)])] {
            do { _ = try PaneLayout.moving(sourceID, to: targetID, position: .right, in: input); fatalError("Invalid move accepted") } catch {}
        }
        let eightIDs = (0..<8).map { _ in UUID() }
        var full = PaneLayout.terminal(eightIDs[0])
        for index in 1..<eightIDs.count { full = full.splitting(eightIDs[index - 1], adding: eightIDs[index], vertical: false) }
        let fullIDs = try full.validatedLeaves()
        assert(fullIDs.count == 8)
        let fullInput = [full, PaneLayout.terminal(source)]
        do { _ = try PaneLayout.moving(source, to: eightIDs.last!, position: .below, in: fullInput); fatalError("Ninth pane accepted") } catch {}
        assert(fullInput[0] == full)
        let fullSwap = try PaneLayout.moving(source, to: eightIDs.last!, position: .swap, in: fullInput)
        assert(fullSwap[0].leaves.count == 8 && fullSwap[1].leaves == [eightIDs.last!])
        print("pane split/collapse, layout archive and model settings checks passed")
    }
}
