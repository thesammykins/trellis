import Foundation

struct AppTheme: Codable, Equatable, Identifiable {
    enum Appearance: String, Codable, CaseIterable { case light, dark }

    struct Colors: Codable, Equatable {
        var background: String
        var surface: String
        var text: String
        var secondary: String
        var accent: String
        var border: String
        var terminalForeground: String
        var terminalBackground: String
        var terminalPalette: [String]
        var terminalExtras: [String: String]? = nil
    }

    var id: String
    var name: String
    var attribution: String
    var appearance: Appearance
    var colors: Colors

    static let graphite = AppTheme(
        id: "trellis.graphite", name: "Graphite",
        attribution: "Original Trellis neutral palette · inspired by developer tools · not an official Codex theme",
        appearance: .dark,
        colors: Colors(
            background: "0E1116", surface: "151922", text: "E6EAF0", secondary: "929BA8",
            accent: "22C7A8", border: "2A313C", terminalForeground: "E6EAF0", terminalBackground: "0E1116",
            terminalPalette: ["171B22", "E06C75", "8FC17A", "E5C07B", "61AFEF", "C678DD", "56B6C2", "D7DAE0", "5C6370", "F07A85", "9DCF87", "F0D18A", "72B9F4", "D68AE8", "67C7D1", "FFFFFF"]
        )
    )

    var validationError: String? {
        guard !id.isEmpty, id.utf8.count <= 128, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 128, attribution.utf8.count <= 512 else { return "Theme identity is missing or too long." }
        let named = [colors.background, colors.surface, colors.text, colors.secondary, colors.accent,
                     colors.border, colors.terminalForeground, colors.terminalBackground]
        guard named.allSatisfy(Self.isHexColor) else { return "Theme colours must use six hexadecimal digits." }
        guard colors.terminalPalette.count == 16, colors.terminalPalette.allSatisfy(Self.isHexColor) else {
            return "A terminal palette must contain exactly 16 hexadecimal colours."
        }
        if let extras = colors.terminalExtras {
            guard Set(extras.keys).isSubset(of: ["cursor-color", "cursor-text", "selection-background", "selection-foreground"]), extras.values.allSatisfy(Self.isHexColor) else { return "Unsupported terminal colour setting." }
        }
        return nil
    }

    func ghosttyColorConfiguration() throws -> String {
        if let validationError { throw ThemeError.invalid(validationError) }
        return (["foreground = #\(colors.terminalForeground)", "background = #\(colors.terminalBackground)"] +
                colors.terminalPalette.enumerated().map { "palette = \($0.offset)=#\($0.element)" } +
                (colors.terminalExtras ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key) = #\($0.value)" })
            .joined(separator: "\n") + "\n"
    }

    func exportedData() throws -> Data {
        if let validationError { throw ThemeError.invalid(validationError) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func importData(_ data: Data) throws -> AppTheme {
        guard data.count <= 64 * 1024 else { throw ThemeError.invalid("Theme files may not exceed 64 KB.") }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any], Set(root.keys).isSubset(of: ["id", "name", "attribution", "appearance", "colors"]),
              let colors = root["colors"] as? [String: Any],
              Set(colors.keys).isSubset(of: ["background", "surface", "text", "secondary", "accent", "border", "terminalForeground", "terminalBackground", "terminalPalette", "terminalExtras"])
        else { throw ThemeError.invalid("Theme JSON contains unsupported fields.") }
        let theme = try JSONDecoder().decode(AppTheme.self, from: data)
        if let validationError = theme.validationError { throw ThemeError.invalid(validationError) }
        return theme
    }

    fileprivate static func isHexColor(_ value: String) -> Bool {
        value.count == 6 && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }
}

struct ThemeDiagnostic: Identifiable, Equatable {
    enum Severity { case warning, error }
    let id = UUID()
    let source: String
    let message: String
    let severity: Severity

    static func == (lhs: ThemeDiagnostic, rhs: ThemeDiagnostic) -> Bool {
        lhs.source == rhs.source && lhs.message == rhs.message && lhs.severity == rhs.severity
    }
}

struct ThemeCatalog {
    let themes: [AppTheme]
    let diagnostics: [ThemeDiagnostic]

    static func load(bundle: Bundle = .main, customDirectory: URL? = nil) -> ThemeCatalog {
        var themes = [AppTheme.graphite]
        var diagnostics: [ThemeDiagnostic] = []
        if let directory = bundle.url(forResource: "themes", withExtension: nil, subdirectory: "ghostty") {
            loadGhosttyThemes(at: directory, themes: &themes, diagnostics: &diagnostics)
        } else {
            diagnostics.append(.init(source: "Built-in themes", message: "The bundled Ghostty theme catalogue is unavailable.", severity: .error))
        }
        if let customDirectory { loadCustomThemes(at: customDirectory, themes: &themes, diagnostics: &diagnostics) }
        return ThemeCatalog(themes: themes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, diagnostics: diagnostics)
    }

    static func parseGhosttyTheme(named name: String, text: String) -> (AppTheme?, [ThemeDiagnostic]) {
        var foreground: String?, background: String?
        var extras: [String: String] = [:]
        var palette = Array<String?>(repeating: nil, count: 16)
        var diagnostics: [ThemeDiagnostic] = []
        let colourKeys: Set<String> = ["cursor-color", "cursor-text", "selection-background", "selection-foreground"]
        for (offset, rawLine) in text.split(whereSeparator: \Character.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else {
                diagnostics.append(.init(source: name, message: "Ignored malformed line \(offset + 1).", severity: .warning)); continue
            }
            let key = parts[0], value = parts[1]
            if key == "palette" {
                let pair = value.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2, let index = Int(pair[0]), palette.indices.contains(index), let hex = normalizedHex(pair[1]) else {
                    diagnostics.append(.init(source: name, message: "Ignored invalid palette colour on line \(offset + 1).", severity: .warning)); continue
                }
                palette[index] = hex
            } else if key == "foreground", let hex = normalizedHex(value) { foreground = hex }
            else if key == "background", let hex = normalizedHex(value) { background = hex }
            else if colourKeys.contains(key) {
                if let hex = normalizedHex(value) { extras[key] = hex }
                else { diagnostics.append(.init(source: name, message: "Ignored invalid \(key) colour on line \(offset + 1).", severity: .warning)) }
            } else {
                diagnostics.append(.init(source: name, message: "Ignored unsupported directive ‘\(key)’ on line \(offset + 1).", severity: .warning))
            }
        }
        guard let foreground, let background, palette.allSatisfy({ $0 != nil }) else {
            diagnostics.append(.init(source: name, message: "Theme requires foreground, background and all 16 palette colours.", severity: .error))
            return (nil, diagnostics)
        }
        let p = palette.map { $0! }
        let appearance: AppTheme.Appearance = luminance(background) > 0.55 ? .light : .dark
        let theme = AppTheme(
            id: "ghostty.\(name)", name: name, attribution: "Bundled Ghostty theme · \(name)", appearance: appearance,
            colors: .init(background: background, surface: mixed(background, foreground, amount: appearance == .dark ? 0.08 : 0.04),
                          text: foreground, secondary: mixed(foreground, background, amount: 0.35), accent: p[appearance == .dark ? 6 : 4],
                          border: mixed(background, foreground, amount: 0.18), terminalForeground: foreground,
                          terminalBackground: background, terminalPalette: p, terminalExtras: extras)
        )
        return (theme, diagnostics)
    }

    static var customThemesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Trellis", isDirectory: true)
            .appendingPathComponent("Themes", isDirectory: true)
    }

    static func readBounded(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 65537) <= 65536 else { throw ThemeError.invalid("Theme must be a regular file under 64 KB") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: 65537) ?? Data()
        guard data.count <= 65536 else { throw ThemeError.invalid("Theme exceeds 64 KB") }
        return data
    }

