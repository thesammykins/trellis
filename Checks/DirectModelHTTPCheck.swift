import Foundation

@main enum DirectModelHTTPCheck {
    static func main() async throws {
        let base = CommandLine.arguments[1]
        for api in DirectAPI.allCases {
            let configuration = DirectModelConfiguration(baseURL: base, model: "fixture", api: api, maxOutputTokens: 128)
            let result = try await DirectModelClient.generate(configuration: configuration, apiKey: "fixture-only", prompt: "fixture context")
            precondition(result == "Fixture response")
        }
        do {
            let configuration = DirectModelConfiguration(baseURL: base + "/redirect", model: "fixture", api: .responses, maxOutputTokens: 128)
            _ = try await DirectModelClient.generate(configuration: configuration, apiKey: "fixture-only", prompt: "fixture context")
            preconditionFailure("Redirect accepted")
        } catch DirectModelError.redirected {}
        print("PASS native HTTP Responses and Chat; redirect refused")
    }
}
