import Combine
import Foundation

enum ModelProviderPreset: String, CaseIterable, Identifiable {
    case openAI, gemini, deepSeek, openRouter, custom
    var id: String { rawValue }
    var name: String {
        switch self {
        case .openAI: "OpenAI API"
        case .gemini: "Google Gemini API"
        case .deepSeek: "DeepSeek API"
        case .openRouter: "OpenRouter"
        case .custom: "Custom compatible API"
        }
    }
    var endpoint: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .deepSeek: "https://api.deepseek.com"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .custom: ""
        }
    }
    var api: DirectAPI { self == .openAI ? .responses : .chatCompletions }
}

struct ModelConnection: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var endpoint: String
    var api: DirectAPI
    var model = ""
    var reasoning = ""

    func validated() throws -> Self {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 100, !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
              endpoint.utf8.count <= 2_048, model.utf8.count <= 256,
              !model.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
              reasoning.isEmpty || DirectModelClient.supportedReasoningEfforts(baseURL: endpoint).contains(reasoning) else {
            throw ModelConnectionError.invalid("Check the connection name, model and reasoning setting.")
        }
        _ = try DirectModelClient.endpoint(for: .init(baseURL: endpoint, model: model.isEmpty ? "discovery" : model,
            api: api, maxOutputTokens: 4_096))
        return self
    }
}

enum ModelConnectionError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}

@MainActor final class ModelConnectionStore: ObservableObject {
    static let shared = ModelConnectionStore()
    @Published private(set) var connections: [ModelConnection] = []
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private let key = "modelConnections.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let value = defaults.object(forKey: key) else { return }
        do {
            guard let data = value as? Data, data.count <= 128 * 1_024 else {
                throw ModelConnectionError.invalid("Saved connections have an invalid storage format.")
            }
            connections = try Self.validate(JSONDecoder().decode([ModelConnection].self, from: data))
        } catch { self.error = error.localizedDescription }
    }

    func save(_ connection: ModelConnection) throws {
        guard error == nil else { throw ModelConnectionError.invalid("Saved connections could not be loaded. Recover the stored data before replacing it.") }
        var values = connections
        if let index = values.firstIndex(where: { $0.id == connection.id }) { values[index] = connection }
        else { values.append(connection) }
        try persist(values)
    }

    func remove(_ id: UUID) throws {
        guard error == nil else { throw ModelConnectionError.invalid("Saved connections could not be loaded.") }
        try persist(connections.filter { $0.id != id })
    }

    private func persist(_ values: [ModelConnection]) throws {
        let valid = try Self.validate(values)
        let data = try JSONEncoder().encode(valid)
        guard data.count <= 128 * 1_024 else { throw ModelConnectionError.invalid("Saved connections exceed 128 KiB.") }
        defaults.set(data, forKey: key)
        connections = valid
    }

    private static func validate(_ values: [ModelConnection]) throws -> [ModelConnection] {
        guard values.count <= 32, Set(values.map(\.id)).count == values.count else {
            throw ModelConnectionError.invalid("Use at most 32 uniquely identified connections.")
        }
        return try values.map { try $0.validated() }
    }
}
