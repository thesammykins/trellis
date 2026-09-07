import Combine
import Foundation

enum NativeAgentDelegationKind: String, Sendable { case delegate, escalate, assignment }

enum AgentToolAccess: String, Codable, CaseIterable, Sendable {
    case textOnly, projectRead, reviewedTools

    var title: String {
        switch self {
        case .textOnly: "Text only"
        case .projectRead: "Read project"
        case .reviewedTools: "Reviewed tools"
        }
    }
}

struct AgentProfile: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var handle = "new-agent"
    var name = "New Agent"
    var specialty = ""
    var instructions = ""
    var enabled = true
    var access = AgentToolAccess.projectRead
    // Empty endpoint/model inherit the conversation's connection/model respectively.
    var endpoint = ""
    var model = ""
    var api = DirectAPI.responses
    var reasoningEffort = ""
    var maxOutputTokens = 2_048
    var maxModelTurns = 6
    var maxToolCalls = 12
    var contextBytes = 32 * 1_024
    var toolOutputBytes = 8 * 1_024
    var delegates: [UUID] = []
    var escalation: UUID?

    func configuration(using inherited: DirectModelConfiguration) -> DirectModelConfiguration {
        .init(baseURL: endpoint.isEmpty ? inherited.baseURL : endpoint,
              model: model.isEmpty ? inherited.model : model,
              api: endpoint.isEmpty ? inherited.api : api,
              maxOutputTokens: maxOutputTokens,
              reasoningEffort: reasoningEffort.isEmpty ? nil : reasoningEffort)
    }

    static var templates: [AgentProfile] {
        let coding = UUID(uuidString: "AA6A2720-68AB-4644-B59E-14063A1F6B01")!
        let explore = UUID(uuidString: "AA6A2720-68AB-4644-B59E-14063A1F6B02")!
        let writing = UUID(uuidString: "AA6A2720-68AB-4644-B59E-14063A1F6B03")!
        let review = UUID(uuidString: "AA6A2720-68AB-4644-B59E-14063A1F6B04")!
        return [
            .init(id: explore, handle: "explore", name: "Explore", specialty: "Find code, facts and relevant context",
                  instructions: "Explore the scoped project efficiently. Search before reading. Return concrete file paths, key findings and uncertainty. Escalate implementation work to Coding.",
                  access: .projectRead, escalation: coding),
            .init(id: coding, handle: "coding", name: "Coding", specialty: "Implement and verify focused changes",
                  instructions: "Trace the relevant flow, make the smallest complete change and verify the behavior. Commands require review. Ask Review to independently check meaningful changes. Return changes, evidence and remaining risks.",
                  access: .reviewedTools, maxOutputTokens: 4_096, delegates: [explore, review]),
            .init(id: writing, handle: "writing", name: "Writing", specialty: "Draft and edit clear, useful prose",
                  instructions: "Write concise, natural prose for the stated audience. Preserve supplied facts and voice. Return the requested draft without inventing evidence.",
                  access: .textOnly, maxOutputTokens: 4_096),
            .init(id: review, handle: "review", name: "Review", specialty: "Validate changes and identify concrete issues",
                  instructions: "Independently inspect the requested evidence or changes. Report actionable issues with file locations and consequences. Distinguish inspected evidence from tests actually run. Do not claim success from another agent's summary alone.",
                  access: .projectRead)
        ]
    }
}

struct AgentTeamConfiguration: Codable, Equatable, Sendable {
    var version = 1
    var profiles = AgentProfile.templates
    var automaticDelegation = true
    var maximumTasks = 6
    var maximumDepth = 3
    var maximumModelRequests = 30

    func validated() throws -> Self {
        func validText(_ value: String, bytes: Int, empty: Bool = true) -> Bool {
            (empty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                && value.utf8.count <= bytes && !value.utf8.contains(0)
        }
        let ids = Set(profiles.map(\.id))
        guard version == 1, profiles.count <= 24, ids.count == profiles.count,
              Set(profiles.map(\.handle)).count == profiles.count,
              (1...24).contains(maximumTasks), (1...4).contains(maximumDepth),
              (1...100).contains(maximumModelRequests) else {
            throw AgentTeamError.invalid("Use unique agents and valid task, depth and request limits.")
        }
        for profile in profiles {
            guard profile.handle.range(of: "\\A[a-z][a-z0-9-]{0,31}\\z", options: .regularExpression) != nil,
                  validText(profile.name, bytes: 100, empty: false), validText(profile.specialty, bytes: 320),
                  validText(profile.instructions, bytes: 16 * 1_024),
                  validText(profile.model, bytes: 256), validText(profile.endpoint, bytes: 2_048),
                  profile.reasoningEffort.isEmpty || DirectModelConfiguration.reasoningEfforts.contains(profile.reasoningEffort),
                  (128...16_384).contains(profile.maxOutputTokens), (1...24).contains(profile.maxModelTurns),
                  (0...48).contains(profile.maxToolCalls), (8_192...65_536).contains(profile.contextBytes),
                  (1_024...16_384).contains(profile.toolOutputBytes),
                  Set(profile.delegates).count == profile.delegates.count,
                  profile.delegates.allSatisfy({ ids.contains($0) && $0 != profile.id }),
                  profile.escalation.map({ ids.contains($0) && $0 != profile.id }) ?? true else {
                throw AgentTeamError.invalid("Check \(profile.name)'s handle, text, route, budgets and delegation targets.")
            }
            if !profile.endpoint.isEmpty {
                _ = try DirectModelClient.endpoint(for: .init(baseURL: profile.endpoint,
                    model: profile.model.isEmpty ? "inherited" : profile.model, api: profile.api, maxOutputTokens: profile.maxOutputTokens))
            }
        }
        return self
    }
}

enum AgentTeamError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let message): message } }
}

@MainActor
final class AgentTeamStore: ObservableObject {
    static let shared = AgentTeamStore()
    @Published private(set) var configuration = AgentTeamConfiguration()
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private let key = "nativeAgentTeam.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let stored = defaults.object(forKey: key) else { return }
        do {
            guard let data = stored as? Data else { throw AgentTeamError.invalid("Agent settings have an invalid storage type.") }
            guard data.count <= 512 * 1_024 else { throw AgentTeamError.invalid("Agent settings exceed 512 KiB.") }
            configuration = try JSONDecoder().decode(AgentTeamConfiguration.self, from: data).validated()
        } catch { self.error = "Agent settings could not be loaded: \(error.localizedDescription)"; configuration.profiles = [] }
    }

    func save(_ value: AgentTeamConfiguration) throws {
        let validated = try value.validated()
        let data = try JSONEncoder().encode(validated)
        guard data.count <= 512 * 1_024 else { throw AgentTeamError.invalid("Agent settings exceed 512 KiB.") }
        defaults.set(data, forKey: key)
        configuration = validated
        error = nil
    }
}
