import Foundation
import CoreFoundation
import Darwin

/// Account metadata from the supported app-server account/read method; never credential material.
enum CodexAccount: Equatable, Sendable {
    case unauthenticated
    case chatGPT(email: String?, plan: String?)
    case apiKey
    case other(String)
}

enum CodexClientError: LocalizedError {
    case unavailable, disconnected, invalidMessage, timedOut, requiresChatGPT, rejected(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "The selected Codex executable or project folder is unavailable."
        case .disconnected: "The Codex app-server connection closed. Reopen the conversation to continue."
        case .invalidMessage: "Codex returned an invalid or oversized app-server message."
        case .timedOut: "Codex did not respond to the app-server request in time."
        case .requiresChatGPT: "Sign in to ChatGPT with Codex before using this route. API-key authentication is not a ChatGPT subscription."
        case .rejected(let message): message
        }
    }
}

enum CodexRequestID: Hashable {
    case number(Int), string(String)
    init?(_ value: Any?) {
        if let value = value as? String, value.utf8.count <= 512 { self = .string(value) }
        else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                let integer = Int(value.stringValue) { self = .number(integer) }
        else { return nil }
    }
    var value: Any { switch self { case .number(let value): value; case .string(let value): value } }
}

/// A small JSONL seam lets fixtures exercise the real protocol without a login or model request.
@MainActor
protocol CodexRPCTransport: AnyObject {
    func start(onMessage: @escaping @MainActor (Data) -> Void,
               onClose: @escaping @MainActor () -> Void) throws
    func send(_ data: Data) throws
    func close() async
}

@MainActor
final class CodexSubscriptionClient {
    var onEvent: ((String, [String: Any]) -> Void)?
    var onServerRequest: ((CodexRequestID, String, [String: Any]) -> Void)?
    var onDisconnect: (() -> Void)?
    private let transport: any CodexRPCTransport
    private var nextID = 0
    private var connected = false
    private var initialized = false
    private var pending: [CodexRequestID: CheckedContinuation<Data, Error>] = [:]
    private var deadlines: [CodexRequestID: Task<Void, Never>] = [:]

    init(executable: String, directory: URL, transport: (any CodexRPCTransport)? = nil) {
        self.transport = transport ?? CodexProcessTransport(executable: executable, directory: directory)
    }

    func connect() async throws {
        if initialized { return }
        guard !connected else { throw CodexClientError.rejected("Codex is already connecting.") }
        connected = true
        do {
            try transport.start(onMessage: { [weak self] in self?.receive($0) }, onClose: { [weak self] in self?.disconnected() })
            _ = try await request("initialize", ["clientInfo": ["name": "trellis", "title": "Trellis", "version": "1"], "capabilities": ["experimentalApi": true]])
            try send(["method": "initialized", "params": [:]])
            initialized = true
        } catch { await close(); throw error }
    }

    func account() async throws -> CodexAccount {
        try await connect()
        let result = try await request("account/read", ["refreshToken": false])
        guard let account = result["account"] as? [String: Any] else { return .unauthenticated }
        switch account["type"] as? String {
        case "chatgpt": return .chatGPT(email: account["email"] as? String, plan: account["planType"] as? String)
        case "apiKey": return .apiKey
        case let type?: return .other(type)
        default: throw CodexClientError.invalidMessage
        }
    }

