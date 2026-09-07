import Foundation

@main
struct SessionIdentityCheck {
    @MainActor
    static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("trellis-session-identity-\(UUID())")
        let file = root.appendingPathComponent("identities.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let session = UUID()
        let first = SessionIdentityStore(workspaceID: UUID(), storageFile: file)
        precondition(first.setSymbol("terminal.fill", for: session))
        precondition(first.setAccent("#12ab34", for: session))
        precondition(!first.setAccent("unsafe", for: session))
        precondition(first.setAccent(nil, for: session))
        precondition(first.setAccent("12ab34", for: session))

        let restored = SessionIdentityStore(workspaceID: UUID(), storageFile: file)
        precondition(restored.identity(for: session) == SessionIdentity(iconSFsymbol: "terminal.fill", accentHex: "12AB34"))
        precondition(restored.reset(session))
        precondition(restored.identity(for: session).isDefault)

        try! Data(repeating: 0, count: 8 * 1_024 * 1_024 + 1).write(to: file)
        let oversized = SessionIdentityStore(workspaceID: UUID(), storageFile: file)
        precondition(oversized.error != nil)
        print("session identity check passed")
    }
}
