import Darwin
import Foundation

struct GhosttyImport {
    static let maximumBytes = 64 * 1024

    struct Finding: Identifiable, Equatable {
        let line: Int
        let key: String
        let summary: String
        var id: String { "\(line):\(key):\(summary)" }
    }

    struct Review: Equatable {
        let sourceName: String
        let preferences: TerminalPreferences
        let appTheme: AppTheme?
        let detected: [Finding]
        let skipped: [Finding]
    }

    static func read(
        _ url: URL,
        baseline: TerminalPreferences,
        baselineTheme: AppTheme?,
        catalog: ThemeCatalog
    ) throws -> Review {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure("The Ghostty configuration could not be opened safely.") }
        defer { close(descriptor) }
        var information = stat()
        guard fstat(descriptor, &information) == 0, (information.st_mode & S_IFMT) == S_IFREG else {
            throw Failure("Choose a regular Ghostty configuration file.")
        }
        guard information.st_size >= 0, information.st_size <= maximumBytes else {
            throw Failure("Ghostty configuration files may not exceed 64 KB.")
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= maximumBytes {
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, maximumBytes + 1 - data.count))
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw Failure("The Ghostty configuration could not be read.") }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        guard data.count <= maximumBytes else { throw Failure("Ghostty configuration files may not exceed 64 KB.") }
        guard let text = String(data: data, encoding: .utf8) else { throw Failure("The Ghostty configuration must be UTF-8 text.") }
        return try parse(text, sourceName: url.lastPathComponent, baseline: baseline, baselineTheme: baselineTheme, catalog: catalog)
    }

    static func parse(
        _ text: String,
        sourceName: String = "Ghostty config",
        baseline: TerminalPreferences,
        baselineTheme: AppTheme?,
        catalog: ThemeCatalog
    ) throws -> Review {
        guard text.utf8.count <= maximumBytes else { throw Failure("Ghostty configuration files may not exceed 64 KB.") }
        let safeSourceName = displayText(sourceName, limit: 128)
        var preferences = baseline
        var selectedTheme: AppTheme?
        var colourOverrides: [(String, String)] = []
        var paletteOverrides: [Int: String] = [:]
        var importedFont = false
        var detected: [Finding] = []
        var skipped: [Finding] = []

        for (offset, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else {
                skipped.append(.init(line: lineNumber, key: "malformed", summary: "No key/value separator."))
                continue
            }
            let rawKey = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            let key = displayKey(rawKey)
            let value = unquoted(pair[1].trimmingCharacters(in: .whitespaces))
            guard !key.isEmpty else {
                skipped.append(.init(line: lineNumber, key: "malformed", summary: "The directive has no key."))
                continue
            }

            switch key {
            case "font-family":
                if value.isEmpty {
                    importedFont = false
                    preferences.fontFamily = baseline.fontFamily
                    skipped.append(invalid(lineNumber, key, "Font fallback reset is unnecessary in Trellis."))
                    continue
                }
                guard !importedFont else {
                    skipped.append(invalid(lineNumber, key, "Additional Ghostty font fallbacks are not supported."))
                    continue
                }
                var candidate = preferences
                candidate.fontFamily = value
                if candidate.validationError == nil {
                    preferences = candidate
                    importedFont = true
                    detected.append(.init(line: lineNumber, key: key, summary: "Font family: \(value)"))
                } else { skipped.append(invalid(lineNumber, key, "Invalid or unsafe font family.")) }
            case "font-size":
                var candidate = preferences
                candidate.fontSize = Double(value) ?? .nan
                if candidate.validationError == nil {
                    preferences = candidate
                    detected.append(.init(line: lineNumber, key: key, summary: "Font size \(value)"))
                } else { skipped.append(invalid(lineNumber, key, "Font size must be between 6 and 72 points.")) }
            case "macos-option-as-alt":
                guard value == "true" || value == "false" else {
                    skipped.append(invalid(lineNumber, key, "Trellis supports only true or false.")); continue
                }
                preferences.optionAsAlt = value == "true"
                detected.append(.init(line: lineNumber, key: key, summary: "Option as Alt: \(value)"))
            case "keybind":
                let binding = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard binding.count == 2,
                      let action = TerminalPreferences.Keybinding.Action(rawValue: String(binding[1]).trimmingCharacters(in: .whitespaces)) else {
                    skipped.append(invalid(lineNumber, key, "Only Trellis search and close-session actions are supported.")); continue
                }
                let item = TerminalPreferences.Keybinding(trigger: String(binding[0]).trimmingCharacters(in: .whitespaces), action: action)
                var candidate = preferences
                candidate.keybindings.removeAll { $0.trigger.lowercased() == item.trigger.lowercased() }
                candidate.keybindings.append(item)
                guard candidate.validationError == nil else {
                    skipped.append(invalid(lineNumber, key, "Shortcut is unsupported, reserved, duplicated, or exceeds the import limit.")); continue
                }
                preferences = candidate
                detected.append(.init(line: lineNumber, key: key, summary: "\(item.trigger) → \(action.name)"))
            case "theme":
                guard let theme = catalog.themes.first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) else {
                    skipped.append(invalid(lineNumber, key, "Theme is not in the bundled Trellis catalogue.")); continue
                }
                selectedTheme = theme
                detected.append(.init(line: lineNumber, key: key, summary: "Theme: \(theme.name)"))
            case "foreground", "background", "cursor-color", "cursor-text", "selection-background", "selection-foreground":
                guard let hex = normalizedHex(value) else {
                    skipped.append(invalid(lineNumber, key, "Colour must use six hexadecimal digits.")); continue
                }
                colourOverrides.append((key, hex))
                detected.append(.init(line: lineNumber, key: key, summary: "Colour override"))
            case "palette":
                let entry = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard entry.count == 2, let index = Int(entry[0].trimmingCharacters(in: .whitespaces)),
                      (0..<16).contains(index), let hex = normalizedHex(String(entry[1])) else {
                    skipped.append(invalid(lineNumber, key, "Palette entry must be an index from 0 to 15 and a six-digit colour.")); continue
                }
                paletteOverrides[index] = hex
                detected.append(.init(line: lineNumber, key: key, summary: "Palette colour \(index)"))
            case "command":
                skipped.append(.init(line: lineNumber, key: key, summary: "Commands are never imported or executed."))
            case "config-file", "config-default-files":
                skipped.append(.init(line: lineNumber, key: key, summary: "Included configuration files are never read."))
            default:
                skipped.append(.init(line: lineNumber, key: key, summary: "Unsupported Ghostty directive."))
            }
        }

        if let validationError = preferences.validationError { throw Failure(validationError) }
        let importedTheme: AppTheme?
        if !colourOverrides.isEmpty || !paletteOverrides.isEmpty {
            var colourBase = selectedTheme ?? baselineTheme ?? AppTheme.graphite
            for (key, hex) in colourOverrides { applyColour(hex, key: key, to: &colourBase) }
            for (index, hex) in paletteOverrides { colourBase.colors.terminalPalette[index] = hex }
            colourBase.id = "ghostty.import"
            colourBase.name = "Ghostty Import"
            colourBase.attribution = "Imported locally from \(safeSourceName)"
            guard colourBase.validationError == nil else { throw Failure("The imported colour settings do not form a valid theme.") }
            importedTheme = colourBase
        } else {
            importedTheme = selectedTheme
        }
        return Review(sourceName: safeSourceName, preferences: preferences, appTheme: importedTheme, detected: detected, skipped: skipped)
    }

    private static func invalid(_ line: Int, _ key: String, _ summary: String) -> Finding {
        Finding(line: line, key: key, summary: summary)
    }

    private static func displayKey(_ key: String) -> String {
        displayText(key, limit: 80)
    }

    private static func displayText(_ value: String, limit: Int) -> String {
        let printable = value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? "�" : String($0) }.joined()
        return String(printable.prefix(limit))
    }

    private static func normalizedHex(_ value: String) -> String? {
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, hex.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else { return nil }
        return hex.uppercased()
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        return String(value.dropFirst().dropLast())
    }

    private static func applyColour(_ hex: String, key: String, to theme: inout AppTheme) {
        switch key {
        case "foreground": theme.colors.terminalForeground = hex
        case "background": theme.colors.terminalBackground = hex
        default:
            var extras = theme.colors.terminalExtras ?? [:]
            extras[key] = hex
            theme.colors.terminalExtras = extras
        }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
