import Foundation

@main
enum AppThemeCheck {
    static func main() throws {
        let malicious = """
        background = #101010
        foreground = #eeeeee
        palette = 0=#000000
        palette = 1=#111111
        palette = 2=#222222
        palette = 3=#333333
        palette = 4=#444444
        palette = 5=#555555
        palette = 6=#666666
        palette = 7=#777777
        palette = 8=#888888
        palette = 9=#999999
        palette = 10=#aaaaaa
        palette = 11=#bbbbbb
        palette = 12=#cccccc
        palette = 13=#dddddd
        palette = 14=#eeeeee
        palette = 15=#ffffff
        cursor-color = #123456
        selection-background = #abcdef
        command = rm -rf /tmp/example
        keybind = super+x=write_screen_file
        """
        let parsed = ThemeCatalog.parseGhosttyTheme(named: "Fixture", text: malicious)
        let theme = try require(parsed.0, "valid colour fields should parse")
        precondition(parsed.1.count == 2)
        let config = try theme.ghosttyColorConfiguration()
        precondition(config.contains("cursor-color = #123456") && config.contains("selection-background = #ABCDEF"))
        precondition(!config.contains("command") && !config.contains("keybind") && config.contains("palette = 15=#FFFFFF"))

        precondition(abs(AppTheme.contrast("000000", on: "FFFFFF") - 21) < 0.001)
        precondition(abs(AppTheme.contrast("657B83", on: "FDF6E3") - 4.13) < 0.02)
        var lowContrast = theme
        lowContrast.colors.background = "FDF6E3"; lowContrast.colors.surface = "F7F1DF"
        lowContrast.colors.text = "657B83"; lowContrast.colors.secondary = "9AA6A5"
        precondition(!lowContrast.contrastWarnings.isEmpty)
        let adjusted = lowContrast.improvingAppContrast()
        precondition(adjusted.contrastWarnings.isEmpty)
        precondition(adjusted.colors.terminalPalette == lowContrast.colors.terminalPalette)
        precondition(adjusted.colors.terminalForeground == lowContrast.colors.terminalForeground)
        let roundTrip = try AppTheme.importData(theme.exportedData())
        precondition(roundTrip == theme)
        var object = try JSONSerialization.jsonObject(with: theme.exportedData()) as! [String: Any]
        object["command"] = "open /Applications/Calculator.app"
        let unsafe = try JSONSerialization.data(withJSONObject: object)
        precondition((try? AppTheme.importData(unsafe)) == nil)
        precondition((try? AppTheme.importData(Data(repeating: 0x20, count: 65 * 1024))) == nil)

        let suite = "AppThemeCheck-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        ThemeSelection.save(theme.id, to: defaults)
        precondition(ThemeSelection.load(from: defaults) == theme.id)
        if CommandLine.arguments.count == 2 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let names = try urls.compactMap { url -> String? in
                guard let text = String(data: try Data(contentsOf: url), encoding: .utf8) else { return nil }
                return ThemeCatalog.parseGhosttyTheme(named: url.lastPathComponent, text: text).0?.name
            }
            for family in ["Catppuccin", "Dracula", "Solarized", "Cyberpunk"] {
                precondition(names.contains { $0.localizedCaseInsensitiveContains(family) }, "Missing bundled \(family) family")
            }
        }
        print("PASS safe Ghostty parsing, bounded JSON import, roundtrip, terminal config and selection persistence")
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CheckError.failed(message) }
        return value
    }
    enum CheckError: Error { case failed(String) }
}
