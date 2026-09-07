import Foundation

@main
enum FilesCheck {
    static func main() throws {
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
        print("PASS local files enumeration, folder order, package closure, symlink protection, relative paths and missing-folder errors")
    }
}
