import Foundation
import Darwin

struct WorkspaceArchive: Codable, Equatable {
    static let currentVersion = 2
    private static let maximumBytes = 1_048_576
    private static let maximumProjects = 256
    private static let maximumSessions = 1_024
    private static let maximumPathBytes = 4_096
    private static let maximumProfileBytes = 64
    private static let supportedProfiles: Set<String> = ["shell", "codex", "opencode", "pi", "claude", "gemini", "custom", "tmux", "remote"]

    struct Session: Codable, Equatable {
        let id: UUID
        let directory: String
        let profile: String
        var nickname: String? = nil
        var favourite: Bool? = nil
        var memoryEnabled: Bool? = nil
        var remote: RemoteProfile? = nil
        var launchSettings: SessionLaunchSettings? = nil
        var customHarness: CustomHarness? = nil
        var multiplexer: MultiplexerProfile? = nil
        var shellConfiguration: ShellConfiguration? = nil
    }

    struct WindowRecord: Codable, Equatable {
        let id: UUID
        let sessions: [Session]
        let selectedProject: String?
        let selectedSessionID: UUID?
        var layouts: [PaneLayout]? = nil
    }

    let version: Int
    let projects: [String]
    let windows: [WindowRecord]
    var sessions: [Session] { windows.flatMap(\.sessions) }
    var selectedProject: String? { windows.first?.selectedProject }
    var selectedSessionID: UUID? { windows.first?.selectedSessionID }

    init(projects: [URL], windows: [WindowRecord]) {
        version = Self.currentVersion
        self.projects = projects.map(\.standardizedFileURL.path)
        self.windows = windows
    }

    init(projects: [URL], sessions: [Session], selectedProject: URL?, selectedSessionID: UUID?) {
        self.init(projects: projects, windows: [.init(id: UUID(), sessions: sessions,
            selectedProject: selectedProject?.standardizedFileURL.path, selectedSessionID: selectedSessionID)])
    }

    private enum CodingKeys: String, CodingKey {
        case version, projects, windows, sessions, selectedProject, selectedSessionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try container.decode(Int.self, forKey: .version)
        guard storedVersion == 1 || storedVersion == Self.currentVersion else {
            throw Failure("Unsupported workspace data version \(storedVersion)")
        }
        version = Self.currentVersion
        projects = try container.decode([String].self, forKey: .projects)
        if storedVersion == 1 {
            // The former single window gets a repeatable identity across migration reads.
            windows = [WindowRecord(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                sessions: try container.decode([Session].self, forKey: .sessions),
                selectedProject: try container.decodeIfPresent(String.self, forKey: .selectedProject),
                selectedSessionID: try container.decodeIfPresent(UUID.self, forKey: .selectedSessionID))]
        } else {
            windows = try container.decode([WindowRecord].self, forKey: .windows)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(projects, forKey: .projects)
        try container.encode(windows, forKey: .windows)
    }

