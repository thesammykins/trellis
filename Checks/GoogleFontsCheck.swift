import Foundation

@main
enum GoogleFontsCheck {
    static func main() async throws {
        let font = GoogleFontsCatalog.fonts[0]
        let cssURL = GoogleFontsStore.cssURL(for: font)
        precondition(cssURL.scheme == "https" && cssURL.host == "fonts.googleapis.com")
        precondition(cssURL.absoluteString.contains("family=JetBrains%20Mono:wght@400"))
        precondition(GoogleFontsStore.isTrusted(URL(string: "https://fonts.gstatic.com/s/font.woff"), host: "fonts.gstatic.com"))
        precondition(!GoogleFontsStore.isTrusted(URL(string: "http://fonts.gstatic.com/s/font.woff"), host: "fonts.gstatic.com"))
        precondition(!GoogleFontsStore.isTrusted(URL(string: "https://fonts.gstatic.com.example/s/font.woff"), host: "fonts.gstatic.com"))

        let validCSS = Data("@font-face { src: url(https://fonts.gstatic.com/s/family/font.woff) format('woff'); }".utf8)
        let parsedURL = try GoogleFontsStore.fontURL(from: validCSS)
        precondition(parsedURL == URL(string: "https://fonts.gstatic.com/s/family/font.woff"))
        let subsetCSS = Data("""
        @font-face { src: url(https://fonts.gstatic.com/s/family/cyrillic.woff2); unicode-range: U+0400-04FF; }
        @font-face { src: url(https://fonts.gstatic.com/s/family/latin.woff2); unicode-range: U+0000-00FF; }
        """.utf8)
        let subsetURL = try GoogleFontsStore.fontURL(from: subsetCSS)
        precondition(subsetURL.lastPathComponent == "latin.woff2")
        let hostileCSS = Data("@font-face { src: url(https://example.com/font.woff); }".utf8)
        precondition((try? GoogleFontsStore.fontURL(from: hostileCSS)) == nil)
        precondition((try? GoogleFontsStore.fontURL(from: Data(repeating: 0x20, count: GoogleFontsStore.maximumStylesheetBytes + 1))) == nil)
        precondition((try? GoogleFontsStore.validateFont(Data("not a font".utf8), expectedFamily: font.family)) == nil)

        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("TrellisGoogleFontsMissing-" + UUID().uuidString)
        precondition((try? GoogleFontsStore.install(Data("not a font".utf8), font: .init(family: "../Fake", note: ""), directory: missing)) == nil)
        let report = GoogleFontsStore.registerInstalled(directory: missing)
        precondition(report.registeredFamilies.isEmpty && report.failures.isEmpty)

        if CommandLine.arguments.contains("--network") || CommandLine.arguments.contains("--network-all") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TrellisGoogleFontsCheck-" + UUID().uuidString, isDirectory: true)
            let fonts = CommandLine.arguments.contains("--network-all") ? GoogleFontsCatalog.fonts : [font]
            for candidate in fonts {
                FileHandle.standardError.write(Data(("Checking " + candidate.family + "\n").utf8))
                let installed = try await GoogleFontsDownloader(directory: directory).download(candidate)
                precondition(installed.deletingLastPathComponent() == directory)
                precondition(FileManager.default.fileExists(atPath: installed.path))
            }
            print("PASS trusted CSS/font download, Core Text validation, ASCII coverage, process registration and managed install for \(fonts.count) font(s)")
        } else {
            print("PASS curated URL construction, exact-host policy, bounded CSS parsing, invalid-font rejection and missing-store startup")
        }
    }
}
