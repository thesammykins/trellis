import Darwin
import Foundation

struct CustomHarness: Identifiable, Codable, Equatable, Sendable {
    static let maximumArguments = 128
    static let maximumNameBytes = 128
    static let maximumPathBytes = 4_096
    static let maximumArgumentBytes = 4_096

    let id: UUID
    let name: String
    let executable: String
    let arguments: [String]
    let integration: String?

    init(id: UUID = UUID(), name: String, executable: String, arguments: [String], integration: String? = nil) throws {
        self.id = id
        self.name = name
        self.executable = executable
        self.arguments = arguments
        self.integration = integration
        try validate()
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            executable: values.decode(String.self, forKey: .executable),
            arguments: values.decode([String].self, forKey: .arguments),
            integration: values.decodeIfPresent(String.self, forKey: .integration)
        )
    }

    func validated() throws -> CustomHarness {
        try validate()
        return self
    }

    private func validate() throws {
        if let integration, !["codex", "opencode", "pi", "claude", "gemini"].contains(integration) {
            throw Failure("Choose a supported native integration or leave the harness integration unset.")
        }
        guard !name.isEmpty, name.utf8.count <= Self.maximumNameBytes,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw Failure("Harness name must be 1–128 bytes with no control characters.")
        }
        guard executable.hasPrefix("/"), executable.utf8.count <= Self.maximumPathBytes,
              !executable.utf8.contains(0),
              URL(fileURLWithPath: executable).standardizedFileURL.path == executable else {
            throw Failure("Executable must be a normalized absolute path under 4096 bytes.")
        }
        guard arguments.count <= Self.maximumArguments,
              arguments.allSatisfy({ $0.utf8.count <= Self.maximumArgumentBytes && !$0.utf8.contains(0) }) else {
            throw Failure("A harness may have at most 128 arguments, each under 4096 bytes with no NUL character.")
        }
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

struct CustomHarnessStore: Sendable {
    static let currentVersion = 1
    static let didChange = Notification.Name("TrellisHarnessesDidChange")
    private static let maximumProfiles = 128
    private static let maximumBytes = 1_048_576

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func appManaged() throws -> CustomHarnessStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(AppStorageLocation.directoryName, isDirectory: true)
        return CustomHarnessStore(fileURL: directory.appendingPathComponent("custom-harnesses.json"))
    }

    func load() throws -> [CustomHarness] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        try validateDirectory(fileURL.deletingLastPathComponent())
        let data = try readBounded(fileURL)
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == Self.currentVersion else {
            throw CustomHarness.Failure("Unsupported custom harness data version \(archive.version).")
        }
        return try validated(archive.profiles)
    }

    func save(_ profiles: [CustomHarness]) throws {
        let profiles = try validated(profiles)
        let data = try JSONEncoder.formatted.encode(Archive(version: Self.currentVersion, profiles: profiles))
        guard data.count <= Self.maximumBytes else {
            throw CustomHarness.Failure("Custom harness data exceeds 1 MiB.")
        }
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try validateDirectory(directory)
        let directoryAttributes = try manager.attributesOfItem(atPath: directory.path)
        guard directoryAttributes[.type] as? FileAttributeType == .typeDirectory,
              (directoryAttributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid() else {
            throw CustomHarness.Failure("Custom harness storage directory must be owned by the current user.")
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try rejectSymlink(fileURL)
        try data.write(to: fileURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func exportData(_ profile: CustomHarness) throws -> Data {
        _ = try profile.validated()
        return try JSONEncoder.formatted.encode(Export(version: Self.currentVersion, profile: profile))
    }

    func importPreview(from data: Data) throws -> CustomHarness {
        guard data.count <= Self.maximumBytes else {
            throw CustomHarness.Failure("Imported harness exceeds 1 MiB.")
        }
        let exported = try JSONDecoder().decode(Export.self, from: data)
        guard exported.version == Self.currentVersion else {
            throw CustomHarness.Failure("Unsupported custom harness export version \(exported.version).")
        }
        return try exported.profile.validated()
    }

    private func validated(_ profiles: [CustomHarness]) throws -> [CustomHarness] {
        guard profiles.count <= Self.maximumProfiles,
              Set(profiles.map(\.id)).count == profiles.count else {
            throw CustomHarness.Failure("Custom harness data contains too many profiles or duplicate identifiers.")
        }
        for profile in profiles { _ = try profile.validated() }
        return profiles
    }

    private func validateDirectory(_ directory: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid() else {
            throw CustomHarness.Failure("Custom harness directory must be a current-user directory, not a symbolic link.")
        }
    }

    private func readBounded(_ url: URL) throws -> Data {
        try rejectSymlink(url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
              (attributes[.size] as? NSNumber)?.intValue ?? (Self.maximumBytes + 1) <= Self.maximumBytes else {
            throw CustomHarness.Failure("Custom harness storage must be a current-user regular file under 1 MiB.")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw CustomHarness.Failure("Custom harness storage exceeds 1 MiB.") }
        return data
    }

    private func rejectSymlink(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
            throw CustomHarness.Failure("Custom harness storage must not be a symbolic link.")
        }
    }

    private struct Archive: Codable {
        let version: Int
        let profiles: [CustomHarness]
    }

    private struct Export: Codable {
        let version: Int
        let profile: CustomHarness
    }
}

private extension JSONEncoder {
    static var formatted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
