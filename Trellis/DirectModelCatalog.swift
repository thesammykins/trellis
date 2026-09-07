import AppKit
import Foundation
import SwiftUI

struct DirectModelCatalogEntry: Identifiable, Equatable, Sendable {
    let id: String
}

enum DirectModelCatalogError: LocalizedError, Equatable {
    case invalidConfiguration
    case missingAPIKey
    case invalidAPIKey
    case redirected
    case requestFailed(Int)
    case responseTooLarge
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Enter a valid direct API base URL."
        case .missingAPIKey: "Save an API key for this endpoint before loading models."
        case .invalidAPIKey: "The API key contains unsupported characters or is too large."
        case .redirected: "The models endpoint redirected the request. Update the configured base URL."
        case .requestFailed(401): "The saved API key was rejected (401). Save a valid key for this endpoint."
        case .requestFailed(403): "This API key cannot list models (403). Check its project or provider permissions."
        case .requestFailed(404), .requestFailed(405): "This endpoint does not support standard model discovery. Enter an exact model ID manually."
        case .requestFailed(429): "Model lookup is rate limited (429). Wait, then refresh."
        case let .requestFailed(status): "Model lookup failed with HTTP status \(status). Enter an exact model ID manually or try again."
        case .responseTooLarge: "The model catalogue exceeded its 512 KiB limit."
        case .malformedResponse: "The endpoint did not return a standard model catalogue. Enter an exact model ID manually."
        }
    }
}

struct DirectModelCatalog {
    static let maximumResponseBytes = 512 * 1024
    static let maximumModels = 2_000
    static let maximumModelIDBytes = 256

    static func load(baseURL: String, apiKey: String) async throws -> [DirectModelCatalogEntry] {
        let request = try makeRequest(baseURL: baseURL, apiKey: apiKey)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: DirectModelCatalogRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw DirectModelCatalogError.malformedResponse }
        if (300..<400).contains(response.statusCode) { throw DirectModelCatalogError.redirected }
        guard response.url == request.url else { throw DirectModelCatalogError.redirected }
        guard (200..<300).contains(response.statusCode) else { throw DirectModelCatalogError.requestFailed(response.statusCode) }
        guard response.expectedContentLength <= 0 || response.expectedContentLength <= maximumResponseBytes else {
            throw DirectModelCatalogError.responseTooLarge
        }
        var data = Data()
        if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumResponseBytes else { throw DirectModelCatalogError.responseTooLarge }
            data.append(byte)
        }
        return try parse(data)
    }

    static func makeRequest(baseURL: String, apiKey: String) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw DirectModelCatalogError.missingAPIKey }
        guard apiKey.utf8.count <= 16 * 1024,
              !apiKey.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\r" || $0 == "\n" }) else {
            throw DirectModelCatalogError.invalidAPIKey
        }
        guard var components = URLComponents(string: baseURL),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let scheme = components.scheme?.lowercased(), let host = components.host,
              scheme == "https" || (scheme == "http" && isLoopback(host)) else {
            throw DirectModelCatalogError.invalidConfiguration
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/models" : "/\(basePath)/models"
        guard let url = components.url else { throw DirectModelCatalogError.invalidConfiguration }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func parse(_ data: Data) throws -> [DirectModelCatalogEntry] {
        guard !data.isEmpty, data.count <= maximumResponseBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawModels = object["data"] as? [[String: Any]],
              rawModels.count <= maximumModels else { throw DirectModelCatalogError.malformedResponse }
        let models = try rawModels.map { item -> DirectModelCatalogEntry in
            guard let id = item["id"] as? String, !id.isEmpty, id.utf8.count <= maximumModelIDBytes,
                  !id.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
                throw DirectModelCatalogError.malformedResponse
            }
            return .init(id: id)
        }
        guard Set(models.map(\.id)).count == models.count else { throw DirectModelCatalogError.malformedResponse }
        return models.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func redirectedRequest(_ request: URLRequest) -> URLRequest? { nil }

    private static func isLoopback(_ host: String) -> Bool {
        let value = host.lowercased()
        if value == "localhost" || value == "::1" { return true }
        let octets = value.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.first == "127" && octets.allSatisfy { UInt8($0) != nil }
    }
}

private final class DirectModelCatalogRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(DirectModelCatalog.redirectedRequest(request))
    }
}

struct DirectModelCatalogPicker: View {
    let baseURL: String
    let apiKey: () throws -> String
    @Binding var modelID: String
    var credentialRevision: UUID?
    @State private var models: [DirectModelCatalogEntry] = []
    @State private var loading = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var operationID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Advertised model", selection: $modelID) {
                    Text("Choose a model").tag("")
                    ForEach(models) { Text($0.id).tag($0.id) }
                    if !modelID.isEmpty && !models.contains(where: { $0.id == modelID }) {
                        Text(modelID + " (manual)").tag(modelID)
                    }
                }
                Button("Load Models") { load() }.disabled(loading)
                if loading { Button("Cancel") { task?.cancel() } }
            }
            if loading { ProgressView("Loading models…").controlSize(.small) }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Text("The endpoint advertises identifiers only. Model capabilities are not inferred.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: baseURL) {
            task?.cancel(); operationID = UUID()
            models = []; loading = false; error = nil
        }
        .onChange(of: credentialRevision) {
            task?.cancel(); operationID = UUID()
            models = []; loading = false; error = nil
        }
        .onDisappear { task?.cancel() }
    }

    private func load() {
        task?.cancel(); models = []; loading = true; error = nil; operationID = UUID()
        let requestedBaseURL = baseURL
        let requestedOperationID = operationID
        let requestedAPIKey: String
        do { requestedAPIKey = try apiKey() }
        catch { loading = false; self.error = error.localizedDescription; announce("Model lookup failed"); return }
        task = Task {
            do {
                let result = try await DirectModelCatalog.load(baseURL: requestedBaseURL, apiKey: requestedAPIKey)
                try Task.checkCancellation()
                guard operationID == requestedOperationID, baseURL == requestedBaseURL else { return }
                models = result
                if result.isEmpty { error = "This endpoint advertised no models. Enter an exact model ID manually." }
                announce(result.isEmpty ? "No models advertised" : "Loaded \(result.count) models")
            } catch is CancellationError {}
            catch {
                guard operationID == requestedOperationID, baseURL == requestedBaseURL else { return }
                self.error = error.localizedDescription
                announce("Model lookup failed")
            }
            if operationID == requestedOperationID { loading = false }
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
