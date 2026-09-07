import Darwin
import Foundation

enum NativeAgentAppRead: Equatable, Sendable { case terminalContext, sessionInfo }
typealias NativeAgentAppReader = @MainActor @Sendable (NativeAgentAppRead) async throws -> String
typealias NativeAgentTerminalRunner = @MainActor @Sendable (String) throws -> Void

enum NativeToolInvocation: Equatable, Sendable {
    case listDirectory(path: String)
    case readFile(path: String)
    case findFiles(query: String, path: String)
    case runCommand(executable: String, arguments: [String], directory: String)
    case runInTerminal(command: String, target: String? = nil)
    case memorySearch(query: String)
    case memoryRead(id: UUID)
    case proposeRecipe(title: String, body: String)
    case readSkill(id: String, path: String = "SKILL.md")
    case listSavedTools
    case proposeSavedTool(recipe: ReusableToolRecipe, id: UUID?, baseHash: String?)
    case runSavedTool(id: UUID, hash: String, snapshot: ApprovedReusableTool? = nil)
    case readApp(NativeAgentAppRead)
    case delegateTask(agent: String, task: String, context: String, kind: NativeAgentDelegationKind, destination: String? = nil)

    var isScopedRead: Bool {
        switch self {
        case .listDirectory, .readFile, .findFiles, .memorySearch, .memoryRead, .readSkill, .listSavedTools: true
        default: false
        }
    }
}

struct NativeToolRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let callID: String
    let name: String
    let invocation: NativeToolInvocation
    let reason: String?

    init(id: UUID, callID: String, name: String, invocation: NativeToolInvocation, reason: String? = nil) {
        self.id = id; self.callID = callID; self.name = name; self.invocation = invocation; self.reason = reason
    }

    var reviewText: String {
        switch invocation {
        case let .listDirectory(path): "List directory: \(path)"
        case let .readFile(path): "Read file: \(path)"
        case let .findFiles(query, path): "Find files containing \"\(query)\" under: \(path)"
        case let .runCommand(executable, arguments, directory):
            "Run in \(directory):\nExecutable: \(executable)\nArguments: \(arguments)"
        case let .runInTerminal(command, target):
            command + "\n\nType and press Return in \(target ?? "an unprepared terminal")"
        case let .memorySearch(query): "Search approved project memory for: \(query)"
        case let .memoryRead(id): "Read approved project memory: \(id.uuidString.lowercased())"
        case let .proposeRecipe(title, body): "Stage recipe proposal for review:\nTitle: \(title)\n\n\(body)"
        case let .readSkill(id, path): "Read reviewed skill source: \(id)\nRelative file: \(path)"
        case .listSavedTools: "List approved reusable tools in this conversation scope."
        case let .proposeSavedTool(recipe, id, baseHash):
            "Stage a reusable tool for separate review; this does not execute or approve it.\n"
                + (id.map { "Update \($0.uuidString.lowercased()) from \(baseHash ?? "unknown")\n" } ?? "New tool\n")
                + recipe.reviewText
        case let .runSavedTool(id, hash, snapshot):
            (snapshot?.recipe.reviewText ?? "The saved tool has not been prepared for review.")
                + "\n\nVersion \(snapshot?.revision.description ?? "unknown")\nTool ID: \(id.uuidString.lowercased())\nReviewed hash: \(hash)"
        case .readApp(.terminalContext): "Read the originating terminal’s current viewport after approval. Output is reviewed separately before sharing."
        case .readApp(.sessionInfo): "Read structured identity and folder information for the originating terminal after approval."
        case let .delegateTask(agent, task, context, kind, destination):
            "\(kind.rawValue.capitalized) to @\(agent)\nDestination: \(destination ?? "not prepared")\n\nTask:\n\(task)\n\nContext to share:\n\(context.isEmpty ? "None" : context)"
        }
    }
}

struct NativeToolResult: Equatable, Sendable {
    let output: String
    let exitCode: Int32?
    let truncated: Bool
}

