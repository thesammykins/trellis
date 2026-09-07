import Foundation
import Combine
import CryptoKit

struct WorkspaceAppearance: Codable, Equatable {
    enum TabDetail: String, Codable, CaseIterable, Identifiable {
        case folder, branch, diff, host, harness, configuredModel
        var id: String { rawValue }
        var title: String { self == .configuredModel ? "Configured model" : rawValue.capitalized }
    }
    enum Density: String, Codable, CaseIterable { case compact, comfortable }
    enum InspectorSide: String, Codable, CaseIterable { case left, right }
    enum SidebarSection: String, Codable, CaseIterable, Identifiable {
        case projects, sessions, knowledge
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }
    var horizontalDetails: [TabDetail] = [.harness, .branch]
    var verticalDetails: [TabDetail] = [.folder, .branch, .harness]
    var density: Density = .comfortable
    var verticalTabWidth: Double = 220
    var inspectorSide: InspectorSide = .right
    var sidebarSections: [SidebarSection] = [.projects, .sessions, .knowledge]

    func validated() throws -> Self {
        guard verticalTabWidth.isFinite, (160...360).contains(verticalTabWidth),
              Set(horizontalDetails).count == horizontalDetails.count,
              Set(verticalDetails).count == verticalDetails.count,
              Set(sidebarSections).count == sidebarSections.count else {
            throw AppearanceFailure("Layout contains duplicate details or a vertical tab width outside 160–360 points.")
        }
        return self
    }
}

struct AppearanceFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
final class WorkspaceAppearanceStore: ObservableObject {
    struct Preset: Codable, Equatable, Identifiable {
        var name: String
        var preferences: WorkspaceAppearance
        var id: String { name }
    }
    private struct Storage: Codable {
        var version = 1
        var defaults = WorkspaceAppearance()
        var projects: [String: WorkspaceAppearance] = [:]
        var presets: [Preset] = []
        func validated() throws -> Self {
            guard version == 1, projects.count <= 256, presets.count <= 64,
                  Set(presets.map(\.name)).count == presets.count,
                  projects.keys.allSatisfy({ $0.count == 64 && $0.allSatisfy { $0.isHexDigit } }) else {
                throw AppearanceFailure("Unsupported or invalid layout settings.")
            }
            _ = try defaults.validated()
            for value in projects.values { _ = try value.validated() }
            for preset in presets { try WorkspaceAppearanceStore.validateName(preset.name); _ = try preset.preferences.validated() }
            return self
        }
    }
    private struct PortablePreset: Codable {
        let version: Int
        let preferences: WorkspaceAppearance
    }
    @Published private(set) var preferences = WorkspaceAppearance()
    @Published private(set) var hasProjectOverride = false
    @Published private(set) var savedPresets: [Preset] = []
    @Published private(set) var error: String?
    private var projectKey: String?
    private let file: URL
    private var observer: NSObjectProtocol?
    private static let changed = Notification.Name("TrellisWorkspaceAppearanceChanged")

    init(project: URL?, file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppStorageLocation.directoryName).appendingPathComponent("appearance.json")
        switchProject(project)
        observer = NotificationCenter.default.addObserver(forName: Self.changed, object: nil, queue: .main) { [weak self] notification in
            let changedFile = notification.object as? URL
            MainActor.assumeIsolated {
                guard let self, changedFile == self.file else { return }
                self.reload()
            }
        }
    }
    isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func switchProject(_ project: URL?) {
        projectKey = project.map { SHA256.hash(data: Data($0.resolvingSymlinksInPath().path.utf8)).map { String(format: "%02x", $0) }.joined() }
        reload()
    }
    private func read() throws -> Storage {
        guard FileManager.default.fileExists(atPath: file.path) else { return Storage() }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576 else {
            throw AppearanceFailure("Layout settings must be a regular file under 1 MiB.")
        }
        return try JSONDecoder().decode(Storage.self, from: Data(contentsOf: file)).validated()
    }
    private func reload() {
        do {
            let storage = try read()
            let override = projectKey.flatMap { storage.projects[$0] }
            preferences = override ?? storage.defaults
            hasProjectOverride = override != nil
            savedPresets = storage.presets
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func mutate(_ change: (inout Storage) throws -> Void) throws {
        do {
            var storage = try read()
            try change(&storage)
            _ = try storage.validated()
            let data = try JSONEncoder().encode(storage)
            guard data.count <= 1_048_576 else { throw AppearanceFailure("Layout settings exceed 1 MiB.") }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            NotificationCenter.default.post(name: Self.changed, object: file)
        } catch { self.error = error.localizedDescription; throw error }
    }
    func update(_ value: WorkspaceAppearance) throws {
        _ = try value.validated()
        try mutate { storage in
            if let projectKey, storage.projects[projectKey] != nil { storage.projects[projectKey] = value }
            else { storage.defaults = value }
        }
    }
    func setProjectOverride(_ enabled: Bool) throws {
        guard let projectKey else { throw AppearanceFailure("Select a project before creating an override.") }
        try mutate { storage in
            if enabled { storage.projects[projectKey] = storage.projects[projectKey] ?? storage.defaults }
            else { storage.projects.removeValue(forKey: projectKey) }
        }
    }
    func reset() throws { try update(WorkspaceAppearance()) }
    func savePreset(named name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.validateName(name)
        try mutate { storage in
            storage.presets.removeAll { $0.name == name }
            storage.presets.append(Preset(name: name, preferences: preferences))
        }
    }
    nonisolated private static func validateName(_ name: String) throws {
        guard !name.isEmpty, name.utf8.count <= 80, !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw AppearanceFailure("Give the preset a name of 1–80 bytes without control characters.")
        }
    }
    func exportPreset() throws -> Data {
        try JSONEncoder().encode(PortablePreset(version: 1, preferences: preferences.validated()))
    }
    func importPreset(_ data: Data) throws {
        guard data.count <= 16_384 else { throw AppearanceFailure("A layout preset must be under 16 KiB.") }
        let preset = try JSONDecoder().decode(PortablePreset.self, from: data)
        guard preset.version == 1 else { throw AppearanceFailure("Unsupported layout preset version.") }
        try update(preset.preferences.validated())
    }
}
