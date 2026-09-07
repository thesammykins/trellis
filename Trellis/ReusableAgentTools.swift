import Foundation

struct ReusableToolRecipe: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let name: String
    let description: String
    let executable: String
    let arguments: [String]
    let directory: String
    let enabled: Bool

    init(name: String, description: String, executable: String, arguments: [String], directory: String, enabled: Bool = true) {
        schemaVersion = 1
        self.name = name
        self.description = description
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.enabled = enabled
    }

    func validated() throws -> Self {
        guard schemaVersion == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 120, !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              description.utf8.count <= 4_096, !description.utf8.contains(0),
              !directory.isEmpty, !directory.hasPrefix("/"), directory.utf8.count <= 4_096,
              !directory.utf8.contains(0), !directory.split(separator: "/").contains("..") else {
            throw NativeAgentToolError.invalidArguments
        }
        try NativeAgentTools.validateCommand(executable: executable, arguments: arguments)
        return self
    }

    var reviewText: String {
        let encodedArguments = (try? JSONEncoder().encode(arguments)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        return "\(name)\n\(description)\nAvailability: \(enabled ? "Enabled" : "Disabled")\n\nExecutable: \(executable)\nArguments (exact JSON array): \(encodedArguments)\nFolder relative to scope: \(directory)"
    }

    func encoded() throws -> String {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    static func decode(_ body: String) throws -> Self {
        guard body.utf8.count <= MemoryStore.maximumBodyBytes,
              let object = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              Set(object.keys) == Set(["schemaVersion", "name", "description", "executable", "arguments", "directory", "enabled"]) else {
            throw NativeAgentToolError.invalidArguments
        }
        return try JSONDecoder().decode(Self.self, from: Data(body.utf8)).validated()
    }
}

struct ApprovedReusableTool: Identifiable, Equatable, Sendable {
    let id: UUID
    let revision: Int
    let hash: String
    let recipe: ReusableToolRecipe
}

actor ReusableAgentTools {
    nonisolated let directory: URL
    private let memory: MemoryStore

    init(root: URL, projectID: String, directory: URL) throws {
        self.directory = directory.resolvingSymlinksInPath().standardizedFileURL
        // Reuse journaled review storage without mixing executable recipes into ordinary project notes.
        memory = try MemoryStore(root: root, projectID: projectID + ":executable-tools-v1")
    }

    func approved() async throws -> [ApprovedReusableTool] {
        let pages = try await memory.pages()
        var tools: [ApprovedReusableTool] = []
        for page in pages { tools.append(try await approved(page.id)) }
        return tools
    }

    func approved(_ id: UUID) async throws -> ApprovedReusableTool {
        let page = try await memory.reviewedPage(id)
        guard page.kind == "how-to" else { throw NativeAgentToolError.invalidArguments }
        let recipe = try ReusableToolRecipe.decode(page.body)
        guard recipe.name == page.title else { throw NativeAgentToolError.invalidArguments }
        return .init(id: page.id, revision: page.revision, hash: page.hash, recipe: recipe)
    }

    func proposals() async throws -> [MemoryProposal] { try await memory.proposals() }

    func propose(_ recipe: ReusableToolRecipe, id: UUID? = nil, baseHash: String? = nil,
                 source: String) async throws -> MemoryProposal {
        _ = try recipe.validated()
        guard (id == nil) == (baseHash == nil) else { throw NativeAgentToolError.invalidArguments }
        if let id {
            let current = try await approved(id)
            guard current.hash == baseHash else { throw NativeAgentToolError.savedToolChanged }
        }
        return try await memory.propose(title: recipe.name, body: recipe.encoded(), kind: "how-to",
                                        pageID: id, source: source, expectedBaseHash: baseHash)
    }

    func approve(_ proposal: MemoryProposal) async throws {
        guard proposal.kind == "how-to", try ReusableToolRecipe.decode(proposal.body).name == proposal.title else {
            throw NativeAgentToolError.invalidArguments
        }
        try await memory.approve(proposal.id, expectedProposal: proposal)
    }

    func setEnabled(_ enabled: Bool, snapshot: ApprovedReusableTool) async throws {
        guard try await approved(snapshot.id) == snapshot else { throw NativeAgentToolError.savedToolChanged }
        let recipe = snapshot.recipe
        let replacement = ReusableToolRecipe(name: recipe.name, description: recipe.description,
            executable: recipe.executable, arguments: recipe.arguments, directory: recipe.directory, enabled: enabled)
        let proposal = try await propose(replacement, id: snapshot.id, baseHash: snapshot.hash, source: "user:Reusable Tools")
        try await approve(proposal)
    }

    func reject(_ id: UUID) async throws { try await memory.reject(id) }
}
