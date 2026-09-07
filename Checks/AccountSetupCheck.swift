import Foundation

@main enum AccountSetupCheck {
    static func main() throws {
        precondition(CodexAccountStatus.classify("Logged in using ChatGPT") == .chatGPT)
        precondition(CodexAccountStatus.classify("Logged in using an API key") == .apiKey)
        precondition(CodexAccountStatus.classify("token=secret") == .unknown)
        precondition(!CodexAccountStatus.classify("token=secret").label.contains("secret"))

        precondition(SettingsPage.agent.matches("API key"))
        precondition(SettingsPage.terminal.matches("  FONT\nsize "))
        precondition(SettingsPage.workspace.matches("sidebar"))
        precondition(SettingsPage.accounts.matches("ChatGPT"))
        precondition(SettingsPage.allCases.allSatisfy { $0.matches(" ") })
        precondition(!SettingsPage.agent.matches("shell arguments"))
        precondition(!SettingsPage.allCases.contains { $0.matches("no-such-setting") })

        let missingKey = try EndpointKey.isSaved(endpoint: "https://fixture-\(UUID()).invalid/v1")
        precondition(!missingKey)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-account-check-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = directory.appendingPathComponent("codex-status")
        try Data("#!/bin/sh\nprintf 'Not logged in\\n'\nexit 1\n".utf8).write(to: fixture)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        let output = try AgentInstallation.probe(executable: fixture.path, arguments: [],
                                                 acceptedExitStatuses: [0, 1])
        precondition(CodexAccountStatus.classify(output) == .signedOut)
        print("PASS Codex status labels, Settings search, and absent-key status")
    }
}
