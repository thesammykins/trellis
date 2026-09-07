import Foundation

@main
enum TerminalPreferencesCheck {
    static func main() throws {
        let suite = "TerminalPreferencesCheck-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var preferences = TerminalPreferences.default
        preferences.fontFamily = "FiraCode Nerd Font Mono"
        preferences.fontSize = 15
        preferences.theme = .midnight
        preferences.optionAsAlt = true
        preferences.keybindings = [.init(trigger: "super+shift+f", action: .startSearch)]
        try expect(preferences.ghosttyConfiguration(), contains: [
            "font-family = \"FiraCode Nerd Font Mono\"",
            "font-size = 15.0",
            "background = 0b1020",
            "macos-option-as-alt = true",
            "keybind = super+shift+f=start_search",
        ])
        preferences.save(to: defaults)
        precondition(TerminalPreferences.load(from: defaults) == preferences)

        preferences.keybindings = [.init(trigger: "ctrl+x", action: .closeSurface)]
        precondition(preferences.validationError != nil)
        preferences.keybindings = [.init(trigger: "super+w", action: .closeSurface)]
        precondition(preferences.validationError != nil)
        for reserved in ["super+q", "super+v", "shift+super+t", "ctrl+super+s", "alt+super+i"] {
            preferences.keybindings = [.init(trigger: reserved, action: .closeSurface)]
            precondition(preferences.validationError != nil, "Accepted reserved shortcut " + reserved)
        }
        preferences.keybindings = [.init(trigger: "super+shift+f", action: .startSearch), .init(trigger: "shift+super+f", action: .endSearch)]
        precondition(preferences.validationError != nil, "Accepted equivalent duplicate shortcuts")
        preferences.keybindings = [.init(trigger: "super+shift+f", action: .startSearch)]
        precondition(TerminalPreferences.nextAvailableTrigger(excluding: preferences.keybindings) == "super+shift+g")
        preferences.keybindings = [.init(trigger: "super+q", action: .closeSurface)]
        defaults.set(try JSONEncoder().encode(preferences), forKey: TerminalPreferences.defaultsKey)
        let migrated = TerminalPreferences.load(from: defaults)
        precondition(migrated.fontFamily == preferences.fontFamily && migrated.fontSize == preferences.fontSize && migrated.keybindings.isEmpty)
        print("PASS terminal preferences config, persistence and supported keybinding validation")
    }

    private static func expect(_ value: String, contains expected: [String]) throws {
        for item in expected where !value.contains(item) { throw CheckError.missing(item) }
    }

    enum CheckError: Error { case missing(String) }
}
