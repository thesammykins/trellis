import CryptoKit
import Foundation

// Disposable fixture keys only; never accesses the Keychain or the app's preferences.
@main
enum UpdateSigningFixture {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let key = Curve25519.Signing.PrivateKey()
        let privateFile = folder.appendingPathComponent("fixture-private-key")
        try key.rawRepresentation.base64EncodedData().write(to: privateFile, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateFile.path)
        let info: [String: Any] = [
            "CFBundleIdentifier": "in.sammyk.trellis.update-fixture",
            "CFBundleExecutable": "Trellis", "CFBundleName": "Trellis",
            "CFBundlePackageType": "APPL", "CFBundleVersion": "42",
            "CFBundleShortVersionString": "0.0.42", "LSMinimumSystemVersion": "27.0",
            "SUFeedURL": "https://example.com/fixture/appcast.xml",
            "SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString(),
            "SURequireSignedFeed": true, "SUVerifyUpdateBeforeExtraction": true,
            "SUAllowsAutomaticUpdates": false, "SUEnableAutomaticChecks": false,
            "SUSignedFeedFailureExpirationInterval": 0
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: folder.appendingPathComponent("Trellis.app/Contents/Info.plist"))
    }
}
