import Darwin
import Foundation

@main enum ProjectDirectoryCheck {
    static func main() async throws {
        let manager = FileManager.default
        let fixture = manager.temporaryDirectory.appendingPathComponent("Trellis-projects-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: fixture) }
        let root = fixture.appendingPathComponent("Projects", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        let canonicalPath = realpath(root.path, nil)!
        defer { free(canonicalPath) }
        let canonicalRoot = URL(fileURLWithPath: String(cString: canonicalPath), isDirectory: true)
        let suite = "ProjectDirectoryCheck-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        precondition(ProjectDirectory.root(from: defaults) == manager.homeDirectoryForCurrentUser.appendingPathComponent("Development", isDirectory: true))
        defaults.set("relative/projects", forKey: ProjectDirectory.defaultsKey)
        precondition(ProjectDirectory.root(from: defaults) == manager.homeDirectoryForCurrentUser.appendingPathComponent("Development", isDirectory: true))
        try ProjectDirectory.setRoot(root, to: defaults)
        precondition(ProjectDirectory.root(from: defaults) == canonicalRoot)
        precondition(defaults.string(forKey: ProjectDirectory.defaultsKey) == canonicalRoot.path)

        let missing = fixture.appendingPathComponent("Missing/Parent", isDirectory: true)
        defaults.set(missing.path, forKey: ProjectDirectory.defaultsKey)
        precondition(ProjectDirectory.root(from: defaults).path == missing.path)
        precondition(!manager.fileExists(atPath: missing.deletingLastPathComponent().path), "Loading the root created ancestors")
        expectFailure(containing: "Finder") { try ProjectDirectory.createProject(named: "Child", root: missing) }
        expectFailure { try ProjectDirectory.setRoot(missing, to: defaults) }
        precondition(!manager.fileExists(atPath: missing.deletingLastPathComponent().path))
        try ProjectDirectory.setRoot(root, to: defaults)

        let name = "Sammy's project 空間"
        let project = try ProjectDirectory.createProject(named: name, root: root)
        precondition(project == canonicalRoot.appendingPathComponent(name, isDirectory: true))
        let emptyProject = try manager.contentsOfDirectory(atPath: project.path)
        precondition(emptyProject.isEmpty)
        let marker = project.appendingPathComponent("keep.txt")
        try Data("unchanged".utf8).write(to: marker)
        expectFailure(containing: "already exists") { try ProjectDirectory.createProject(named: name, root: root) }
        let retainedMarker = try Data(contentsOf: marker)
        precondition(retainedMarker == Data("unchanged".utf8))
        let existingFile = root.appendingPathComponent("existing-file")
        try Data("keep file".utf8).write(to: existingFile)
        expectFailure { try ProjectDirectory.createProject(named: "existing-file", root: root) }
        expectFailure { try ProjectDirectory.setRoot(existingFile, to: defaults) }
        precondition(ProjectDirectory.root(from: defaults) == canonicalRoot)
        let retainedFile = try Data(contentsOf: existingFile)
        precondition(retainedFile == Data("keep file".utf8))
        let maximumName = String(repeating: "x", count: 255)
        let maximumProject = try ProjectDirectory.createProject(named: maximumName, root: root)
        precondition(maximumProject.lastPathComponent == maximumName)

        let before = try manager.contentsOfDirectory(atPath: root.path).sorted()
        for invalid in ["", " ", ".", "..", "../escape", "a/b", "/absolute", "bad\0name", "bad\nname", "bad\tname", "bad\u{2028}name", String(repeating: "x", count: 256), String(repeating: "界", count: 86)] {
            expectFailure { try ProjectDirectory.createProject(named: invalid, root: root) }
        }
        let after = try manager.contentsOfDirectory(atPath: root.path).sorted()
        precondition(after == before)
        expectFailure { try ProjectDirectory.setRoot(URL(string: "https://example.com/projects")!, to: defaults) }
        expectFailure { try ProjectDirectory.createProject(named: "Child", root: URL(string: "file://example.com/tmp")!) }

        let outside = fixture.appendingPathComponent("Outside", isDirectory: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: false)
        let childLink = root.appendingPathComponent("linked-child")
        try manager.createSymbolicLink(at: childLink, withDestinationURL: outside)
        expectFailure(containing: "already exists") { try ProjectDirectory.createProject(named: "linked-child", root: root) }
        let linkTarget = try manager.destinationOfSymbolicLink(atPath: childLink.path)
        let outsideContents = try manager.contentsOfDirectory(atPath: outside.path)
        precondition(linkTarget == outside.path && outsideContents.isEmpty)
        let dangling = root.appendingPathComponent("dangling-child")
        try manager.createSymbolicLink(at: dangling, withDestinationURL: missing)
        expectFailure { try ProjectDirectory.createProject(named: "dangling-child", root: root) }
        precondition(!manager.fileExists(atPath: missing.path))

        let rootLink = fixture.appendingPathComponent("Chosen Root")
        try manager.createSymbolicLink(at: rootLink, withDestinationURL: root)
        try ProjectDirectory.setRoot(rootLink, to: defaults)
        precondition(ProjectDirectory.root(from: defaults) == canonicalRoot)
        let linkedProject = try ProjectDirectory.createProject(named: "Through root link", root: rootLink)
        precondition(linkedProject == canonicalRoot.appendingPathComponent("Through root link", isDirectory: true))

        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do { _ = try ProjectDirectory.createProject(named: "Concurrent", root: root); return true }
                    catch { return false }
                }
            }
            var count = 0
            for await success in group where success { count += 1 }
            return count
        }
        precondition(successes == 1, "Concurrent creation must have exactly one winner")
        let concurrentContents = try manager.contentsOfDirectory(atPath: root.appendingPathComponent("Concurrent").path)
        precondition(concurrentContents.isEmpty)
        print("PASS project root persistence, exact names, exclusive creation, traversal rejection and symlink containment")
    }

    private static func expectFailure(containing text: String? = nil, _ operation: () throws -> Any) {
        do { _ = try operation(); preconditionFailure("Expected project directory failure") }
        catch { if let text { precondition(error.localizedDescription.contains(text), error.localizedDescription) } }
    }
}
