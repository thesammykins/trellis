import Darwin
import Foundation

enum ProjectDirectory {
    static let defaultsKey = "projectRootDirectory"

    static func root(from defaults: UserDefaults = .standard) -> URL {
        if let path = defaults.string(forKey: defaultsKey), validPath(path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Development", isDirectory: true)
    }

    static func setRoot(_ url: URL, to defaults: UserDefaults = .standard) throws {
        let descriptor = try openRoot(url)
        defer { close(descriptor) }
        defaults.set(try directoryURL(descriptor).path, forKey: defaultsKey)
    }

    static func createProject(named name: String, root: URL) throws -> URL {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 255, name != ".", name != "..", !name.contains("/"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.union(.newlines).contains) else {
            throw Failure("Use one project name under 256 bytes, without slashes or control characters.")
        }
        let descriptor = try openRoot(root)
        defer { close(descriptor) }
        let parent = try directoryURL(descriptor)
        guard parent.appendingPathComponent(name).path.utf8.count < Int(PATH_MAX) else {
            throw Failure("The project path is too long. Choose a shorter name or projects folder.")
        }
        // Anchor creation to the chosen directory; an existing name, including a symlink, must fail.
        guard mkdirat(descriptor, name, S_IRWXU) == 0 else {
            let code = errno
            if code == EEXIST { throw Failure("A file or folder named \"\(name)\" already exists. Choose another name.") }
            throw Failure("Could not create the project folder: " + String(cString: strerror(code)))
        }
        let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard child >= 0 else { throw Failure("The new project folder changed during creation. Check the projects folder before retrying.") }
        defer { close(child) }
        let created = try directoryURL(child)
        guard try created.deletingLastPathComponent() == directoryURL(descriptor) else {
            throw Failure("The new project folder moved during creation. Check the projects folder before retrying.")
        }
        return created
    }

    private static func openRoot(_ url: URL) throws -> Int32 {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host?.lowercased() == "localhost",
              url.query == nil, url.fragment == nil, validPath(url.path) else {
            throw Failure("Choose an existing local folder for projects.")
        }
        // A user-selected root may be a symlink; subsequent operations use this opened directory.
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw Failure("The projects folder is unavailable. Choose an existing folder or create it in Finder first: " + String(cString: strerror(errno)))
        }
        return descriptor
    }

    private static func directoryURL(_ descriptor: Int32) throws -> URL {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &path) == 0,
              let value = String(validating: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self), validPath(value) else {
            throw Failure("The projects folder path could not be resolved. Choose the folder again.")
        }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    private static func validPath(_ path: String) -> Bool {
        path.hasPrefix("/") && path.utf8.count < Int(PATH_MAX)
            && !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.union(.newlines).contains)
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
