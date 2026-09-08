import Foundation

@main
enum UpdateConfigurationCheck {
    static func main() throws {
        let absent = try UpdateConfiguration.read([:])
        let empty = try UpdateConfiguration.read(["SUFeedURL": "", "SUPublicEDKey": ""])
        precondition(absent == nil && empty == nil)
        let publicKey = Data(repeating: 7, count: 32).base64EncodedString()
        let valid: [String: Any] = [
            "SUFeedURL": "https://github.com/example/trellis/releases/latest/download/appcast.xml",
            "SUPublicEDKey": publicKey,
            "SUAllowsAutomaticUpdates": false,
            "SUVerifyUpdateBeforeExtraction": true,
            "SURequireSignedFeed": true,
            "SUSignedFeedFailureExpirationInterval": 0
        ]
        let configured = try UpdateConfiguration.read(valid)
        precondition(configured?.publicKey == publicKey)
        for feed in ["", "http://example.com/appcast.xml", "file:///tmp/appcast.xml", "https://user:password@example.com/appcast.xml", "https://example.com/feed?token=secret", "https://example.com/feed#fragment", "https://example.com/ bad", String(repeating: "a", count: 2049)] {
            var invalid = valid; invalid["SUFeedURL"] = feed
            expectFailure(invalid)
        }
        for key in ["", "not-base64", Data(repeating: 1, count: 31).base64EncodedString(), publicKey + "\n"] {
            var invalid = valid; invalid["SUPublicEDKey"] = key
            expectFailure(invalid)
        }
        for field in ["SUAllowsAutomaticUpdates", "SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed", "SUSignedFeedFailureExpirationInterval"] {
            var absent = valid; absent.removeValue(forKey: field); expectFailure(absent)
        }
        var unattended = valid; unattended["SUAllowsAutomaticUpdates"] = true; expectFailure(unattended)
        var unsigned = valid; unsigned["SURequireSignedFeed"] = false; expectFailure(unsigned)
        var expiry = valid; expiry["SUSignedFeedFailureExpirationInterval"] = 1728000; expectFailure(expiry)
        expectFailure(["SUFeedURL": 3, "SUPublicEDKey": ""])
        expectFailure(["SUFeedURL": "", "SUPublicEDKey": false])
        print("PASS updater configuration: unconfigured local builds, valid HTTPS/key, malformed/credential-bearing feeds, invalid keys, required signature policy and no unattended installs")
    }

    private static func expectFailure(_ metadata: [String: Any]) {
        do { _ = try UpdateConfiguration.read(metadata); preconditionFailure("Expected invalid update configuration to be rejected") }
        catch { }
    }
}
