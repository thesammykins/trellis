import AppKit
import Foundation

@main
enum FilesCheck {
    @MainActor
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("TrellisFilesCheck-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let folder = root.appendingPathComponent("Folder", isDirectory: true)
        let package = root.appendingPathComponent("Fixture.app", isDirectory: true)
        let file = root.appendingPathComponent("notes.txt")
        let link = root.appendingPathComponent("Folder link")
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        try manager.createDirectory(at: package, withIntermediateDirectories: false)
        try Data().write(to: file)
        try manager.createSymbolicLink(at: link, withDestinationURL: folder)

        let entries = try FilesDirectoryReader.children(of: root)
        precondition(entries.first?.url.lastPathComponent == folder.lastPathComponent, "expandable folders sort first")
        precondition(entries.first(where: { $0.url.lastPathComponent == folder.lastPathComponent })?.canExpand == true)
        precondition(entries.first(where: { $0.url.lastPathComponent == package.lastPathComponent })?.isPackage == true)
        precondition(entries.first(where: { $0.url.lastPathComponent == package.lastPathComponent })?.canExpand == false, "packages stay closed")
        precondition(entries.first(where: { $0.url.lastPathComponent == link.lastPathComponent })?.isSymbolicLink == true)
        precondition(entries.first(where: { $0.url.lastPathComponent == link.lastPathComponent })?.canExpand == false, "symlinks cannot recurse")
        precondition(FilesDirectoryReader.relativePath(for: file, root: root) == "notes.txt")
        precondition(FilesDirectoryReader.relativePath(for: root.deletingLastPathComponent(), root: root) == nil)
        do {
            _ = try FilesDirectoryReader.children(of: root, maximumEntries: 2)
            preconditionFailure("large directories must be bounded")
        } catch FilesDirectoryError.tooManyEntries(2) {}

        let missing = root.appendingPathComponent("missing", isDirectory: true)
        precondition((try? FilesDirectoryReader.children(of: missing)) == nil, "missing folders surface an error")
        try await checkRefresh(root: root, folder: folder, file: file)
        print("PASS local files enumeration, folder order, package closure, symlink protection, relative paths and missing-folder errors")
    }

    @MainActor
    private static func checkRefresh(root: URL, folder: URL, file: URL) async throws {
        _ = NSApplication.shared
        let outline = NSOutlineView()
        let column = NSTableColumn(identifier: .init("file"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        let coordinator = FilesOutline.Coordinator(rootURL: root)
        coordinator.outline = outline
        outline.dataSource = coordinator
        outline.delegate = coordinator
        func item(_ name: String) -> Any? {
            for row in 0..<outline.numberOfRows {
                guard let item = outline.item(atRow: row),
                      let cell = coordinator.outlineView(outline, viewFor: column, item: item) as? NSTableCellView else { continue }
                if cell.textField?.stringValue == name { return item }
            }
            return nil
        }
        try Data().write(to: folder.appendingPathComponent("before.txt"))
        coordinator.reload(rootURL: root)
        try await wait("initial folder") { item("Folder") != nil }
        let folderItem = item("Folder")!
        outline.expandItem(folderItem)
        try await wait("expanded child") { item("before.txt") != nil }
        outline.collapseItem(folderItem)

        try Data().write(to: folder.appendingPathComponent("after.txt"))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        try Data().write(to: root.appendingPathComponent("refresh-marker"))
        coordinator.reload(rootURL: root)
        try await wait("refreshed root") { item("refresh-marker") != nil }
        outline.expandItem(folderItem)
        try await wait("refresh must invalidate cached collapsed children") { item("after.txt") != nil }
        precondition(coordinator.outlineView(outline, isItemExpandable: item("notes.txt")!),
                     "refresh must recognize a file replaced by a directory")

        try Data().write(to: folder.appendingPathComponent("while-open.txt"))
        coordinator.reload(rootURL: root)
        try await wait("refresh must update expanded children") { item("while-open.txt") != nil }
        print("PASS native outline refresh updates collapsed/expanded children and changed file types")
    }

    @MainActor
    private static func wait(_ message: String, until condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure(message)
    }
}
