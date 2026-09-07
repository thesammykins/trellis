import Foundation

@main
enum AgentTeamCheck {
    @MainActor
    static func main() throws {
        let original = try AgentTeamConfiguration().validated()
        precondition(original.profiles.map(\.handle) == ["explore", "coding", "writing", "review"])
        precondition(original.profiles.allSatisfy { $0.endpoint.isEmpty && $0.model.isEmpty })
        let inherited = DirectModelConfiguration(baseURL: "https://gateway.example/v1", model: "chosen-model",
            api: .chatCompletions, maxOutputTokens: 1_024, reasoningEffort: "high")
        let inheritedRole = original.profiles[0].configuration(using: inherited)
        precondition(inheritedRole.baseURL == inherited.baseURL && inheritedRole.model == inherited.model)
        precondition(inheritedRole.api == .chatCompletions && inheritedRole.reasoningEffort == nil)
        var routed = original
        routed.profiles[0].endpoint = "https://role.example/v1"
        routed.profiles[0].model = "advertised-role-model"
        routed.profiles[0].api = .responses
        routed.profiles[0].reasoningEffort = "low"
        routed.profiles[0].maxOutputTokens = 1_536
        let resolved = try routed.validated().profiles[0].configuration(using: inherited)
        precondition(resolved.baseURL == "https://role.example/v1" && resolved.model == "advertised-role-model")
        precondition(resolved.api == .responses && resolved.reasoningEffort == "low" && resolved.maxOutputTokens == 1_536)

        for handle in ["", "Uppercase", "has space", "coding\n", String(repeating: "x", count: 33)] {
            try rejected(original) { $0.profiles[0].handle = handle }
        }
        try rejected(original) { $0.profiles[1].handle = $0.profiles[0].handle }
        try rejected(original) { $0.profiles[1].id = $0.profiles[0].id }
        try rejected(original) { $0.profiles[0].delegates = [UUID()] }
        try rejected(original) { $0.profiles[0].delegates = [$0.profiles[0].id] }
        try rejected(original) { $0.profiles[0].delegates = [$0.profiles[1].id, $0.profiles[1].id] }
        try rejected(original) { $0.profiles[0].escalation = UUID() }
        try rejected(original) { $0.profiles[0].escalation = $0.profiles[0].id }
        try rejected(original) { $0.profiles[0].endpoint = "http://public.example/v1" }
        try rejected(original) { $0.profiles[0].endpoint = "https://user:password@example.com/v1" }
        try rejected(original) { $0.profiles[0].endpoint = "https://example.com/v1?token=example" }
        try rejected(original) { $0.profiles[0].instructions = "null\0text" }
        try rejected(original) { $0.profiles[0].instructions = String(repeating: "a", count: 16_385) }
        try rejected(original) { $0.profiles[0].reasoningEffort = "unsupported-effort" }
        try rejected(original) { $0.profiles[0].contextBytes = 8_191 }
        try rejected(original) { $0.profiles[0].toolOutputBytes = 16_385 }
        try rejected(original) { $0.profiles[0].maxOutputTokens = 127 }
        try rejected(original) { $0.profiles[0].maxModelTurns = 25 }
        try rejected(original) { $0.profiles[0].maxToolCalls = -1 }
        try rejected(original) { $0.maximumTasks = 25 }
        try rejected(original) { $0.maximumDepth = 0 }
        try rejected(original) { $0.maximumModelRequests = 101 }
        try rejected(original) { $0.version = 2 }
        try rejected(original) { value in
            value.profiles = (0..<25).map { number in
                var profile = AgentProfile()
                profile.handle = "role-\(number)"
                return profile
            }
        }

        let suiteName = "Trellis.AgentTeamCheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "nativeAgentTeam.v1"
        let store = AgentTeamStore(defaults: defaults)
        precondition(store.error == nil && store.configuration == original)
        try store.save(routed)
        let reopened = AgentTeamStore(defaults: defaults)
        precondition(reopened.error == nil && reopened.configuration == routed)
        let saved = defaults.data(forKey: key)
        var invalid = routed
        invalid.maximumTasks = 0
        var didReject = false
        do { try store.save(invalid) } catch { didReject = true }
        precondition(didReject && defaults.data(forKey: key) == saved && store.configuration == routed)

        for corrupted: Data in [Data("not-json".utf8), Data(repeating: 0x20, count: 512 * 1_024 + 1)] {
            defaults.set(corrupted, forKey: key)
            let corrupt = AgentTeamStore(defaults: defaults)
            precondition(corrupt.error != nil && corrupt.configuration.profiles.isEmpty)
            precondition(defaults.data(forKey: key) == corrupted)
        }
        defaults.set("wrong stored type", forKey: key)
        let wrongType = AgentTeamStore(defaults: defaults)
        precondition(wrongType.error != nil && wrongType.configuration.profiles.isEmpty)
        precondition(defaults.string(forKey: key) == "wrong stored type")
        try wrongType.save(original)
        precondition(wrongType.error == nil && AgentTeamStore(defaults: defaults).configuration == original)
        print("PASS agent team: inherited/custom routes, handle and route validation, budgets, save round-trip, rejected-save preservation, corrupt settings and explicit recovery")
    }

    private static func rejected(_ original: AgentTeamConfiguration, change: (inout AgentTeamConfiguration) -> Void) throws {
        var invalid = original
        change(&invalid)
        var didReject = false
        do { _ = try invalid.validated() } catch { didReject = true }
        precondition(didReject, "Invalid team configuration was accepted")
    }
}
