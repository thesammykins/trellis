import Foundation

enum DirectAPI: String, Codable, CaseIterable, Sendable {
    case responses
    case chatCompletions
}

struct DirectModelConfiguration: Codable, Sendable {
    var baseURL: String
    var model: String
    var api: DirectAPI
    var maxOutputTokens: Int
}

enum DirectModelError: Error, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case invalidModel
    case invalidPrompt
    case invalidConfiguration
    case inputTooLarge
    case responseTooLarge
    case redirected
    case invalidResponse
    case requestFailed(Int)
    case refused
    case incomplete
}

extension DirectModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add an API key for this model route."
        case .invalidAPIKey: "The API key contains unsupported characters or is too large."
        case .invalidModel: "Enter a valid model identifier."
        case .invalidPrompt: "The selected context contains an unsupported null character."
        case .invalidConfiguration: "Check the direct model endpoint and token limit."
        case .inputTooLarge: "The selected context exceeds the 128 KiB request limit."
        case .responseTooLarge: "The model response exceeds the 2 MiB safety limit."
        case .redirected: "The model endpoint redirected the request; update the configured base URL."
        case .invalidResponse: "The model provider returned an invalid response."
        case let .requestFailed(status): "The model provider returned HTTP status \(status)."
        case .refused: "The model declined this request."
        case .incomplete: "The model response was incomplete; try again."
        }
    }
}

struct DirectModelClient {
    private static let maximumInputBytes = 128 * 1024
    private static let maximumResponseBytes = 2 * 1024 * 1024
    private static let maximumOutputTokens = 128 * 1024

    static func generate(
        configuration: DirectModelConfiguration,
        apiKey: String,
        prompt: String
    ) async throws -> String {
        let request = try makeRequest(configuration: configuration, apiKey: apiKey, prompt: prompt)
        let (data, response) = try await send(request)
        return try parseResponse(data, api: configuration.api, contentType: response.value(forHTTPHeaderField: "Content-Type"))
    }

    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let delegate = RedirectRefusingDelegate()
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 60
        sessionConfiguration.timeoutIntervalForResource = 120
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        sessionConfiguration.urlCache = nil
        let session = URLSession(configuration: sessionConfiguration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw DirectModelError.invalidResponse }
        if (300..<400).contains(http.statusCode) { throw DirectModelError.redirected }

