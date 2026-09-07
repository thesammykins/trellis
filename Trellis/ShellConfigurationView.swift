import SwiftUI

struct ShellConfigurationView: View {
    private let defaults: UserDefaults
    private let onChange: (ShellConfiguration) -> Void
    private let shells: [String]
    @State private var configuration: ShellConfiguration
    @State private var error = ""

    init(defaults: UserDefaults = .standard, onChange: @escaping (ShellConfiguration) -> Void = { _ in }) {
        self.defaults = defaults
        self.onChange = onChange
        _configuration = State(initialValue: ShellConfiguration.load(from: defaults))
        shells = ShellConfiguration.installedShells()
    }

    var body: some View {
        Form {
            Section("New Shells") {
                Picker("Installed shell", selection: installedShellBinding) {
                    if !shells.contains(configuration.executable) {
                        Text(configuration.executable).tag(configuration.executable)
                    }
                    ForEach(shells, id: \.self) { shell in Text(shell).tag(shell) }
                }
                TextField("Custom executable", text: binding(\.executable))
                    .textFieldStyle(.roundedBorder)
                Text("Choose an installed shell or enter its absolute executable path. Trellis does not install shells, change your login shell, or alter shell configuration.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Arguments") {
                if configuration.arguments.isEmpty {
                    Text("No arguments").foregroundStyle(.secondary)
                }
                ForEach(configuration.arguments.indices, id: \.self) { index in
                    HStack {
                        TextField("Argument \(index + 1)", text: argumentBinding(index))
                            .textFieldStyle(.roundedBorder)
                        Button("Remove", role: .destructive) {
                            var copy = configuration
                            copy.arguments.remove(at: index)
                            save(copy)
                        }
                    }
                }
                Button("Add Argument") {
                    var copy = configuration
                    copy.arguments.append("")
                    save(copy)
                }
                .disabled(configuration.arguments.count >= ShellConfiguration.maximumArguments)
                Text("Arguments are passed directly to the executable. Login arguments are preset only for shells whose installed documentation supports them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Applies to new shells and new split panes. Existing sessions retain their own shell snapshot.")
                .font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity)
    }

    private var installedShellBinding: Binding<String> {
        Binding(get: { configuration.executable }, set: { executable in
            var copy = configuration
            copy.executable = executable
            copy.arguments = ShellConfiguration.loginPresetArguments(for: executable) ?? []
            save(copy)
        })
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ShellConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in
            var copy = configuration
            copy[keyPath: keyPath] = value
            save(copy)
        })
    }

    private func argumentBinding(_ index: Int) -> Binding<String> {
        Binding(get: { configuration.arguments[index] }, set: { value in
            var copy = configuration
            copy.arguments[index] = value
            save(copy)
        })
    }

    private func save(_ candidate: ShellConfiguration) {
        configuration = candidate
        guard let validationError = candidate.validationError else {
            error = ""
            candidate.save(to: defaults)
            onChange(candidate)
            return
        }
        error = validationError
    }
}