actor NativeAgentTools {
    static let maximumOutputBytes = 64 * 1024
    static let maximumCommandArguments = 128
    static let maximumArgumentBytes = 4_096
    private static let maximumDirectoryEntries = 500
    private static let maximumScannedFiles = 2_000
    private static let maximumMatches = 200
    private static let commandTimeout: Duration = .seconds(30)

    private let root: URL
    private let memoryStore: MemoryStore?
    private let instructionSnapshot: AgentInstructionSnapshot?
    private let reusableTools: ReusableAgentTools?
    private let appReader: NativeAgentAppReader?
    private let terminalTarget: String?
    private let terminalRunner: NativeAgentTerminalRunner?
    private let access: AgentToolAccess
    private var submittedTerminalRequests = Set<UUID>()

    init(directory: URL, memoryStore: MemoryStore? = nil, instructionSnapshot: AgentInstructionSnapshot? = nil,
         reusableTools: ReusableAgentTools? = nil, appReader: NativeAgentAppReader? = nil,
         terminalTarget: String? = nil, terminalRunner: NativeAgentTerminalRunner? = nil,
         access: AgentToolAccess = .reviewedTools) throws {
        let resolved = directory.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NativeAgentToolError.invalidDirectory
        }
        root = resolved
        self.memoryStore = memoryStore
        self.instructionSnapshot = instructionSnapshot
        guard reusableTools == nil || reusableTools?.directory == resolved else { throw NativeAgentToolError.outsideDirectory }
        self.reusableTools = reusableTools
        self.appReader = appReader
        guard (terminalTarget == nil) == (terminalRunner == nil),
              terminalTarget.map({ !$0.isEmpty && $0.utf8.count <= 4_096 && !$0.utf8.contains(0) }) ?? true else {
            throw NativeAgentToolError.invalidArguments
        }
        self.terminalTarget = terminalTarget
        self.terminalRunner = terminalRunner
        self.access = access
    }

    func prepared(_ request: NativeToolRequest) async throws -> NativeToolRequest {
        try enforceAccess(request.invocation)
        if let reason = request.reason {
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 320,
                  !reason.unicodeScalars.contains(where: CharacterSet.controlCharacters.union(.newlines).contains) else {
                throw NativeAgentToolError.invalidArguments
            }
        }
        let invocation: NativeToolInvocation
        switch request.invocation {
        case let .listDirectory(path): invocation = .listDirectory(path: try resolved(path).path)
        case let .readFile(path): invocation = .readFile(path: try resolved(path).path)
        case let .findFiles(query, path): invocation = .findFiles(query: query, path: try resolved(path).path)
        case let .runCommand(executable, arguments, directory):
            try Self.validateCommand(executable: executable, arguments: arguments)
            invocation = .runCommand(executable: executable, arguments: arguments, directory: try resolved(directory).path)
        case let .runInTerminal(command, _):
            try Self.validateTerminalCommand(command)
            guard let terminalTarget, terminalRunner != nil else { throw NativeAgentToolError.terminalUnavailable }
            invocation = .runInTerminal(command: command, target: terminalTarget)
        case let .memorySearch(query):
            guard memoryStore != nil, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  query.utf8.count <= MemoryStore.maximumQueryBytes, !query.utf8.contains(0) else {
                throw NativeAgentToolError.invalidArguments
            }
            invocation = request.invocation
        case .memoryRead:
            guard memoryStore != nil else { throw NativeAgentToolError.memoryUnavailable }
            invocation = request.invocation
        case let .proposeRecipe(title, body):
            guard memoryStore != nil, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  title.utf8.count <= MemoryStore.maximumTitleBytes, body.utf8.count <= MemoryStore.maximumBodyBytes,
                  !title.utf8.contains(0), !body.utf8.contains(0) else { throw NativeAgentToolError.invalidArguments }
            invocation = request.invocation
        case .listSavedTools:
            guard reusableTools != nil else { throw NativeAgentToolError.savedToolsUnavailable }
            invocation = request.invocation
        case let .proposeSavedTool(recipe, id, baseHash):
            guard let reusableTools, (id == nil) == (baseHash == nil) else { throw NativeAgentToolError.savedToolsUnavailable }
            _ = try recipe.validated()
            _ = try resolved(recipe.directory)
            if let id, try await reusableTools.approved(id).hash != baseHash { throw NativeAgentToolError.savedToolChanged }
            invocation = request.invocation
        case let .runSavedTool(id, hash, _):
            guard let reusableTools else { throw NativeAgentToolError.savedToolsUnavailable }
            let snapshot = try await reusableTools.approved(id)
            guard snapshot.hash == hash else { throw NativeAgentToolError.savedToolChanged }
            guard snapshot.recipe.enabled else { throw NativeAgentToolError.savedToolDisabled }
            _ = try resolved(snapshot.recipe.directory)
            invocation = .runSavedTool(id: id, hash: hash, snapshot: snapshot)
        case .readApp:
            guard appReader != nil else { throw NativeAgentToolError.appContextUnavailable }
            invocation = request.invocation
        case let .readSkill(id, path):
            try AgentInstructions.validateSkillPath(path)
            guard instructionSnapshot?.skills.contains(where: { $0.id == id }) == true else {
                throw NativeAgentToolError.skillUnavailable
            }
            invocation = request.invocation
        case .delegateTask: throw NativeAgentToolError.invalidArguments
        }
        return .init(id: request.id, callID: request.callID, name: request.name, invocation: invocation, reason: request.reason)
    }

    func execute(_ request: NativeToolRequest, proposalSource: String = "native-agent") async throws -> NativeToolResult {
        try Task.checkCancellation()
        try enforceAccess(request.invocation)
        switch request.invocation {
        case let .listDirectory(path): return try listDirectory(path)
        case let .readFile(path): return try readFile(path)
        case let .findFiles(query, path): return try findFiles(query: query, path: path)
        case let .runCommand(executable, arguments, directory):
            return try await runCommand(executable: executable, arguments: arguments, directory: directory)
        case let .runInTerminal(command, target):
            try Self.validateTerminalCommand(command)
            guard let terminalRunner, let target, target == terminalTarget else { throw NativeAgentToolError.terminalUnavailable }
            guard submittedTerminalRequests.insert(request.id).inserted else { throw NativeAgentToolError.terminalAlreadySubmitted }
            // Never retry an injection whose side effects may already have reached the shell.
            try await MainActor.run {
                try Task.checkCancellation()
                try terminalRunner(command)
            }
            return .init(output: "Submitted the reviewed command and Return to the selected terminal. Completion and exit status are unknown. No terminal output was captured.", exitCode: nil, truncated: false)
        case let .memorySearch(query): return try await memorySearch(query)
        case let .memoryRead(id): return try await memoryRead(id)
        case let .proposeRecipe(title, body): return try await proposeRecipe(title: title, body: body, source: proposalSource)
        case let .readSkill(id, path): return try readSkill(id, path: path)
        case .listSavedTools:
            guard let reusableTools else { throw NativeAgentToolError.savedToolsUnavailable }
            var lines: [String] = []
            var bytes = 0
            for tool in try await reusableTools.approved() where tool.recipe.enabled {
                let line = try Self.jsonLine(["id": tool.id.uuidString.lowercased(), "hash": tool.hash,
                    "revision": tool.revision, "name": tool.recipe.name, "description": tool.recipe.description,
                    "executable": tool.recipe.executable, "arguments": tool.recipe.arguments, "directory": tool.recipe.directory])
                bytes += line.utf8.count + 1
                if bytes > Self.maximumOutputBytes { return bounded(lines.joined(separator: "\n"), truncated: true) }
                lines.append(line)
            }
            return bounded(lines.isEmpty ? "No approved reusable tools. Propose one for user review." : lines.joined(separator: "\n"))
        case let .proposeSavedTool(recipe, id, baseHash):
            guard let reusableTools else { throw NativeAgentToolError.savedToolsUnavailable }
            _ = try resolved(recipe.directory)
            let proposal = try await reusableTools.propose(recipe, id: id, baseHash: baseHash, source: proposalSource)
            return bounded("Staged reusable tool proposal \(proposal.id.uuidString.lowercased()). It cannot run until reviewed and applied in Reusable Tools; running still needs separate execution approval.")
        case let .runSavedTool(id, hash, snapshot):
            guard let reusableTools, let snapshot, snapshot.id == id, snapshot.hash == hash,
                  try await reusableTools.approved(id) == snapshot else { throw NativeAgentToolError.savedToolChanged }
            guard snapshot.recipe.enabled else { throw NativeAgentToolError.savedToolDisabled }
            try Task.checkCancellation()
            return try await runCommand(executable: snapshot.recipe.executable, arguments: snapshot.recipe.arguments,
                                        directory: snapshot.recipe.directory)
        case let .readApp(kind):
            guard let appReader else { throw NativeAgentToolError.appContextUnavailable }
            let text = try await appReader(kind)
            try Task.checkCancellation()
            return bounded(text)
        case .delegateTask: throw NativeAgentToolError.invalidArguments
        }
    }

    private func enforceAccess(_ invocation: NativeToolInvocation) throws {
        guard access == .reviewedTools || (access == .projectRead && invocation.isScopedRead) else {
            throw NativeAgentToolError.capabilityDenied
        }
    }

    private static func validateTerminalCommand(_ command: String) throws {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              command.utf8.count <= 4_096,
              !command.unicodeScalars.contains(where: CharacterSet.controlCharacters.union(.newlines).contains) else {
            throw NativeAgentToolError.invalidArguments
        }
    }

    private func memorySearch(_ query: String) async throws -> NativeToolResult {
        guard let memoryStore else { throw NativeAgentToolError.memoryUnavailable }
        let matches = try await memoryStore.pages(query: query)
        var returned: [MemoryPage] = []
        var lines: [String] = []
        var bytes = 0
        for page in matches {
            let line = try Self.jsonLine(["id": page.id.uuidString.lowercased(), "title": page.title,
                                         "kind": page.kind, "revision": page.revision])
            let added = line.utf8.count + (lines.isEmpty ? 0 : 1)
            guard bytes + added <= MemoryStore.maximumReturnedBytes else { break }
            lines.append(line); returned.append(page); bytes += added
        }
        let output = lines.joined(separator: "\n")
        _ = try await memoryStore.recordRetrieval(pages: returned, returnedBytes: output.utf8.count, mechanism: "native")
        return .init(output: output, exitCode: nil, truncated: returned.count < matches.count)
    }

    private func memoryRead(_ id: UUID) async throws -> NativeToolResult {
        guard let memoryStore else { throw NativeAgentToolError.memoryUnavailable }
        guard let page = try await memoryStore.pages().first(where: { $0.id == id }) else { throw NativeAgentToolError.memoryNotFound }
        let header = try Self.jsonLine(["id": page.id.uuidString.lowercased(), "title": page.title,
                                       "kind": page.kind, "revision": page.revision]) + "\n"
        let body = Self.utf8Prefix(page.body, maximumBytes: max(0, MemoryStore.maximumReturnedBytes - header.utf8.count))
        let output = header + body
        _ = try await memoryStore.recordRetrieval(pages: [page], returnedBytes: output.utf8.count, mechanism: "native")
        return .init(output: output, exitCode: nil, truncated: body.utf8.count < page.body.utf8.count)
    }

    private func proposeRecipe(title: String, body: String, source: String) async throws -> NativeToolResult {
        guard let memoryStore else { throw NativeAgentToolError.memoryUnavailable }
        let proposal = try await memoryStore.propose(title: title, body: body, kind: "how-to", source: source)
        return .init(output: "Staged pending recipe proposal \(proposal.id.uuidString.lowercased()). Review it in Project Memory before applying.",
                     exitCode: nil, truncated: false)
    }

    private func readSkill(_ id: String, path: String) throws -> NativeToolResult {
        guard let instructionSnapshot else { throw NativeAgentToolError.skillUnavailable }
        let source = try instructionSnapshot.readSkill(id: id, path: path)
        return bounded("Source: \(source.declaredPath)\nResolved source: \(source.resolvedPath)\nScope: \(source.scope)\nSHA-256: \(source.sha256)\n\n\(source.text)")
    }

    private static func jsonLine(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    private static func utf8Prefix(_ value: String, maximumBytes: Int) -> String {
        var data = Data(value.utf8.prefix(maximumBytes))
        while String(data: data, encoding: .utf8) == nil { data.removeLast() }
        return String(decoding: data, as: UTF8.self)
    }

    private func listDirectory(_ path: String) throws -> NativeToolResult {
        let directory = try resolved(path)
        let values = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        guard values.count <= Self.maximumDirectoryEntries else { throw NativeAgentToolError.tooManyResults }
        let lines = try values.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                return url.lastPathComponent + (isDirectory ? "/" : "")
            }
        return bounded(lines.joined(separator: "\n"))
    }

    private func readFile(_ path: String) throws -> NativeToolResult {
        let file = try resolved(path)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw NativeAgentToolError.invalidFile }
        guard (attributes[.size] as? NSNumber)?.intValue ?? (Self.maximumOutputBytes + 1) <= Self.maximumOutputBytes else {
            throw NativeAgentToolError.outputTooLarge
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard let text = String(data: data, encoding: .utf8) else { throw NativeAgentToolError.notUTF8 }
        return NativeToolResult(output: text, exitCode: nil, truncated: false)
    }

    private func findFiles(query: String, path: String) throws -> NativeToolResult {
        guard !query.isEmpty, query.utf8.count <= 256, !query.utf8.contains(0) else {
            throw NativeAgentToolError.invalidArguments
        }
        let directory = try resolved(path)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw NativeAgentToolError.invalidDirectory }
        var scanned = 0
        var matches: [String] = []
        while let url = enumerator.nextObject() as? URL {
            scanned += 1
            guard scanned <= Self.maximumScannedFiles else { throw NativeAgentToolError.tooManyResults }
            let candidate = try confined(url)
            guard candidate.lastPathComponent.localizedCaseInsensitiveContains(query) else { continue }
            matches.append(relative(candidate))
            if matches.count == Self.maximumMatches { break }
        }
        return bounded(matches.sorted().joined(separator: "\n"), truncated: matches.count == Self.maximumMatches)
    }

    private func runCommand(executable: String, arguments: [String], directory: String) async throws -> NativeToolResult {
        try Self.validateCommand(executable: executable, arguments: arguments)
        let cwd = try resolved(directory)
        let result = try await CommandRunner(
            executable: URL(fileURLWithPath: executable).standardizedFileURL,
            arguments: arguments,
            directory: cwd,
            maximumBytes: Self.maximumOutputBytes
        ).run(timeout: Self.commandTimeout)
        try Task.checkCancellation()
        return result
    }

    nonisolated static func validateCommand(executable: String, arguments: [String]) throws {
        guard executable.hasPrefix("/"), executable.utf8.count <= 4_096, !executable.utf8.contains(0),
              URL(fileURLWithPath: executable).standardizedFileURL.path == executable,
              arguments.count <= maximumCommandArguments,
              arguments.allSatisfy({ $0.utf8.count <= maximumArgumentBytes && !$0.utf8.contains(0) }) else {
            throw NativeAgentToolError.invalidArguments
        }
    }

    private func resolved(_ path: String) throws -> URL {
        guard !path.utf8.contains(0), path.utf8.count <= 4_096 else { throw NativeAgentToolError.invalidPath }
        let candidate = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
        return try confined(candidate.resolvingSymlinksInPath().standardizedFileURL)
    }

    private func confined(_ url: URL) throws -> URL {
        let path = url.path
        guard path == root.path || path.hasPrefix(root.path + "/") else { throw NativeAgentToolError.outsideDirectory }
        return url
    }

    private func relative(_ url: URL) -> String {
        url.path == root.path ? "." : String(url.path.dropFirst(root.path.count + 1))
    }

    private func bounded(_ output: String, truncated: Bool = false) -> NativeToolResult {
        let data = Data(output.utf8)
        guard data.count > Self.maximumOutputBytes else {
            return NativeToolResult(output: output, exitCode: nil, truncated: truncated)
        }
        return NativeToolResult(
            output: String(decoding: data.prefix(Self.maximumOutputBytes), as: UTF8.self),
            exitCode: nil,
            truncated: true
        )
    }
}

