import Combine
import Foundation

private let sessionOrganizationMaximumBytes = 65_536
private let sessionOrganizationMaximumCategories = 32
private let sessionOrganizationMaximumAssignments = 1_024
private let sessionOrganizationMaximumNameBytes = 64

struct SessionCategory: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
}

enum SessionSort: String, CaseIterable, Codable, Identifiable {
    case manual, title, harness, directory

    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: "Manual"
        case .title: "Title"
        case .harness: "Harness"
        case .directory: "Directory"
        }
    }
}

@MainActor
final class SessionOrganization: ObservableObject {
    @Published private(set) var categories: [SessionCategory] = []
    @Published private(set) var assignments: [UUID: UUID] = [:]
    @Published private(set) var sort: SessionSort = .manual
    @Published private(set) var readError: String?

    private let file: URL?

    init(workspaceID: UUID) {
        do { file = try Self.file(for: workspaceID) }
        catch { file = nil; readError = error.localizedDescription }
        load()
    }

    // Fixture checks can isolate storage from the user's Application Support directory.
    init(workspaceID: UUID, storageFile: URL) {
        file = storageFile
        load()
    }

    func category(for sessionID: UUID) -> UUID? { assignments[sessionID] }

    @discardableResult
    func copySessions(_ ids: [UUID], from source: SessionOrganization) -> Bool {
        let oldCategories = categories, oldAssignments = assignments
        for id in ids {
            guard let categoryID = source.assignments[id],
                  let category = source.categories.first(where: { $0.id == categoryID }) else {
                assignments.removeValue(forKey: id)
                continue
            }
            let matching = categories.first { $0.name.localizedCaseInsensitiveCompare(category.name) == .orderedSame }
            if let matching { assignments[id] = matching.id }
            else {
                let imported = SessionCategory(id: UUID(), name: category.name)
                categories.append(imported)
                assignments[id] = imported.id
            }
        }
        guard save() else { categories = oldCategories; assignments = oldAssignments; return false }
        return true
    }

    @discardableResult
    func createCategory(_ rawName: String) -> UUID? {
        guard let name = validatedName(rawName), !categories.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            readError = "Category names must be unique, under 64 bytes, and contain no control characters."
            return nil
        }
        let category = SessionCategory(id: UUID(), name: name)
        categories.append(category)
        guard save() else { categories.removeLast(); return nil }
        return category.id
    }

    @discardableResult
    func renameCategory(_ id: UUID, to rawName: String) -> Bool {
        guard let index = categories.firstIndex(where: { $0.id == id }), let name = validatedName(rawName),
              !categories.enumerated().contains(where: { $0.offset != index && $0.element.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            readError = "Category names must be unique, under 64 bytes, and contain no control characters."
            return false
        }
        let previous = categories[index].name
        categories[index].name = name
        guard save() else { categories[index].name = previous; return false }
        return true
    }

    @discardableResult
    func removeCategory(_ id: UUID) -> Bool {
        guard categories.contains(where: { $0.id == id }) else { return false }
        let previousCategories = categories
        let previousAssignments = assignments
        categories.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
        guard save() else { categories = previousCategories; assignments = previousAssignments; return false }
        return true
    }

    @discardableResult
    func assign(_ sessionID: UUID, to categoryID: UUID?) -> Bool {
        let previous = assignments[sessionID]
        if let categoryID {
            guard categories.contains(where: { $0.id == categoryID }) else {
                readError = "That category is no longer available."
                return false
            }
            assignments[sessionID] = categoryID
        } else {
            assignments.removeValue(forKey: sessionID)
        }
        guard save() else { assignments[sessionID] = previous; return false }
        return true
    }

    @discardableResult
    func setSort(_ value: SessionSort) -> Bool {
        let previous = sort
        sort = value
        guard save() else { sort = previous; return false }
        return true
    }

    private func load() {
        guard let file else { return }
        do {
            guard FileManager.default.fileExists(atPath: file.path) else { return }
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            guard data.count <= sessionOrganizationMaximumBytes else { throw Failure("Session organization data exceeds 64 KiB.") }
            let stored = try JSONDecoder().decode(Stored.self, from: data)
            try stored.validated()
            categories = stored.categories
            assignments = stored.assignments
            sort = stored.sort
        } catch {
            readError = "Could not load session organization: \(error.localizedDescription)"
        }
    }

    private func save() -> Bool {
        guard let file else { return false }
        do {
            let stored = Stored(categories: categories, assignments: assignments, sort: sort)
            try stored.validated()
            let data = try JSONEncoder().encode(stored)
            guard data.count <= sessionOrganizationMaximumBytes else { throw Failure("Session organization data exceeds 64 KiB.") }
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            readError = nil
            return true
        } catch {
            readError = "Could not save session organization: \(error.localizedDescription)"
            return false
        }
    }

    private func validatedName(_ rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= sessionOrganizationMaximumNameBytes,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return name
    }

    private static func file(for workspaceID: UUID) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
            .appendingPathComponent(AppStorageLocation.directoryName, isDirectory: true)
            .appendingPathComponent("SessionOrganization", isDirectory: true)
        return support.appendingPathComponent(workspaceID.uuidString.lowercased()).appendingPathExtension("json")
    }

    private struct Stored: Codable {
        let categories: [SessionCategory]
        let assignments: [UUID: UUID]
        let sort: SessionSort

        func validated() throws {
            guard categories.count <= sessionOrganizationMaximumCategories,
                  assignments.count <= sessionOrganizationMaximumAssignments,
                  Set(categories.map(\.id)).count == categories.count,
                  Set(categories.map { $0.name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) }).count == categories.count,
                  categories.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= sessionOrganizationMaximumNameBytes && !$0.name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }),
                  assignments.values.allSatisfy({ id in categories.contains(where: { $0.id == id }) }) else {
                throw Failure("Invalid session organization data.")
            }
        }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
