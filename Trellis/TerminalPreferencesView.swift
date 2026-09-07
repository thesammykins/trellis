import SwiftUI

struct TerminalPreferencesView: View {
    private let defaults: UserDefaults
    private let onChange: (TerminalPreferences) -> Void
    private let fonts: [String]
    @State private var preferences: TerminalPreferences
    @State private var error = ""

    init(defaults: UserDefaults = .standard, onChange: @escaping (TerminalPreferences) -> Void = { _ in }) {
        self.defaults = defaults
        self.onChange = onChange
        let loaded = TerminalPreferences.load(from: defaults)
        _preferences = State(initialValue: loaded)
        fonts = TerminalPreferences.installedMonospaceFamilies()
    }

    var body: some View {
        Form {
            Section("Text & Input") {
                Picker("Font", selection: binding(\.fontFamily)) {
                    if !fonts.contains(preferences.fontFamily) {
                        Text(preferences.fontFamily).tag(preferences.fontFamily)
                    }
                    ForEach(fonts, id: \.self) { Text($0).tag($0) }
                }
                Text("Installed fixed-pitch fonts are listed, including Nerd Fonts already on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Font size")
                    Spacer()
                    Stepper(value: binding(\.fontSize), in: 6...72, step: 1) {
                        Text(preferences.fontSize.formatted(.number.precision(.fractionLength(0))))
                    }
                    .accessibilityLabel("Font size")
                    .accessibilityValue("\(Int(preferences.fontSize)) points")
                }
                Picker("Fallback terminal theme", selection: binding(\.theme)) {
                    ForEach(TerminalPreferences.Theme.allCases) { theme in Text(theme.name).tag(theme) }
                }
                Text("App Themes overrides these fallback colours when a whole-app theme is selected.").font(.caption).foregroundStyle(.secondary)
                Toggle("Option acts as Alt", isOn: binding(\.optionAsAlt))
            }

            Section("Keybindings") {
                Text("Use Command shortcuts only. Standard editing, app, navigation and split shortcuts are reserved. See the menu bar or Help → Getting Started for shortcuts.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(preferences.keybindings.indices, id: \.self) { index in
                    HStack {
                        TextField("Shortcut", text: keybindingTrigger(index), prompt: Text("super+shift+f"))
                            .labelsHidden().accessibilityLabel("Keyboard shortcut")
                            .textFieldStyle(.roundedBorder)
                        Picker("Action", selection: keybindingAction(index)) {
                            ForEach(TerminalPreferences.Keybinding.Action.allCases) { action in
                                Text(action.name).tag(action)
                            }
                        }
                        .labelsHidden()
                        Button("Remove", role: .destructive) {
                            var copy = preferences
                            copy.keybindings.remove(at: index)
                            save(copy)
                        }
                    }
                }
                Button("Add Keybinding") {
                    guard let trigger = TerminalPreferences.nextAvailableTrigger(excluding: preferences.keybindings) else { return }
                    var copy = preferences
                    copy.keybindings.append(.init(trigger: trigger, action: .startSearch))
                    save(copy)
                }
                .disabled(preferences.keybindings.count >= 12 || TerminalPreferences.nextAvailableTrigger(excluding: preferences.keybindings) == nil)
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TerminalPreferences, Value>) -> Binding<Value> {
        Binding(get: { preferences[keyPath: keyPath] }, set: { value in
            var copy = preferences
            copy[keyPath: keyPath] = value
            save(copy)
        })
    }

    private func keybindingTrigger(_ index: Int) -> Binding<String> {
        Binding(get: { preferences.keybindings[index].trigger }, set: { value in
            var copy = preferences
            copy.keybindings[index].trigger = value
            save(copy)
        })
    }

    private func keybindingAction(_ index: Int) -> Binding<TerminalPreferences.Keybinding.Action> {
        Binding(get: { preferences.keybindings[index].action }, set: { value in
            var copy = preferences
            copy.keybindings[index].action = value
            save(copy)
        })
    }

    private func save(_ candidate: TerminalPreferences) {
        guard let validationError = candidate.validationError else {
            preferences = candidate
            error = ""
            candidate.save(to: defaults)
            onChange(candidate)
            return
        }
        preferences = candidate
        error = validationError
    }
}