        var data = Data()
        if http.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(http.expectedContentLength), maximumResponseBytes))
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumResponseBytes else { throw DirectModelError.responseTooLarge }
            data.append(byte)
        }
        guard (200..<300).contains(http.statusCode) else { throw DirectModelError.requestFailed(http.statusCode) }
        return (data, http)
    }

    static func makeRequest(
        configuration: DirectModelConfiguration,
        apiKey: String,
        prompt: String
    ) throws -> URLRequest {
        guard prompt.utf8.count <= maximumInputBytes else { throw DirectModelError.inputTooLarge }
        guard !prompt.unicodeScalars.contains("\0") else { throw DirectModelError.invalidPrompt }
        let body: [String: Any]
        switch configuration.api {
        case .responses:
            body = [
                "model": configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
                "input": prompt,
                "max_output_tokens": configuration.maxOutputTokens,
                "stream": false,
                "store": false,
                "tools": [],
            ]
        case .chatCompletions:
            body = [
                "model": configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
                "messages": [["role": "user", "content": prompt]],
                "max_completion_tokens": configuration.maxOutputTokens,
                "stream": false,
                "store": false,
                "tools": [],
            ]
        }
        return try makeRequest(configuration: configuration, apiKey: apiKey, body: body)
    }

    static func makeRequest(
        configuration: DirectModelConfiguration,
        apiKey: String,
        body suppliedBody: [String: Any]
    ) throws -> URLRequest {
        let url = try endpoint(for: configuration)
        guard !apiKey.isEmpty else { throw DirectModelError.missingAPIKey }
        guard apiKey.utf8.count <= 16 * 1024,
              !apiKey.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\r" || $0 == "\n" })
        else { throw DirectModelError.invalidAPIKey }
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, model.utf8.count <= 256,
              !model.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw DirectModelError.invalidModel }
        guard (1...maximumOutputTokens).contains(configuration.maxOutputTokens) else {
            throw DirectModelError.invalidConfiguration
        }
        var body = suppliedBody
        body["model"] = model
        let data = try JSONSerialization.data(withJSONObject: body)
        guard data.count <= maximumInputBytes else { throw DirectModelError.inputTooLarge }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        return request
    }

    static func parseResponse(_ data: Data, api: DirectAPI, contentType: String? = nil) throws -> String {
        guard data.count <= maximumResponseBytes else { throw DirectModelError.responseTooLarge }
        let isSSE = contentType?.lowercased().contains("text/event-stream") == true
            || data.starts(with: Data("data:".utf8))
        return try isSSE ? parseSSE(data, api: api) : parseJSON(data, api: api)
    }

    static func redirectedRequest(_ request: URLRequest) -> URLRequest? { nil }

    private static func endpoint(for configuration: DirectModelConfiguration) throws -> URL {
        guard var components = URLComponents(string: configuration.baseURL),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let scheme = components.scheme?.lowercased(), let host = components.host,
              scheme == "https" || (scheme == "http" && isLoopback(host))
        else { throw DirectModelError.invalidConfiguration }
        let suffix = configuration.api == .responses ? "responses" : "chat/completions"
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/\(suffix)" : "/\(basePath)/\(suffix)"
        guard let url = components.url else { throw DirectModelError.invalidConfiguration }
        return url
    }

    private static func isLoopback(_ host: String) -> Bool {
        let value = host.lowercased()
        if value == "localhost" || value == "::1" { return true }
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4
            && octets.first == "127"
            && octets.allSatisfy { UInt8($0) != nil }
    }

    private static func parseJSON(_ data: Data, api: DirectAPI) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DirectModelError.invalidResponse
        }
        if object["error"] is [String: Any] { throw DirectModelError.invalidResponse }
        switch api {
        case .responses:
            return try responseText(from: object)
        case .chatCompletions:
            guard let choice = (object["choices"] as? [[String: Any]])?.first,
                  choice["finish_reason"] as? String == "stop",
                  let message = choice["message"] as? [String: Any]
            else { throw DirectModelError.incomplete }
            if message["refusal"] as? String != nil { throw DirectModelError.refused }
            guard let text = message["content"] as? String, !text.isEmpty else {
                throw DirectModelError.invalidResponse
            }
            return text
        }
    }

    private static func responseText(from object: [String: Any]) throws -> String {
        guard object["status"] as? String == "completed",
              object["error"] is NSNull || object["error"] == nil,
              object["incomplete_details"] is NSNull || object["incomplete_details"] == nil
        else { throw DirectModelError.incomplete }
        let contents = (object["output"] as? [[String: Any]])?.flatMap { $0["content"] as? [[String: Any]] ?? [] } ?? []
        if contents.contains(where: { $0["type"] as? String == "refusal" }) { throw DirectModelError.refused }
        let text = contents.compactMap { item -> String? in
            guard item["type"] as? String == "output_text" else { return nil }
            return item["text"] as? String
        }.joined()
        guard !text.isEmpty else { throw DirectModelError.invalidResponse }
        return text
    }

    private static func parseSSE(_ data: Data, api: DirectAPI) throws -> String {
        guard let rawSource = String(data: data, encoding: .utf8) else { throw DirectModelError.invalidResponse }
        let source = rawSource.replacingOccurrences(of: "\r\n", with: "\n")
        var deltas = ""
        var finalText: String?
        var completed = false
        var chatFinishReason: String?

        for event in source.components(separatedBy: "\n\n") {
            let payload = event.split(separator: "\n")
                .filter { $0.hasPrefix("data:") }
                .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            guard !payload.isEmpty else { continue }
            if payload == "[DONE]" { completed = true; continue }
            guard let eventData = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any]
            else { throw DirectModelError.invalidResponse }
            if object["type"] as? String == "error" { throw DirectModelError.invalidResponse }

            switch api {
            case .responses:
                switch object["type"] as? String {
                case "response.output_text.delta": deltas += object["delta"] as? String ?? ""
                case "response.refusal.delta", "response.refusal.done": throw DirectModelError.refused
                case "response.completed":
                    guard let response = object["response"] as? [String: Any] else { throw DirectModelError.invalidResponse }
                    finalText = try responseText(from: response)
                    completed = true
                case "response.incomplete", "response.failed": throw DirectModelError.incomplete
                default: break
                }
            case .chatCompletions:
                guard let choice = (object["choices"] as? [[String: Any]])?.first else { continue }
                if let delta = choice["delta"] as? [String: Any] {
                    if delta["refusal"] as? String != nil { throw DirectModelError.refused }
                    deltas += delta["content"] as? String ?? ""
                }
                if let reason = choice["finish_reason"] as? String { chatFinishReason = reason }
            }
        }

        if api == .chatCompletions {
            guard completed, chatFinishReason == "stop" else { throw DirectModelError.incomplete }
        } else if !completed {
            throw DirectModelError.incomplete
        }
        let text = finalText ?? deltas
        guard !text.isEmpty else { throw DirectModelError.invalidResponse }
        return text
    }
}

private final class RedirectRefusingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(DirectModelClient.redirectedRequest(request))
    }
}