    func models() async throws -> [AgentModel] {
        try await connect()
        var models: [AgentModel] = [], cursor: String?
        var seen = Set<String>()
        for _ in 0..<20 {
            var params: [String: Any] = ["limit": 100, "includeHidden": false]
            if let cursor { params["cursor"] = cursor }
            let result = try await request("model/list", params)
            let parsed = try AgentModelCatalog.parseCodexResponse(JSONSerialization.data(withJSONObject: ["result": result]))
            models += parsed.models
            guard Set(models.map(\.id)).count == models.count else { throw CodexClientError.invalidMessage }
            guard let next = parsed.nextCursor else { return models }
            guard seen.insert(next).inserted else { throw CodexClientError.invalidMessage }
            cursor = next
        }
        throw CodexClientError.invalidMessage
    }

    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard connected else { throw CodexClientError.disconnected }
        nextID += 1
        let id = CodexRequestID.number(nextID)
        let data: Data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    self?.finish(id, result: .failure(CodexClientError.timedOut))
                }
                do { try send(["id": id.value, "method": method, "params": params]) }
                catch { finish(id, result: .failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) }
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CodexClientError.invalidMessage }
        return result
    }

    func respond(_ id: CodexRequestID, result: [String: Any]) throws {
        try send(["id": id.value, "result": result])
    }

    func rejectUnsupported(_ id: CodexRequestID, method: String) throws {
        try send(["id": id.value, "error": ["code": -32601, "message": "Trellis does not support this Codex request: \(method). No approval was granted."]])
    }

    /// Interrupt is best effort; closing the owned process below remains bounded if Codex is unresponsive.
    func interrupt(threadID: String, turnID: String) {
        nextID += 1
        try? send(["id": nextID, "method": "turn/interrupt", "params": ["threadId": threadID, "turnId": turnID]])
    }

    func close() async {
        disconnected(notify: false)
        await transport.close()
    }

    private func send(_ object: [String: Any]) throws {
        guard connected else { throw CodexClientError.disconnected }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= 4 * 1024 * 1024 else { throw CodexClientError.invalidMessage }
        data.append(0x0a)
        try transport.send(data)
    }

    private func receive(_ data: Data) {
        guard connected else { return }
        guard data.count <= 4 * 1024 * 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            disconnected(); Task { await transport.close() }; return
        }
        if let method = object["method"] as? String, let params = object["params"] as? [String: Any] {
            if let id = CodexRequestID(object["id"]) {
                if let onServerRequest { onServerRequest(id, method, params) }
                else { try? rejectUnsupported(id, method: method) }
            } else { onEvent?(method, params) }
        } else if let id = CodexRequestID(object["id"]) {
            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Codex rejected the request."
                finish(id, result: .failure(CodexClientError.rejected(String(message.prefix(4096)))))
            } else if let result = object["result"] as? [String: Any] { do { finish(id, result: .success(try JSONSerialization.data(withJSONObject: result))) }
                catch { finish(id, result: .failure(error)) } }
            else { finish(id, result: .failure(CodexClientError.invalidMessage)) }
        }
    }

    private func finish(_ id: CodexRequestID, result: Result<Data, Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func disconnected(notify: Bool = true) {
        let wasConnected = connected
        connected = false; initialized = false
        for id in Array(pending.keys) { finish(id, result: .failure(CodexClientError.disconnected)) }
        if notify && wasConnected { onDisconnect?() }
    }
}

@MainActor
private final class CodexProcessTransport: CodexRPCTransport {
    private let executable: String
    private let directory: URL
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var errors: Pipe?
    private var buffer = Data()
    private var onMessage: (@MainActor (Data) -> Void)?
    private var onClose: (@MainActor () -> Void)?

    init(executable: String, directory: URL) { self.executable = executable; self.directory = directory }

    func start(onMessage: @escaping @MainActor (Data) -> Void, onClose: @escaping @MainActor () -> Void) throws {
        guard process == nil, executable.hasPrefix("/"), !executable.utf8.contains(0),
              FileManager.default.isExecutableFile(atPath: executable), directory.isFileURL,
              (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw CodexClientError.unavailable }
        self.onMessage = onMessage; self.onClose = onClose
        let process = Process(), input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = directory
        // Preserve the installed Codex account, configuration, native headers and tool environment.
        // No credentials are read, copied or synthesized by Trellis.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = AgentInstallation.searchPath
        process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            Task { @MainActor [weak self] in self?.consume(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        process.terminationHandler = { [weak self] _ in Task { @MainActor [weak self] in self?.onClose?() } }
        self.process = process; self.input = input; self.output = output; self.errors = errors
        do { try process.run() } catch { dispose(); throw error }
    }

    func send(_ data: Data) throws {
        guard process?.isRunning == true, let input else { throw CodexClientError.disconnected }
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        guard process != nil else { return }
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0a) {
            guard newline <= 4 * 1024 * 1024 else { onClose?(); Task { await close() }; return }
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            if !line.isEmpty { onMessage?(line) }
        }
        if buffer.count > 4 * 1024 * 1024 { onClose?(); Task { await close() } }
    }

    func close() async {
        guard let owned = process else { return }
        onClose = nil
        try? input?.fileHandleForWriting.close()
        // Closing stdin lets Codex finish its own turn/child cleanup before forced termination.
        for _ in 0..<10 where owned.isRunning { try? await Task.sleep(for: .milliseconds(25)) }
        if owned.isRunning { owned.terminate() }
        for _ in 0..<40 where owned.isRunning { try? await Task.sleep(for: .milliseconds(25)) }
        if owned.isRunning { kill(owned.processIdentifier, SIGKILL) }
        if process === owned { dispose() }
    }

    deinit {
        // Normal lifecycle awaits close(); this covers a discarded client during setup.
        if let process, process.isRunning { process.terminate() }
    }

    private func dispose() {
        output?.fileHandleForReading.readabilityHandler = nil
        errors?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        try? output?.fileHandleForReading.close()
        try? errors?.fileHandleForReading.close()
        process?.terminationHandler = nil
        process = nil; input = nil; output = nil; errors = nil; buffer.removeAll()
    }
}
