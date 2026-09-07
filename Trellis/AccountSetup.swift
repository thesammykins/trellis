import Foundation

enum CodexAccountStatus: Equatable {
    case checking
    case chatGPT
    case apiKey
    case signedOut
    case unavailable(String)
    case unknown

    var label: String {
        switch self {
        case .checking: "Checking…"
        case .chatGPT: "Signed in with ChatGPT"
        case .apiKey: "Signed in with an API key"
        case .signedOut: "Sign-in required"
        case .unavailable(let reason): reason
        case .unknown: "Codex returned an unrecognised account status"
        }
    }

    static func classify(_ output: String) -> CodexAccountStatus {
        let status = output.lowercased()
        if status.contains("chatgpt") { return .chatGPT }
        if status.contains("api key") || status.contains("api-key") { return .apiKey }
        if status.contains("not logged in") || status.contains("login required") { return .signedOut }
        return .unknown
    }

    static func refresh() async -> CodexAccountStatus {
        await Task.detached(priority: .utility) {
            do {
                let executable = try LaunchProfile.codex.executable(searchPath: AgentInstallation.searchPath)
                return classify(try AgentInstallation.probe(executable: executable,
                                                            arguments: ["login", "status"],
                                                            acceptedExitStatuses: [0, 1]))
            } catch {
                return .unavailable("Codex account status is unavailable")
            }
        }.value
    }
}
