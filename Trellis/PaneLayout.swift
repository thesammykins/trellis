import Foundation

enum PaneDropPosition: String, CaseIterable, Identifiable {
    case left, right, above, below, swap
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PaneDragToken {
    static func encode(workspaceID: UUID, sessionID: UUID) -> String {
        "trellis-session:\(workspaceID.uuidString.lowercased()):\(sessionID.uuidString)"
    }

    static func sessionID(in token: String, workspaceID: UUID) -> UUID? {
        guard token.utf8.count <= 128 else { return nil }
        let parts = token.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "trellis-session",
              UUID(uuidString: String(parts[1])) == workspaceID else { return nil }
        return UUID(uuidString: String(parts[2]))
    }
}

/// Layout holds session identities only; each session retains its own Ghostty surface.
indirect enum PaneLayout: Codable, Equatable {
    case terminal(UUID)
    case split(vertical: Bool, first: PaneLayout, second: PaneLayout)

    var leaves: [UUID] {
        switch self {
        case .terminal(let id): [id]
        case .split(_, let first, let second): first.leaves + second.leaves
        }
    }

    func splitting(_ id: UUID, adding newID: UUID, vertical: Bool) -> PaneLayout {
        switch self {
        case .terminal(let leaf): leaf == id ? .split(vertical: vertical, first: self, second: .terminal(newID)) : self
        case .split(let axis, let first, let second):
            .split(vertical: axis, first: first.splitting(id, adding: newID, vertical: vertical),
                   second: second.splitting(id, adding: newID, vertical: vertical))
        }
    }

    func removing(_ id: UUID) -> PaneLayout? {
        switch self {
        case .terminal(let leaf): return leaf == id ? nil : self
        case .split(let vertical, let first, let second):
            let a = first.removing(id), b = second.removing(id)
            if let a, let b { return .split(vertical: vertical, first: a, second: b) }
            return a ?? b
        }
    }

    func balanced() throws -> PaneLayout {
        let ids = try validatedLeaves()
        func build(_ ids: ArraySlice<UUID>, vertical: Bool) -> PaneLayout {
            if ids.count == 1 { return .terminal(ids.first!) }
            let middle = ids.index(ids.startIndex, offsetBy: ids.count / 2)
            return .split(vertical: vertical,
                          first: build(ids[..<middle], vertical: !vertical),
                          second: build(ids[middle...], vertical: !vertical))
        }
        return build(ids[...], vertical: false)
    }

    static func moving(_ source: UUID, to target: UUID, position: PaneDropPosition, in layouts: [PaneLayout]) throws -> [PaneLayout] {
        let original = try layouts.flatMap { try $0.validatedLeaves() }
        guard source != target, original.contains(source), original.contains(target),
              Set(original).count == original.count else {
            throw WorkspaceArchive.Failure("Choose two distinct existing panes in a valid workspace")
        }
        let result: [PaneLayout]
        if position == .swap {
            result = layouts.map { $0.replacingLeaves { id in .terminal(id == source ? target : id == target ? source : id) } }
        } else {
            let sourceFirst = position == .left || position == .above
            let vertical = position == .above || position == .below
            result = layouts.compactMap { $0.removing(source) }.map { layout in
                layout.replacingLeaves { id in
                    guard id == target else { return .terminal(id) }
                    return .split(vertical: vertical,
                                  first: .terminal(sourceFirst ? source : target),
                                  second: .terminal(sourceFirst ? target : source))
                }
            }
        }
        let moved = try result.flatMap { try $0.validatedLeaves() }
        guard moved.count == original.count, Set(moved) == Set(original) else {
            throw WorkspaceArchive.Failure("Moving panes must preserve every session exactly once")
        }
        return result
    }

    private func replacingLeaves(_ replacement: (UUID) -> PaneLayout) -> PaneLayout {
        switch self {
        case .terminal(let id): return replacement(id)
        case .split(let vertical, let first, let second):
            return .split(vertical: vertical, first: first.replacingLeaves(replacement), second: second.replacingLeaves(replacement))
        }
    }

    func validatedLeaves(depth: Int = 0) throws -> [UUID] {
        guard depth < 8 else { throw WorkspaceArchive.Failure("Pane layout is too deeply nested") }
        switch self {
        case .terminal(let id): return [id]
        case .split(_, let first, let second):
            let ids = try first.validatedLeaves(depth: depth + 1) + second.validatedLeaves(depth: depth + 1)
            guard ids.count <= 8, Set(ids).count == ids.count else {
                throw WorkspaceArchive.Failure("A tab supports up to eight distinct panes")
            }
            return ids
        }
    }
}

struct SessionLaunchSettings: Codable, Equatable {
    var model: String = ""
    var reasoning: String = ""

    func validate() throws {
        guard model.utf8.count <= 256, reasoning.utf8.count <= 32,
              !model.hasPrefix("-"),
              !model.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              reasoning.utf8.allSatisfy({ (97...122).contains($0) }) else {
            throw WorkspaceArchive.Failure("Invalid saved model or reasoning setting")
        }
    }

    func arguments(for profile: LaunchProfile) throws -> [String] {
        try validate()
        return try AgentResume.modelArguments(profile: profile, model: model)
            + AgentResume.reasoningArguments(profile: profile, effort: reasoning)
    }
}
