import Foundation

struct AgentModel: Identifiable, Sendable, Equatable {
    let id: String
    let displayName: String
    let reasoningEfforts: [String]
    let defaultReasoningEffort: String?
}

enum AgentModelCatalog {
    static func load(profile: LaunchProfile, directory: URL, executable: String? = nil,
                     launchArguments: [String] = []) async throws -> [AgentModel] {
        // Saved arguments may select a config or contain a subcommand. Do not compose a different invocation.
        guard launchArguments.isEmpty else { throw CatalogError.savedArguments }
        guard directory.isFileURL, directory.path.hasPrefix("/"),
              (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw CatalogError.invalidDirectory
        }
        let directory = directory.standardizedFileURL
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            switch profile {
            case .codex:
                return try loadCodex(executable: discoveryExecutable(executable, for: profile),
                                     directory: directory)
            case .opencode:
                return try loadOpenCode(executable: discoveryExecutable(executable, for: profile),
                                        directory: directory)
            default:
                throw CatalogError.unsupported(profile.title)
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func discoveryExecutable(_ selected: String?, for profile: LaunchProfile) throws -> String {
        guard let selected else { return try profile.executable(searchPath: AgentInstallation.searchPath) }
        let url = URL(fileURLWithPath: selected)
        guard selected.hasPrefix("/"), selected.utf8.count <= 4_096, !selected.utf8.contains(0),
              url.standardizedFileURL.path == selected,
              (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              FileManager.default.isExecutableFile(atPath: selected) else {
            throw CatalogError.commandFailed("The selected agent executable is unavailable. Update it in Manage Agents.")
        }
        return selected
    }

    static func parseCodexResponse(_ data: Data) throws -> (models: [AgentModel], nextCursor: String?) {
        let object = try object(data)
        guard let result = object["result"] as? [String: Any],
              let entries = result["data"] as? [[String: Any]] else {
            if object["error"] != nil {
                throw CatalogError.commandFailed("app-server rejected model discovery.")
            }
            throw CatalogError.malformedResponse
        }
        guard entries.count <= Limits.models else { throw CatalogError.outputLimit }
        let models = try entries.map { entry -> AgentModel in
            guard let id = valid(entry["model"] as? String),
                  let name = valid(entry["displayName"] as? String),
                  let options = entry["supportedReasoningEfforts"] as? [[String: Any]],
                  options.count <= Limits.reasoningOptions else {
                throw CatalogError.malformedResponse
            }
            let efforts = try options.map { option -> String in
                guard let effort = valid(option["reasoningEffort"] as? String) else {
                    throw CatalogError.malformedResponse
                }
                return effort
            }
            let defaultEffort = entry["defaultReasoningEffort"] as? String
            guard defaultEffort == nil || efforts.contains(defaultEffort!) else {
                throw CatalogError.malformedResponse
            }
            return AgentModel(id: id, displayName: name, reasoningEfforts: efforts,
                              defaultReasoningEffort: defaultEffort)
        }
        guard Set(models.map(\.id)).count == models.count else { throw CatalogError.malformedResponse }
        return (models, result["nextCursor"] as? String)
    }

    static func parseOpenCodeOutput(_ data: Data) throws -> [AgentModel] {
        guard data.count <= Limits.outputBytes else { throw CatalogError.outputLimit }
        let objects = try topLevelObjects(in: data)
        guard !objects.isEmpty, objects.count <= Limits.models else { throw CatalogError.malformedResponse }
        let models = try objects.map { data in
            let entry = try object(data)
            guard let modelID = valid(entry["id"] as? String),
                  let providerID = valid(entry["providerID"] as? String),
                  let name = valid(entry["name"] as? String) else {
                throw CatalogError.malformedResponse
            }
            return AgentModel(id: "\(providerID)/\(modelID)", displayName: name,
                              reasoningEfforts: [], defaultReasoningEffort: nil)
        }
        guard Set(models.map(\.id)).count == models.count else { throw CatalogError.malformedResponse }
        return models
    }

    private static func loadCodex(executable: String, directory: URL) throws -> [AgentModel] {
        let server = try CatalogProcess(executable: executable, arguments: ["app-server", "--stdio"],
                                        currentDirectory: directory)
        defer { server.stop() }
        try server.send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "trellis", "version": "1"]
        ]])
        _ = try server.response(id: 1)
        try server.send(["method": "initialized", "params": [:]])

