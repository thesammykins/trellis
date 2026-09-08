import Combine
import Foundation

struct RemoteLocation: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var hostAlias = ""
    var directory = ""
    var tmuxExecutable = "tmux"

    func validated() throws -> Self {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 128,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.union(.newlines).contains) else {
            throw RemoteLocationError.invalid("Use a location name under 129 bytes without control characters.")
        }
        _ = try RemoteProfile(hostAlias: hostAlias, directory: directory)
        _ = try RemoteProfile(hostAlias: hostAlias, directory: "/", sessionName: "trellis-00000000-0000-0000-0000-000000000000", tmuxExecutable: tmuxExecutable)
        return self
    }

    func profile(persistent: Bool) throws -> RemoteProfile {
        _ = try validated()
        if persistent {
            return try RemoteProfile(hostAlias: hostAlias, directory: directory,
                sessionName: "trellis-\(UUID().uuidString)", tmuxExecutable: tmuxExecutable)
        }
        return try RemoteProfile(hostAlias: hostAlias, directory: directory)
    }
}

enum RemoteLocationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}

/// Stores connection locations only. It never reads SSH configuration, keys or remote state.
@MainActor
final class RemoteLocationStore: ObservableObject {
    static let shared = RemoteLocationStore()
    static let defaultsKey = "sshLocations.v1"
    @Published private(set) var locations: [RemoteLocation] = []
    @Published private(set) var error: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let stored = defaults.object(forKey: Self.defaultsKey) else { return }
        do {
            guard let data = stored as? Data, data.count <= 256 * 1_024 else {
                throw RemoteLocationError.invalid("Saved SSH locations have an invalid format or exceed 256 KiB.")
            }
            let archive = try JSONDecoder().decode(Archive.self, from: data)
            guard archive.version == 1 else { throw RemoteLocationError.invalid("Unsupported SSH location version.") }
            locations = try Self.validate(archive.locations)
        } catch { self.error = "SSH locations could not be loaded: " + error.localizedDescription }
    }

    func save(_ location: RemoteLocation) throws {
        try persist(locations.filter { $0.id != location.id } + [location.validated()])
    }

    func remove(_ id: UUID) throws { try persist(locations.filter { $0.id != id }) }

    private func persist(_ values: [RemoteLocation]) throws {
        // A corrupt stored value must be recovered explicitly, never replaced by an incidental edit.
        guard error == nil else { throw RemoteLocationError.invalid(error!) }
        let values = try Self.validate(values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Archive(version: 1, locations: values))
        guard data.count <= 256 * 1_024 else { throw RemoteLocationError.invalid("Saved SSH locations exceed 256 KiB.") }
        defaults.set(data, forKey: Self.defaultsKey)
        locations = values
    }

    private static func validate(_ values: [RemoteLocation]) throws -> [RemoteLocation] {
        guard values.count <= 128, Set(values.map(\.id)).count == values.count else {
            throw RemoteLocationError.invalid("Use at most 128 SSH locations with unique identities.")
        }
        return try values.map { try $0.validated() }
    }

    private struct Archive: Codable { let version: Int; let locations: [RemoteLocation] }
}