enum NativeAgentToolError: Error, LocalizedError, Equatable {
    case invalidArguments, invalidDirectory, invalidFile, invalidPath, notUTF8, outsideDirectory
    case outputTooLarge, tooManyResults, timedOut, launchFailed, memoryUnavailable, memoryNotFound, skillUnavailable
    case savedToolsUnavailable, savedToolChanged, savedToolDisabled, appContextUnavailable
    case terminalUnavailable, terminalAlreadySubmitted
    case capabilityDenied

    var errorDescription: String? {
        switch self {
        case .invalidArguments: "The tool arguments are invalid or exceed their limits."
        case .invalidDirectory: "The requested directory does not exist."
        case .invalidFile: "The requested path is not a regular file."
        case .invalidPath: "The requested path is invalid."
        case .notUTF8: "The requested file is not UTF-8 text."
        case .outsideDirectory: "The requested path resolves outside the chosen directory."
        case .outputTooLarge: "The requested file exceeds the 64 KiB read limit."
        case .tooManyResults: "The request exceeds the bounded search or directory limit."
        case .timedOut: "The command exceeded the 30 second limit and was terminated."
        case .launchFailed: "The command could not be launched."
        case .memoryUnavailable: "Project memory is unavailable for this agent."
        case .memoryNotFound: "The requested approved memory page was not found."
        case .skillUnavailable: "Choose a skill from the reviewed instruction snapshot."
        case .savedToolsUnavailable: "Reusable tools are unavailable for this conversation scope."
        case .savedToolChanged: "The saved tool changed or was not prepared for review. Request and review its current approved version."
        case .savedToolDisabled: "The saved tool is disabled. Enable it explicitly in Reusable Tools before requesting a run."
        case .appContextUnavailable: "The originating terminal is unavailable. No app context was read."
        case .terminalUnavailable: "The reviewed terminal is unavailable or its target changed. No command was submitted."
        case .terminalAlreadySubmitted: "This terminal request was already attempted. Inspect the terminal before requesting another command."
        case .capabilityDenied: "This agent's configured tool access does not permit that action."
        }
    }
}