        var models: [AgentModel] = []
        var cursor: String?
        var seen = Set<String>()
        for page in 0..<Limits.pages {
            var params: [String: Any] = ["limit": Limits.pageSize, "includeHidden": false]
            if let cursor { params["cursor"] = cursor }
            let id = page + 2
            try server.send(["id": id, "method": "model/list", "params": params])
            let parsed = try parseCodexResponse(server.response(id: id))
            models += parsed.models
            guard models.count <= Limits.models,
                  Set(models.map(\.id)).count == models.count else { throw CatalogError.malformedResponse }
            guard let next = parsed.nextCursor else { return models }
            guard seen.insert(next).inserted else { throw CatalogError.malformedResponse }
            cursor = next
        }
        throw CatalogError.pageLimit
    }

    private static func loadOpenCode(executable: String, directory: URL) throws -> [AgentModel] {
        try parseOpenCodeOutput(CatalogProcess.run(executable: executable,
                                                   arguments: ["models", "--verbose"],
                                                   currentDirectory: directory))
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= Limits.outputBytes,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogError.malformedResponse
        }
        return value
    }

    private static func valid(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 512,
              !value.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return nil }
        return value
    }

    private static func topLevelObjects(in data: Data) throws -> [Data] {
        var results: [Data] = []
        var start: Int?
        var depth = 0
        var quoted = false
        var escaped = false
        for (index, byte) in data.enumerated() {
            if let objectStart = start {
                if quoted {
                    if escaped { escaped = false }
                    else if byte == 0x5c { escaped = true }
                    else if byte == 0x22 { quoted = false }
                } else if byte == 0x22 { quoted = true }
                else if byte == 0x7b { depth += 1 }
                else if byte == 0x7d {
                    depth -= 1
                    if depth == 0 {
                        results.append(data.subdata(in: objectStart..<(index + 1)))
                        start = nil
                    }
                }
            } else if byte == 0x7b {
                start = index
                depth = 1
            }
        }
        guard start == nil else { throw CatalogError.malformedResponse }
        return results
    }

    private enum Limits {
        static let outputBytes = 4 * 1_024 * 1_024
        static let pages = 20
        static let pageSize = 100
        static let models = pages * pageSize
        static let reasoningOptions = 16
        static let timeout: TimeInterval = 10
    }

    enum CatalogError: LocalizedError, Equatable {
        case unsupported(String), invalidDirectory, commandFailed(String), malformedResponse, outputLimit, pageLimit, timedOut, savedArguments

        var errorDescription: String? {
            switch self {
            case .unsupported(let profile): "Model discovery is unavailable for \(profile)."
            case .savedArguments: "This launcher has saved arguments. Use the agent default or enter an exact model ID; discovery cannot safely reuse those arguments."
            case .invalidDirectory: "Model discovery requires an existing local project directory."
            case .commandFailed(let message): "Model discovery failed: \(message)"
            case .malformedResponse: "The agent returned an invalid model catalog."
            case .outputLimit: "The agent model catalog exceeded the output limit."
            case .pageLimit: "The agent model catalog exceeded the page limit."
            case .timedOut: "Model discovery timed out."
            }
        }
    }

    private final class CatalogProcess {
        private let process = Process()
        private let input = Pipe()
        private let outputURL: URL
        private let outputWriter: FileHandle
        private var consumedLines = 0
        private let deadline = ProcessInfo.processInfo.systemUptime + Limits.timeout

        init(executable: String, arguments: [String], currentDirectory: URL) throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-models-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            outputURL = directory.appendingPathComponent("output")
            guard FileManager.default.createFile(atPath: outputURL.path, contents: nil,
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw CatalogError.commandFailed("Could not create model output file.")
            }
            outputWriter = try FileHandle(forWritingTo: outputURL)
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = AgentInstallation.searchPath
            process.environment = environment
            process.standardInput = input
            process.standardOutput = outputWriter
            process.standardError = outputWriter
            try process.run()
        }

        deinit { stop() }

        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0a)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        func response(id: Int) throws -> Data {
            while true {
                try Task.checkCancellation()
                let data = try Self.readOutput(outputURL)
                var lines = data.split(separator: 0x0a, omittingEmptySubsequences: true)
                if data.last != 0x0a, !lines.isEmpty { lines.removeLast() }
                for line in lines.dropFirst(consumedLines) {
                    consumedLines += 1
                    guard let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                          (message["id"] as? Int) == id else { continue }
                    return Data(line)
                }
                if !process.isRunning {
                    throw CatalogError.commandFailed("app-server exited with status \(process.terminationStatus).")
                }
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw CatalogError.timedOut }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }

        func stop() {
            try? input.fileHandleForWriting.close()
            try? outputWriter.close()
            if process.isRunning {
                process.terminate()
                let stopDeadline = ProcessInfo.processInfo.systemUptime + 0.5
                while process.isRunning && ProcessInfo.processInfo.systemUptime < stopDeadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
            try? FileManager.default.removeItem(at: outputURL.deletingLastPathComponent())
        }

        static func run(executable: String, arguments: [String], currentDirectory: URL) throws -> Data {
            let command = try CatalogProcess(executable: executable, arguments: arguments,
                                             currentDirectory: currentDirectory)
            defer { command.stop() }
            while command.process.isRunning {
                try Task.checkCancellation()
                let size = (try? command.outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= Limits.outputBytes else { throw CatalogError.outputLimit }
                guard ProcessInfo.processInfo.systemUptime < command.deadline else { throw CatalogError.timedOut }
                Thread.sleep(forTimeInterval: 0.02)
            }
            command.process.waitUntilExit()
            let data = try readOutput(command.outputURL)
            guard command.process.terminationStatus == 0 else {
                throw CatalogError.commandFailed("agent exited with status \(command.process.terminationStatus).")
            }
            return data
        }

        private static func readOutput(_ url: URL) throws -> Data {
            let reader = try FileHandle(forReadingFrom: url)
            defer { try? reader.close() }
            let data = try reader.read(upToCount: Limits.outputBytes + 1) ?? Data()
            guard data.count <= Limits.outputBytes else { throw CatalogError.outputLimit }
            return data
        }
    }
}
