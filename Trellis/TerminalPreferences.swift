import AppKit
import Foundation

struct TerminalPreferences: Codable, Equatable {
    enum Theme: String, CaseIterable, Codable, Identifiable {
        case trellis
        case midnight
        case paper

        var id: String { rawValue }
        var name: String {
            switch self {
            case .trellis: "Trellis"
            case .midnight: "Midnight"
            case .paper: "Paper"
            }
        }

        var foreground: String {
            switch self {
            case .trellis: "dce5e3"
            case .midnight: "d6e2ff"
            case .paper: "24323a"
            }
        }

        var background: String {
            switch self {
            case .trellis: "101719"
            case .midnight: "0b1020"
            case .paper: "f4f7f5"
            }
        }
    }

    struct Keybinding: Codable, Equatable, Identifiable {
        enum Action: String, CaseIterable, Codable, Identifiable {
            case startSearch = "start_search"
            case endSearch = "end_search"
            case closeSurface = "close_surface"

            var id: String { rawValue }
            var name: String {
                switch self {
                case .startSearch: "Start Search"
                case .endSearch: "End Search"
                case .closeSurface: "Close Session"
                }
            }
        }

        var trigger: String
        var action: Action
        var id: String { trigger }
    }

    static let defaultsKey = "terminalPreferences"
    static let `default` = TerminalPreferences()
    static let reservedTriggers: Set<String> = ["super+t", "super+shift+t", "super+d", "super+shift+d", "super+w", "super+n", "super+o", "super+q", "super+c", "super+v", "super+x", "super+a", "super+z", "super+shift+z", "super+f", "super+ctrl+s", "super+alt+i", "super+p", "super+shift+a"]

    var fontFamily = "JetBrains Mono"
    var fontSize = 14.0
    var theme: Theme = .trellis
    var optionAsAlt = false
    var keybindings: [Keybinding] = []

    static func load(from defaults: UserDefaults = .standard) -> TerminalPreferences {
        guard let data = defaults.data(forKey: defaultsKey),
              var preferences = try? JSONDecoder().decode(TerminalPreferences.self, from: data) else { return .default }
        // Preserve fonts and colours when an older binding now conflicts with a
        // standard app command. The stored document is unchanged until Apply.
        preferences.keybindings.removeAll { binding in
            reservedTriggers.contains { canonicalTrigger($0) == canonicalTrigger(binding.trigger) }
        }
        return preferences.validationError == nil ? preferences : .default
    }

    func save(to defaults: UserDefaults = .standard) {
        guard validationError == nil, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    var validationError: String? {
        let family = fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !family.isEmpty, family.utf8.count <= 256, Self.isSingleConfigValue(family) else {
            return "Choose an installed font family."
        }
        guard fontSize.isFinite, (6...72).contains(fontSize) else {
            return "Font size must be between 6 and 72 points."
        }
        guard keybindings.count <= 12 else { return "Use at most 12 custom keybindings." }
        var triggers = Set<String>()
        for binding in keybindings {
            guard Self.isSupportedTrigger(binding.trigger) else {
                return "\(binding.trigger) is not a supported terminal shortcut."
            }
            guard !Self.reservedTriggers.contains(where: { Self.canonicalTrigger($0) == Self.canonicalTrigger(binding.trigger) }) else {
                return "\(binding.trigger) is reserved by a Trellis window command."
            }
            guard triggers.insert(Self.canonicalTrigger(binding.trigger)).inserted else {
                return "Each custom shortcut must be unique."
            }
        }
        return nil
    }

    func ghosttyConfiguration() throws -> String {
        if let validationError { throw ValidationError(message: validationError) }
        let family = Self.escapedConfigString(fontFamily.trimmingCharacters(in: .whitespacesAndNewlines))
        let size = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), fontSize)
        var lines = [
            "font-family = \"\(family)\"",
            "font-size = \(size)",
            "background = \(theme.background)",
            "foreground = \(theme.foreground)",
            "macos-option-as-alt = \(optionAsAlt ? "true" : "false")",
        ]
        if theme == .paper {
            // Dark ANSI colours keep coloured prompts readable on a light terminal.
            let palette = ["24323a", "9e2433", "286238", "866100", "24539e", "7542a6", "166e78", "59676f",
                           "55646d", "b02035", "277a3c", "8a6500", "2a5ec3", "8a3fa8", "007784", "24323a"]
            lines += palette.enumerated().map { "palette = \($0.offset)=\($0.element)" }
        }
        lines += keybindings.map { "keybind = \($0.trigger)=\($0.action.rawValue)" }
        return lines.joined(separator: "\n") + "\n"
    }

    static func installedMonospaceFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { family in
                NSFontManager.shared.availableMembers(ofFontFamily: family)?.contains { member in
                    guard let name = member[0] as? String else { return false }
                    return NSFont(name: name, size: 12)?.isFixedPitch == true
                } == true
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func nextAvailableTrigger(excluding bindings: [Keybinding]) -> String? {
        let unavailable = reservedTriggers.union(bindings.map { $0.trigger.lowercased() })
        return ["super+shift+f", "super+shift+g", "super+shift+h", "super+shift+j", "super+shift+k"]
            .first { !unavailable.contains($0) }
    }

    private static func canonicalTrigger(_ raw: String) -> String { raw.lowercased().split(separator: "+").sorted().joined(separator: "+") }

    private static func isSupportedTrigger(_ raw: String) -> Bool {
        guard raw == raw.lowercased() else { return false }
        let parts = raw.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard (1...5).contains(parts.count), parts.allSatisfy({ !$0.isEmpty }) else { return false }
        let modifiers: Set<String> = ["shift", "ctrl", "alt", "super", "caps"]
        let keys: Set<String> = Set("abcdefghijklmnopqrstuvwxyz".map(String.init))
            .union((0...9).map(String.init))
            .union((1...24).map { "f\($0)" })
            .union(["enter", "escape", "space", "tab", "up", "down", "left", "right"])
        let keyParts = parts.filter { !modifiers.contains($0) }
        return keyParts.count == 1 && keys.contains(keyParts[0]) &&
            Set(parts.filter { modifiers.contains($0) }).count == parts.filter { modifiers.contains($0) }.count &&
            parts.contains("super")
    }

    private static func isSingleConfigValue(_ value: String) -> Bool {
        !value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    private static func escapedConfigString(_ value: String) -> String {
        value.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
    }

    struct ValidationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