    func validated() throws -> WorkspaceArchive {
        guard version == Self.currentVersion else { throw Failure("Unsupported workspace data version \(version)") }
        guard projects.count <= Self.maximumProjects, windows.count <= Self.maximumProjects,
              sessions.count <= Self.maximumSessions else {
            throw Failure("Workspace data contains too many projects, windows or sessions")
        }
        let paths = projects + sessions.map(\.directory) + windows.compactMap(\.selectedProject)
        guard paths.allSatisfy(Self.isValidDirectoryPath) else {
            throw Failure("Workspace data contains an invalid project directory")
        }
        guard Set(projects).count == projects.count,
              Set(windows.map(\.id)).count == windows.count,
              Set(sessions.map(\.id)).count == sessions.count,
              sessions.allSatisfy({ Self.supportedProfiles.contains($0.profile) && $0.profile.utf8.count <= Self.maximumProfileBytes }),
              sessions.allSatisfy({ projects.contains($0.directory) }),
              sessions.allSatisfy({ ($0.profile == "remote") == ($0.remote != nil) }),
              windows.allSatisfy({ window in
                  (window.selectedProject.map(projects.contains) ?? true)
                    && (window.selectedSessionID.map { id in window.sessions.contains { $0.id == id } } ?? true)
                    && (window.selectedSessionID.flatMap { id in window.sessions.first { $0.id == id } }
                        .map { $0.directory == window.selectedProject } ?? true)
              }) else {
            throw Failure("Workspace data contains invalid or duplicate identifiers")
        }
        for session in sessions {
            if let nickname = session.nickname {
                guard nickname.utf8.count <= 128, !nickname.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw Failure("Invalid session nickname") }
            }
            try session.launchSettings?.validate()
            _ = try session.customHarness?.validated()
            _ = try session.shellConfiguration?.validated()
            guard (session.profile == "custom") == (session.customHarness != nil),
                  (session.profile == "tmux") == (session.multiplexer != nil) else {
                throw Failure("Invalid custom harness session")
            }
        }
        for window in windows {
            if let layouts = window.layouts {
                let leaves = try layouts.flatMap { try $0.validatedLeaves() }
                guard Set(leaves).count == leaves.count,
                      Set(leaves) == Set(window.sessions.map(\.id)),
                      layouts.allSatisfy({ layout in
                          Set(layout.leaves.compactMap { id in window.sessions.first { $0.id == id }?.directory }).count <= 1
                      }) else { throw Failure("Invalid terminal pane layout") }
            }
        }
        return self
    }

    var projectURLs: [URL] { projects.map { URL(fileURLWithPath: $0).standardizedFileURL } }

    static func load(from file: URL) throws -> WorkspaceArchive? {
        do {
            let attributes = try safeAttributes(at: file)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  ((attributes[.size] as? NSNumber)?.intValue ?? (maximumBytes + 1)) <= maximumBytes else {
                throw Failure("Workspace data is not a regular file under 1 MiB")
            }
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file, options: .mappedIfSafe)).validated()
        } catch {
            if isMissing(error) { return nil }
            throw Failure("Could not restore the workspace. The existing file was left unchanged: \(error.localizedDescription)")
        }
    }

    func save(to file: URL) throws {
        _ = try validated()
        let manager = FileManager.default
        let directory = file.deletingLastPathComponent()
        if manager.fileExists(atPath: directory.path) { _ = try Self.safeDirectoryAttributes(at: directory) }
        else { try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        }
        _ = try Self.safeDirectoryAttributes(at: directory)
        do { _ = try Self.safeAttributes(at: file) }
        catch {
            guard Self.isMissing(error) else { throw error }
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumBytes else { throw Failure("Workspace data exceeds 1 MiB") }
        try data.write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    static func defaultFile(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                            appropriateFor: nil, create: true)
            .appendingPathComponent(AppStorageLocation.directoryName, isDirectory: true)
            .appendingPathComponent("workspace.json")
    }

    private static func isValidDirectoryPath(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count <= maximumPathBytes && !path.utf8.contains(0) && path.hasPrefix("/")
            && URL(fileURLWithPath: path).standardizedFileURL.path == path
    }

    private static func safeAttributes(at url: URL) throws -> [FileAttributeKey: Any] {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid() else {
            throw Failure("Workspace storage must be owned by the current user and must not be a symbolic link")
        }
        return attributes
    }

    private static func safeDirectoryAttributes(at url: URL) throws -> [FileAttributeKey: Any] {
        let attributes = try safeAttributes(at: url)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw Failure("Workspace storage directory is not a directory")
        }
        return attributes
    }

    private static func isMissing(_ error: Error) -> Bool {
        let cocoa = error as NSError
        if cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSFileReadNoSuchFileError { return true }
        let underlying = cocoa.userInfo[NSUnderlyingErrorKey] as? NSError
        return underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(ENOENT)
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
