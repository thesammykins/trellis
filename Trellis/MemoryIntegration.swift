import Foundation
import CryptoKit

struct MemoryIntegration {
    let root: URL
    let projectID: String

    init(project: URL) throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true).appendingPathComponent(AppStorageLocation.directoryName)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        root = support.appendingPathComponent("Projects")
        projectID = SHA256.hash(data: Data(project.resolvingSymlinksInPath().path.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    private static var tomlEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    func launch(profile: LaunchProfile) throws -> (arguments: [String], environment: [String: String]) {
        guard let helper = Bundle.main.path(forAuxiliaryExecutable: "MemoryBridge") else {
            throw IntegrationFailure("The memory bridge is missing from the app bundle.")
        }
        let args = ["--root", root.path, "--project-id", projectID]
        switch profile {
        case .codex:
            let quotedHelper = String(decoding: try Self.tomlEncoder.encode(helper), as: UTF8.self)
            let quotedArgs = String(decoding: try Self.tomlEncoder.encode(args), as: UTF8.self)
            return (["-c", "mcp_servers.trellis.command=" + quotedHelper,
                     "-c", "mcp_servers.trellis.args=" + quotedArgs], [:])
        case .opencode:
            let config: [String: Any] = ["mcp": ["trellis": ["type": "local", "command": [helper] + args, "enabled": true]]]
            return ([], ["OPENCODE_CONFIG_CONTENT": String(decoding: try JSONSerialization.data(withJSONObject: config), as: UTF8.self)])
        default: throw IntegrationFailure("Memory tools are currently available for Codex and OpenCode.")
        }
    }
}

private struct IntegrationFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
