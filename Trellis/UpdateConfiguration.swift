import Foundation

struct UpdateConfiguration: Equatable, Sendable {
    let feedURL: URL
    let publicKey: String

    /// Missing release inputs are normal for local builds. Partial or unsafe inputs are errors.
    static func read(_ metadata: [String: Any]) throws -> Self? {
        let feed = metadata["SUFeedURL"] as? String ?? ""
        let key = metadata["SUPublicEDKey"] as? String ?? ""
        guard !feed.isEmpty || !key.isEmpty else {
            if metadata["SUFeedURL"] != nil || metadata["SUPublicEDKey"] != nil {
                guard (metadata["SUFeedURL"] == nil || metadata["SUFeedURL"] is String),
                      (metadata["SUPublicEDKey"] == nil || metadata["SUPublicEDKey"] is String) else {
                    throw Failure("The update feed and public signing key must be strings.")
                }
            }
            return nil
        }
        guard feed.utf8.count <= 2048, let url = URL(string: feed),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.query == nil, !feed.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw Failure("This build needs a public HTTPS update feed without credentials, a query, or a fragment.")
        }
        guard key.utf8.count <= 128, let bytes = Data(base64Encoded: key), bytes.count == 32,
              bytes.base64EncodedString() == key else {
            throw Failure("This build needs a valid Ed25519 public update signing key.")
        }
        guard metadata["SUAllowsAutomaticUpdates"] as? Bool == false,
              metadata["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
              metadata["SURequireSignedFeed"] as? Bool == true,
              metadata["SUSignedFeedFailureExpirationInterval"] as? Int == 0 else {
            throw Failure("This build must require signed feeds and archives, with automatic installation disabled.")
        }
        return Self(feedURL: url, publicKey: key)
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
