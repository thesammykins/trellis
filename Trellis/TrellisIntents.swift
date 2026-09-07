import AppIntents
import Foundation

extension Notification.Name {
    static let TrellisOpenRegisteredProject = Notification.Name("TrellisOpenRegisteredProject")
}

struct ProjectEntity: AppEntity, Identifiable {
    let id: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static let defaultQuery = ProjectEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: URL(fileURLWithPath: id).lastPathComponent))
    }
}

struct ProjectEntityQuery: EntityQuery {
    func entities(for identifiers: [ProjectEntity.ID]) async throws -> [ProjectEntity] {
        let requested = Set(identifiers)
        return try TrellisProjectRegistry.projects().filter { requested.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProjectEntity] {
        try TrellisProjectRegistry.projects()
    }
}

struct OpenProjectIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Project"
    static let description = IntentDescription("Open a registered Trellis project")
    static let openAppWhenRun = true

    @Parameter(title: "Project") var project: ProjectEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$project)")
    }

    func perform() async throws -> some IntentResult {
        try await TrellisProjectIntentHandoff.open(project, showMemory: false)
        return .result()
    }
}

struct ShowProjectMemoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Project Memory"
    static let description = IntentDescription("Open the memory view for a registered Trellis project")
    static let openAppWhenRun = true

    @Parameter(title: "Project") var project: ProjectEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show memory for \(\.$project)")
    }

    func perform() async throws -> some IntentResult {
        try await TrellisProjectIntentHandoff.open(project, showMemory: true)
        return .result()
    }
}

struct TrellisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenProjectIntent(),
            phrases: ["Open a project in \(.applicationName)"],
            shortTitle: "Open Project",
            systemImageName: "folder"
        )
        AppShortcut(
            intent: ShowProjectMemoryIntent(),
            phrases: ["Show project memory in \(.applicationName)"],
            shortTitle: "Project Memory",
            systemImageName: "book"
        )
    }
}

private enum TrellisProjectRegistry {
    static func projects() throws -> [ProjectEntity] {
        let file = try WorkspaceArchive.defaultFile()
        guard let archive = try WorkspaceArchive.load(from: file) else { return [] }
        return archive.projectURLs.map { ProjectEntity(id: $0.standardizedFileURL.path) }
    }

    static func project(id: String) throws -> ProjectEntity? {
        try projects().first { $0.id == id }
    }
}

private enum TrellisProjectIntentHandoff {
    static func open(_ project: ProjectEntity, showMemory: Bool) async throws {
        guard let registered = try TrellisProjectRegistry.project(id: project.id) else {
            throw TrellisIntentFailure.projectIsNoLongerRegistered
        }
        await MainActor.run {
            var userInfo: [AnyHashable: Any] = ["path": registered.id]
            if showMemory { userInfo["memory"] = true }
            NotificationCenter.default.post(name: .TrellisOpenRegisteredProject, object: nil, userInfo: userInfo)
        }
    }
}

private enum TrellisIntentFailure: LocalizedError {
    case projectIsNoLongerRegistered

    var errorDescription: String? {
        switch self {
        case .projectIsNoLongerRegistered:
            "That project is no longer registered in Trellis."
        }
    }
}
