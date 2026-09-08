import Foundation

@main
enum DirectModelCatalogCheck {
    static func main() throws {
        let request = try DirectModelCatalog.makeRequest(baseURL: "https://api.openai.com/v1/", apiKey: "fixture-key")
        precondition(request.url?.absoluteString == "https://api.openai.com/v1/models")
        precondition(request.httpMethod == "GET")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
        precondition(request.httpBody == nil)
        let loopback = try DirectModelCatalog.makeRequest(baseURL: "http://127.0.0.1:11434/v1", apiKey: "local")
        precondition(loopback.url?.absoluteString == "http://127.0.0.1:11434/v1/models")
        precondition(DirectModelCatalog.redirectedRequest(URLRequest(url: URL(string: "https://elsewhere.invalid/v1/models")!)) == nil)
        for endpoint in ["https://openrouter.ai/api/v1", "https://openrouter.ai/api/v1/", "https://OPENROUTER.AI:443/api/v1"] {
            let anonymous = try DirectModelCatalog.makeRequest(baseURL: endpoint, apiKey: "")
            precondition(anonymous.url?.path == "/api/v1/models" && anonymous.httpMethod == "GET")
            precondition(anonymous.value(forHTTPHeaderField: "Authorization") == nil)
            precondition(anonymous.value(forHTTPHeaderField: "Accept") == "application/json")
            precondition(DirectModelCatalog.redirectedRequest(anonymous) == nil)
            let authenticated = try DirectModelCatalog.makeRequest(baseURL: endpoint, apiKey: "fixture-only")
            precondition(authenticated.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only")
        }
        for endpoint in ["https://openrouter.ai:8443/api/v1", "https://openrouter.ai/other", "https://openrouter.ai/api/v1/models",
                         "https://openrouter.ai//api/v1", "https://openrouter.ai/api%2Fv1", "https://openrouter.ai/api/v1//",
                         "https://openrouter.ai.example.com/api/v1", "https://api.openrouter.ai/api/v1", "https://example.com/api/v1",
                         "https://api.deepseek.com", "https://generativelanguage.googleapis.com/v1beta/openai", "http://127.0.0.1:11434/v1"] {
            expect(.missingAPIKey) { try DirectModelCatalog.makeRequest(baseURL: endpoint, apiKey: "") }
        }
        for endpoint in ["http://openrouter.ai/api/v1", "https://user@openrouter.ai/api/v1", "https://:secret@openrouter.ai/api/v1",
                         "https://openrouter.ai/api/v1?query=1", "https://openrouter.ai/api/v1#fragment"] {
            expect(.invalidConfiguration) { try DirectModelCatalog.makeRequest(baseURL: endpoint, apiKey: "") }
        }
        for key in ["bad\nkey", "bad\rkey", "bad\0key", String(repeating: "x", count: 16 * 1024 + 1)] {
            expect(.invalidAPIKey) { try DirectModelCatalog.makeRequest(baseURL: "https://openrouter.ai/api/v1", apiKey: key) }
        }

        let parsed = try DirectModelCatalog.parse(Data(#"{"object":"list","data":[{"id":"z-model","object":"model"},{"id":"a-model","owned_by":"fixture"}]}"#.utf8))
        precondition(parsed.map(\.id) == ["a-model", "z-model"])
        for endpoint in ["https://generativelanguage.googleapis.com/v1beta/openai", "https://api.deepseek.com", "https://openrouter.ai/api/v1"] {
            let request = try DirectModelCatalog.makeRequest(baseURL: endpoint, apiKey: "fixture-only")
            precondition(request.url?.absoluteString == endpoint + "/models" && request.url?.query == nil)
        }
        let richCatalog = try JSONSerialization.data(withJSONObject: ["data": [["id": "fixture", "description": String(repeating: "d", count: 600_000)]]])
        let richResult = try DirectModelCatalog.parse(richCatalog)
        precondition(richResult.map(\.id) == ["fixture"])
        if CommandLine.arguments.count > 1 {
            let downloaded = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let advertised = try DirectModelCatalog.parse(downloaded)
            print("Parsed public catalogue: \(advertised.count) advertised IDs, \(downloaded.count) bytes")
        }
        expect(.malformedResponse) { try DirectModelCatalog.parse(Data(#"{"data":[{"id":"same"},{"id":"same"}]}"#.utf8)) }
        expect(.malformedResponse) { try DirectModelCatalog.parse(Data(#"{"data":[{"id":"bad\nmodel"}]}"#.utf8)) }
        expect(.malformedResponse) { try DirectModelCatalog.parse(Data(#"{"data":"wrong"}"#.utf8)) }
        let oversized = Data(#"{"data":[]}"#.utf8) + Data(repeating: 0x20, count: DirectModelCatalog.maximumResponseBytes)
        expect(.malformedResponse) { try DirectModelCatalog.parse(oversized) }
        let excessive = (0...DirectModelCatalog.maximumModels).map { ["id": "model-\($0)"] }
        let excessiveData = try JSONSerialization.data(withJSONObject: ["data": excessive])
        expect(.malformedResponse) { try DirectModelCatalog.parse(excessiveData) }
        expect(.missingAPIKey) { try DirectModelCatalog.makeRequest(baseURL: "https://api.openai.com/v1", apiKey: "") }
        expect(.invalidAPIKey) { try DirectModelCatalog.makeRequest(baseURL: "https://api.openai.com/v1", apiKey: "bad\nkey") }
        expect(.invalidConfiguration) { try DirectModelCatalog.makeRequest(baseURL: "http://example.com/v1", apiKey: "x") }
        expect(.invalidConfiguration) { try DirectModelCatalog.makeRequest(baseURL: "https://user:pass@example.com/v1", apiKey: "x") }
        expect(.invalidConfiguration) { try DirectModelCatalog.makeRequest(baseURL: "https://example.com/v1?next=elsewhere", apiKey: "x") }
        precondition(DirectModelCatalogError.requestFailed(401).errorDescription?.contains("saved API key") == true)
        precondition(DirectModelCatalogError.requestFailed(403).errorDescription?.contains("permissions") == true)
        precondition(DirectModelCatalogError.requestFailed(404).errorDescription?.contains("manually") == true)
        precondition(DirectModelCatalogError.requestFailed(429).errorDescription?.contains("rate limited") == true)
        print("PASS direct model catalogue endpoint, exact public OpenRouter discovery, auth boundaries, redirect refusal, bounded parsing, IDs and duplicates")
    }

    private static func expect<T>(_ expected: DirectModelCatalogError, _ operation: () throws -> T) {
        do { _ = try operation(); preconditionFailure("Expected \(expected)") }
        catch let error as DirectModelCatalogError { precondition(error == expected) }
        catch { preconditionFailure("Unexpected error: \(error)") }
    }
}
