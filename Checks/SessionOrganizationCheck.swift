import Foundation

@main
struct SessionOrganizationCheck {
    @MainActor
    static func main() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("trellis-session-organization-\(UUID())")
        let file = root.appendingPathComponent("organization.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let workspaceID = UUID()
        let first = SessionOrganization(workspaceID: workspaceID, storageFile: file)
        guard let work = first.createCategory("Work"), first.createCategory("work") == nil else { fatalError("category validation failed") }
        let session = UUID()
        guard first.assign(session, to: work), first.setSort(.harness) else { fatalError("persistence write failed") }

        let restored = SessionOrganization(workspaceID: workspaceID, storageFile: file)
        guard restored.categories == [SessionCategory(id: work, name: "Work")], restored.category(for: session) == work, restored.sort == .harness else {
            fatalError("persistence restore failed")
        }
        let destination = SessionOrganization(workspaceID: UUID(), storageFile: root.appendingPathComponent("destination.json"))
        let matching = destination.createCategory("work")!
        precondition(destination.copySessions([session], from: restored))
        precondition(destination.categories.count == 1 && destination.category(for: session) == matching)
        precondition(restored.category(for: session) == work)
        guard restored.removeCategory(work), restored.category(for: session) == nil else { fatalError("category removal must only clear assignments") }

        try! Data(repeating: 0, count: 65_537).write(to: file)
        let oversized = SessionOrganization(workspaceID: workspaceID, storageFile: file)
        guard oversized.readError != nil else { fatalError("oversized file was accepted") }
        print("session organization check passed")
    }
}