private final class CommandRunner: @unchecked Sendable {
    private let executable: URL
    private let arguments: [String]
    private let directory: URL
    private let output: OutputCollector
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NativeToolResult, Error>?
    private var finished = false
    private var timedOut = false
    private var cancelled = false
    private var pid: pid_t = 0
    private var parentStatus: Int32?
    private var readerFinished = false
    private var timeoutTask: Task<Void, Never>?

    init(executable: URL, arguments: [String], directory: URL, maximumBytes: Int) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        output = OutputCollector(maximumBytes: maximumBytes)
    }

    func run(timeout: Duration) async throws -> NativeToolResult {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let wasCancelled = lock.withLock { () -> Bool in
                    self.continuation = continuation
                    return cancelled
                }
                if wasCancelled { finish(error: CancellationError()); return }
                do {
                    let readDescriptor = try spawn()
                    let child = lock.withLock { pid }
                    Task.detached { [weak self, output] in
                        var buffer = [UInt8](repeating: 0, count: 8_192)
                        while true {
                            let count = read(readDescriptor, &buffer, buffer.count)
                            if count > 0 { output.append(Data(buffer.prefix(count))); continue }
                            if count == -1 && errno == EINTR { continue }
                            break
                        }
                        close(readDescriptor)
                        self?.readerDidFinish()
                    }
                    Task.detached { [weak self] in
                        var status: Int32 = 0
                        while waitpid(child, &status, 0) == -1 && errno == EINTR {}
                        self?.parentExited(status: status)
                    }
                    let timeoutTask = Task { [weak self] in
                        try? await Task.sleep(for: timeout)
                        self?.timeout()
                    }
                    let alreadyFinished = lock.withLock { () -> Bool in
                        guard !finished else { return true }
                        self.timeoutTask = timeoutTask
                        return false
                    }
                    if alreadyFinished { timeoutTask.cancel() }
                } catch {
                    finish(error: NativeAgentToolError.launchFailed)
                }
            }
        } onCancel: { cancel() }
    }

    private func timeout() {
        let child = lock.withLock { () -> pid_t in
            guard !finished else { return 0 }
            timedOut = true
            cancelled = true
            return pid
        }
        signalGroup(child)
    }

    private func cancel() {
        let child = lock.withLock { () -> pid_t in
            guard !finished else { return 0 }
            cancelled = true
            return pid
        }
        signalGroup(child)
    }

    private func parentExited(status: Int32) {
        let child = lock.withLock { () -> pid_t in
            parentStatus = status
            return pid
        }
        // A command returning does not authorize background descendants to outlive the bounded tool call.
        signalGroup(child)
        finishIfReady()
    }

    private func readerDidFinish() {
        lock.withLock { readerFinished = true }
        finishIfReady()
    }

    private func finishIfReady() {
        let completion = lock.withLock { () -> (CheckedContinuation<NativeToolResult, Error>, Result<NativeToolResult, Error>)? in
            guard !finished, readerFinished, let status = parentStatus, let continuation else { return nil }
            finished = true
            self.continuation = nil
            pid = 0
            timeoutTask?.cancel()
            timeoutTask = nil
            if timedOut { return (continuation, .failure(NativeAgentToolError.timedOut)) }
            if cancelled { return (continuation, .failure(CancellationError())) }
            let exitCode: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
            return (continuation, .success(output.result(exitCode: exitCode)))
        }
        if let completion { completion.0.resume(with: completion.1) }
    }

    private func signalGroup(_ child: pid_t) {
        guard child > 0 else { return }
        kill(-child, SIGTERM)
        kill(-child, SIGKILL)
    }

    private func spawn() throws -> Int32 {
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw NativeAgentToolError.launchFailed }
        let readDescriptor = descriptors[0]
        let writeDescriptor = descriptors[1]
        let nullDescriptor = open("/dev/null", O_RDONLY)
        guard nullDescriptor >= 0 else {
            close(readDescriptor); close(writeDescriptor)
            throw NativeAgentToolError.launchFailed
        }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0,
              posix_spawn_file_actions_adddup2(&actions, nullDescriptor, STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, writeDescriptor, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, writeDescriptor, STDERR_FILENO) == 0,
              posix_spawn_file_actions_addclose(&actions, readDescriptor) == 0,
              posix_spawn_file_actions_addclose(&actions, writeDescriptor) == 0,
              posix_spawn_file_actions_addclose(&actions, nullDescriptor) == 0,
              posix_spawn_file_actions_addchdir(&actions, directory.path) == 0,
              posix_spawnattr_init(&attributes) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            close(readDescriptor); close(writeDescriptor); close(nullDescriptor)
            throw NativeAgentToolError.launchFailed
        }
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        let values = [executable.path] + arguments
        let strings = values.map { strdup($0) }
        defer { strings.forEach { free($0) } }
        var argv: [UnsafeMutablePointer<CChar>?] = strings + [nil]
        var child: pid_t = 0
        let status = posix_spawn(&child, executable.path, &actions, &attributes, &argv, environ)
        close(writeDescriptor)
        close(nullDescriptor)
        guard status == 0 else { close(readDescriptor); throw NativeAgentToolError.launchFailed }
        let shouldCancel = lock.withLock { () -> Bool in
            pid = child
            return cancelled
        }
        if shouldCancel { signalGroup(child) }
        return readDescriptor
    }

    private func finish(error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<NativeToolResult, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<NativeToolResult, Error>? in
            guard !finished else { return nil }
            finished = true
            timeoutTask?.cancel()
            timeoutTask = nil
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let maximumBytes: Int
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false

    init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

    func append(_ chunk: Data) {
        lock.withLock {
            let remaining = maximumBytes - data.count
            if remaining > 0 { data.append(chunk.prefix(remaining)) }
            if chunk.count > remaining { truncated = true }
        }
    }

    func result(exitCode: Int32) -> NativeToolResult {
        lock.withLock {
            let decoded = String(decoding: data, as: UTF8.self)
            let output = utf8Prefix(decoded, maximumBytes: maximumBytes)
            return NativeToolResult(output: output, exitCode: exitCode,
                                    truncated: truncated || output.utf8.count < decoded.utf8.count)
        }
    }
}

private func utf8Prefix(_ value: String, maximumBytes: Int) -> String {
    guard value.utf8.count > maximumBytes else { return value }
    var data = Data(value.utf8.prefix(maximumBytes))
    while String(data: data, encoding: .utf8) == nil { data.removeLast() }
    return String(decoding: data, as: UTF8.self)
}
