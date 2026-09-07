import Foundation

typealias NativeAgentCredentialResolver = @MainActor @Sendable (String) throws -> String

@MainActor
struct NativeAgentDelegation: Identifiable {
    let id: UUID
    let profile: AgentProfile
    let configuration: DirectModelConfiguration
    let kind: NativeAgentDelegationKind
    let task: String
    let child: NativeAgentRuntime
}

/// One conversation owns the captured routes and the budget shared by every descendant.
@MainActor
final class NativeAgentTeamSession {
    let team: AgentTeamConfiguration
    let connection: DirectModelConfiguration
    private var keys: [String: String]
    private let credentialResolver: NativeAgentCredentialResolver?
    private(set) var tasks = 0
    private(set) var requests = 0

    init(team: AgentTeamConfiguration, connection: DirectModelConfiguration, apiKey: String,
         credentialResolver: NativeAgentCredentialResolver?) throws {
        self.team = try team.validated()
        self.connection = connection
        keys = [Self.endpointKey(connection.baseURL): apiKey]
        self.credentialResolver = credentialResolver
    }

    static func endpointKey(_ value: String) -> String {
        guard var url = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return value }
        url.scheme = url.scheme?.lowercased(); url.host = url.host?.lowercased()
        if (url.scheme == "https" && url.port == 443) || (url.scheme == "http" && url.port == 80) { url.port = nil }
        while url.path.hasSuffix("/") { url.path.removeLast() }
        return url.string ?? value
    }

    func key(for configuration: DirectModelConfiguration) throws -> String {
        let endpoint = Self.endpointKey(configuration.baseURL)
        if keys[endpoint] == nil { keys[endpoint] = try credentialResolver?(configuration.baseURL) ?? "" }
        guard let key = keys[endpoint], !key.isEmpty else {
            throw AgentTeamError.invalid("The selected agent's endpoint has no captured API key. Configure it before starting a new conversation.")
        }
        _ = try DirectModelClient.makeRequest(configuration: configuration, apiKey: key, body: ["model": configuration.model])
        return key
    }

    func reserveTask(depth: Int) throws {
        guard depth <= team.maximumDepth, tasks < team.maximumTasks else {
            throw AgentTeamError.invalid("This conversation reached its agent task or nesting limit.")
        }
        tasks += 1
    }

    func reserveRequest() throws {
        guard requests < team.maximumModelRequests else {
            throw AgentTeamError.invalid("The agent team reached this conversation's shared model-request limit.")
        }
        requests += 1
    }
}