    static func saveCustom(_ theme: AppTheme, to directory: URL = customThemesDirectory) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = theme.id.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "-", options: .regularExpression)
        let url = directory.appendingPathComponent(safeName + ".json")
        try theme.exportedData().write(to: url, options: .atomic)
        return url
    }

    private static func loadGhosttyThemes(at directory: URL, themes: inout [AppTheme], diagnostics: inout [ThemeDiagnostic]) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
        for url in urls {
            guard let data = try? readBounded(url), data.count <= 64 * 1024, let text = String(data: data, encoding: .utf8) else {
                diagnostics.append(.init(source: url.lastPathComponent, message: "Theme is unreadable or exceeds 64 KB.", severity: .error)); continue
            }
            let parsed = parseGhosttyTheme(named: url.lastPathComponent, text: text)
            if let theme = parsed.0 { themes.append(theme) }
            diagnostics += parsed.1
        }
    }

    private static func loadCustomThemes(at directory: URL, themes: inout [AppTheme], diagnostics: inout [ThemeDiagnostic]) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in urls where url.pathExtension.lowercased() == "json" {
            do { themes.append(try AppTheme.importData(readBounded(url))) }
            catch { diagnostics.append(.init(source: url.lastPathComponent, message: error.localizedDescription, severity: .error)) }
        }
    }

    private static func normalizedHex(_ value: String) -> String? {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        return AppTheme.isHexColor(result) ? result.uppercased() : nil
    }

    private static func luminance(_ hex: String) -> Double {
        let values = stride(from: 0, to: 6, by: 2).map { Double(Int(hex.dropFirst($0).prefix(2), radix: 16) ?? 0) / 255 }
        return 0.2126 * values[0] + 0.7152 * values[1] + 0.0722 * values[2]
    }

    private static func mixed(_ first: String, _ second: String, amount: Double) -> String {
        let channels = stride(from: 0, to: 6, by: 2).map { offset -> Int in
            let a = Double(Int(first.dropFirst(offset).prefix(2), radix: 16) ?? 0)
            let b = Double(Int(second.dropFirst(offset).prefix(2), radix: 16) ?? 0)
            return Int((a + (b - a) * amount).rounded())
        }
        return channels.map { String(format: "%02X", $0) }.joined()
    }
}

struct ThemeSelection {
    static let defaultsKey = "selectedAppThemeID"
    static func load(from defaults: UserDefaults = .standard) -> String { defaults.string(forKey: defaultsKey) ?? AppTheme.graphite.id }
    static func save(_ id: String, to defaults: UserDefaults = .standard) { defaults.set(id, forKey: defaultsKey) }
}

enum ThemeError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}
