import Foundation

@main
enum GhosttyImportCheck {
    static func main() throws {
        let catalog = ThemeCatalog(themes: [.graphite], diagnostics: [])
        let text = """
        font-family = "Fixture Mono"
        font-family = Ignored Fallback
        font-size = 18
        macos-option-as-alt = true
        keybind = super+shift+f=start_search
        foreground = #AABBCC
        palette = 2=#102030
        command = /bin/zsh -c dangerous
        config-file = /tmp/not-read
        unknown-secret = do-not-echo
        keybind = global:super+x=close_surface
        font-size = nan
        """
        let result = try GhosttyImport.parse(text, baseline: .default, baselineTheme: .graphite, catalog: catalog)
        precondition(result.preferences.fontFamily == "Fixture Mono")
        precondition(result.preferences.fontSize == 18 && result.preferences.optionAsAlt)
        precondition(result.preferences.keybindings == [.init(trigger: "super+shift+f", action: .startSearch)])
        precondition(result.appTheme?.colors.terminalForeground == "AABBCC")
        precondition(result.appTheme?.colors.terminalPalette[2] == "102030")
        precondition(result.skipped.contains { $0.key == "command" && $0.summary.contains("never") })
        precondition(result.skipped.contains { $0.key == "config-file" && $0.summary.contains("never") })
        precondition(result.skipped.contains { $0.key == "unknown-secret" && !$0.summary.contains("do-not-echo") })
        precondition(result.detected.contains { $0.summary == "Font family: Fixture Mono" })
        precondition(result.detected.contains { $0.summary == "super+shift+f → Start Search" })
        precondition(result.skipped.contains { $0.summary.contains("font fallbacks") })
        precondition(result.preferences.validationError == nil)

        let untouched = try GhosttyImport.parse("font-size = 16", baseline: .default, baselineTheme: .graphite, catalog: catalog)
        precondition(untouched.appTheme == nil)
        let orderedTheme = try GhosttyImport.parse("foreground=#123456\ntheme=Graphite", baseline: .default, baselineTheme: nil, catalog: catalog)
        precondition(orderedTheme.appTheme?.colors.terminalForeground == "123456")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-ghostty-import-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let oversized = root.appendingPathComponent("config")
        try Data(repeating: 0x20, count: GhosttyImport.maximumBytes + 1).write(to: oversized)
        assertThrows { try GhosttyImport.read(oversized, baseline: .default, baselineTheme: nil, catalog: catalog) }
        assertThrows { try GhosttyImport.read(URL(fileURLWithPath: "/dev/null"), baseline: .default, baselineTheme: nil, catalog: catalog) }
        let injection = try GhosttyImport.parse("font-family = bad\0value", baseline: .default, baselineTheme: nil, catalog: catalog)
        precondition(injection.preferences == .default && injection.skipped.count == 1)
        print("PASS bounded Ghostty import, validation, skipped directives and no implicit theme reset")
    }

    private static func assertThrows(_ operation: () throws -> Any) {
        do { _ = try operation(); preconditionFailure("Expected failure") } catch {}
    }
}
