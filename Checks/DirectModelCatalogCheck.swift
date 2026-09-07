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

        let parsed = try DirectModelCatalog.parse(Data(#"{"object":"list","data":[{"id":"z-model","object":"model"},{"id":"a-model","owned_by":"fixture"}]}"#.utf8))
        precondition(parsed.map(\.id) == ["a-model", "z-model"])
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
        print("PASS direct model catalogue endpoint, auth validation, redirect refusal, bounded parsing, IDs and duplicates")
    }

    private static func expect<T>(_ expected: DirectModelCatalogError, _ operation: () throws -> T) {
        do { _ = try operation(); preconditionFailure("Expected \(expected)") }
        catch let error as DirectModelCatalogError { precondition(error == expected) }
        catch { preconditionFailure("Unexpected error: \(error)") }
    }
}
