import Foundation
import Darwin

private let supportedVersions = ["2025-03-26", "2024-11-05"]
private let maximumLineBytes = 128 * 1024
private let maximumResultBytes = 32 * 1024

@main
struct MemoryBridge {
    static func main() async {
        guard let configuration = Configuration(arguments: Array(CommandLine.arguments.dropFirst())) else {
            FileHandle.standardError.write(Data("MemoryBridge requires --root <absolute-path> --project-id <id>\n".utf8))
            exit(EXIT_FAILURE)
        }

        do {
            let store = try MemoryStore(root: configuration.root, projectID: configuration.projectID)
            for line in LineReader(fileHandle: .standardInput, limit: maximumLineBytes) {
                await handle(line: line, store: store)
            }
        } catch {
            FileHandle.standardError.write(Data("MemoryBridge could not open its memory scope.\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func handle(line: LineReader.Line, store: MemoryStore) async {
        guard case let .data(data) = line else {
            respond(error: RPCError(code: -32600, message: "Request exceeds the maximum message size."), id: .null)
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let request = object as? [String: Any], request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String else {
            respond(error: RPCError(code: -32600, message: "Invalid JSON-RPC request."), id: .null)
            return
        }
        let id = request["id"].flatMap(RPCID.init)
        if request["id"] != nil && id == nil {
            respond(error: RPCError(code: -32600, message: "Invalid request identifier."), id: .null)
            return
        }
        if id == nil { return handleNotification(method: method) }
        let params = request["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            guard let requested = params["protocolVersion"] as? String else {
                respond(error: RPCError(code: -32602, message: "initialize requires protocolVersion."), id: id!)
                return
            }
            let version = supportedVersions.contains(requested) ? requested : supportedVersions[0]
            respond(result: [
                "protocolVersion": version,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "trellis-memory-bridge", "version": "0.1.0"]
            ], id: id!)
        case "ping":
            respond(result: [:], id: id!)
        case "tools/list":
            respond(result: ["tools": toolDefinitions()], id: id!)
        case "tools/call":
            await callTool(params: params, id: id!, store: store)
        default:
            respond(error: RPCError(code: -32601, message: "Method not found."), id: id!)
        }
    }

    private static func handleNotification(method: String) {
        // Only lifecycle notifications are intentionally accepted without a response.
        if method != "notifications/initialized" {
            FileHandle.standardError.write(Data("MemoryBridge ignored a notification.\n".utf8))
        }
    }

    private static func callTool(params: [String: Any], id: RPCID, store: MemoryStore) async {
        guard let name = params["name"] as? String,
              let arguments = params["arguments"] as? [String: Any] else {
            respond(error: RPCError(code: -32602, message: "tools/call requires a name and object arguments."), id: id)
            return
        }
        switch name {
        case "trellis_memory_search":
            guard let query = arguments["query"] as? String, arguments.count == 1 else {
                respond(error: RPCError(code: -32602, message: "Search requires only a string query."), id: id)
                return
            }
            do {
                let pages = try await store.pages(query: query)
                var limited: [[String: Any]] = []
                var returnedPages: [MemoryPage] = []
                for page in pages {
                    let entry: [String: Any] = ["id": page.id.uuidString, "title": page.title, "body": page.body,
                                                "kind": page.kind, "revision": page.revision, "hash": page.hash]
                    if encoded(["pages": limited + [entry]]).count > maximumResultBytes { continue }
                    limited.append(entry)
                    returnedPages.append(page)
                }
                let returnedBytes = toolResult(["pages": limited], id: id)
                do { _ = try await store.recordRetrieval(pages: returnedPages, returnedBytes: returnedBytes) }
                catch { FileHandle.standardError.write(Data("MemoryBridge could not record a retrieval receipt.\n".utf8)) }
            } catch {
                toolFailure("Memory search failed.", id: id)
            }
        case "trellis_memory_propose":
            guard let title = arguments["title"] as? String, let body = arguments["body"] as? String,
                  let kind = arguments["kind"] as? String, let source = arguments["source"] as? String,
                  arguments.keys.allSatisfy({ ["title", "body", "kind", "source", "pageID"].contains($0) }) else {
                respond(error: RPCError(code: -32602, message: "Proposal fields are invalid."), id: id)
                return
            }
            let pageID: UUID?
            if let raw = arguments["pageID"] { guard let text = raw as? String, let value = UUID(uuidString: text) else {
                respond(error: RPCError(code: -32602, message: "pageID must be a UUID."), id: id); return
            }; pageID = value } else { pageID = nil }
            do {
                let proposal = try await store.propose(title: title, body: body, kind: kind, pageID: pageID, source: source)
                toolResult(["id": proposal.id.uuidString, "status": proposal.status], id: id)
            } catch {
                toolFailure("Memory proposal was rejected.", id: id)
            }
        default:
            respond(error: RPCError(code: -32602, message: "Unknown tool."), id: id)
        }
    }

    private static func toolDefinitions() -> [[String: Any]] { [
        ["name": "trellis_memory_search", "description": "Search approved pages in this fixed Trellis project scope.",
         "inputSchema": ["type": "object", "properties": ["query": ["type": "string"]], "required": ["query"], "additionalProperties": false]],
        ["name": "trellis_memory_propose", "description": "Stage a memory proposal for human review in this fixed Trellis project scope.",
         "inputSchema": ["type": "object", "properties": ["title": ["type": "string"], "body": ["type": "string"], "kind": ["type": "string", "enum": ["decision", "constraint", "how-to", "reference", "lesson", "preference"]], "source": ["type": "string"], "pageID": ["type": "string", "format": "uuid"]], "required": ["title", "body", "kind", "source"], "additionalProperties": false]]
    ] }

    @discardableResult
    private static func toolResult(_ value: [String: Any], id: RPCID) -> Int {
        let data = encoded(value)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        respond(result: ["content": [["type": "text", "text": text]], "isError": false], id: id)
        return data.count
    }

    private static func toolFailure(_ message: String, id: RPCID) {
        respond(result: ["content": [["type": "text", "text": message]], "isError": true], id: id)
    }

    private static func respond(result: [String: Any], id: RPCID) { write(["jsonrpc": "2.0", "id": id.value, "result": result]) }
    private static func respond(error: RPCError, id: RPCID) { write(["jsonrpc": "2.0", "id": id.value, "error": ["code": error.code, "message": error.message]]) }
    private static func write(_ object: [String: Any]) { FileHandle.standardOutput.write(encoded(object) + Data("\n".utf8)) }
    private static func encoded(_ object: Any) -> Data { (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8) }
}

private struct Configuration {
    let root: URL
    let projectID: String
    init?(arguments: [String]) {
        guard arguments.count == 4, arguments[0] == "--root", arguments[2] == "--project-id",
              arguments[1].hasPrefix("/"), !arguments[1].utf8.contains(0), !arguments[3].isEmpty else { return nil }
        root = URL(fileURLWithPath: arguments[1], isDirectory: true)
        projectID = arguments[3]
    }
}

private enum RPCID {
    case string(String), number(Int), null
    init?(_ value: Any) { if let string = value as? String { self = .string(string) } else if let number = value as? Int { self = .number(number) } else if value is NSNull { self = .null } else { return nil } }
    var value: Any { switch self { case let .string(value): value; case let .number(value): value; case .null: NSNull() } }
}

private struct RPCError { let code: Int; let message: String }

private final class LineReader: Sequence, IteratorProtocol {
    enum Line { case data(Data), tooLarge }
    private let handle: FileHandle; private let limit: Int; private var buffer = Data(); private var exhausted = false; private var discarding = false
    init(fileHandle: FileHandle, limit: Int) { handle = fileHandle; self.limit = limit }
    func next() -> Line? {
        while !exhausted {
            if discarding {
                if let newline = buffer.firstIndex(of: 10) {
                    buffer.removeSubrange(...newline)
                    discarding = false
                    return .tooLarge
                }
                buffer.removeAll(keepingCapacity: true)
            } else if let newline = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                return .data(Data(line))
            } else if buffer.count > limit {
                discarding = true
                continue
            }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { exhausted = true; break }
            buffer.append(contentsOf: bytes.prefix(count))
        }
        if discarding { discarding = false; return .tooLarge }
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll() }
        return buffer.count <= limit ? .data(buffer) : .tooLarge
    }
}
