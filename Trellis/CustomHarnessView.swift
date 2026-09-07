import AppKit
import SwiftUI

@MainActor
struct CustomHarnessView: View {
    let store: CustomHarnessStore
    let onLaunch: (CustomHarness) -> Void
    let onChange: ([CustomHarness]) -> Void

    @State private var profiles: [CustomHarness] = []
    @State private var detected: [CustomHarness] = []
    @State private var selection: UUID?
    @State private var editor: Draft?
    @State private var imported: CustomHarness?
    @State private var errorMessage: String?

    init(
        store: CustomHarnessStore,
        onLaunch: @escaping (CustomHarness) -> Void,
        onChange: @escaping ([CustomHarness]) -> Void = { _ in }
    ) {
        self.store = store
        self.onLaunch = onLaunch
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(selection: $selection) {
                Section("My Agents") {
                    if profiles.isEmpty {
                        Text("Add a detected agent below, or choose Add Other.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(profiles) { profile in
                        profileLabel(profile).tag(profile.id)
                    }
                }
                Section("Detected on This Mac") {
                    if detected.isEmpty {
                        Text("No additional agents found. Add Other accepts any executable.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(detected) { profile in
                        Button {
                            do { try save(profile) }
                            catch { errorMessage = error.localizedDescription }
                        } label: {
                            HStack {
                                profileLabel(profile)
                                Spacer()
                                Label("Add", systemImage: "plus").foregroundStyle(Color.accentColor)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Add \(profile.name)")
                    }
                }
            }
            .frame(minHeight: 280)

            HStack {
                Button("Add Other…") { editor = Draft() }
                Button("Edit") {
                    if let profile = selectedProfile { editor = Draft(profile) }
                }.disabled(selectedProfile == nil)
                Button("Remove", role: .destructive) { removeSelected() }.disabled(selectedProfile == nil)
                Spacer()
                Button("Launch…") { if let profile = selectedProfile { onLaunch(profile) } }
                    .buttonStyle(.borderedProminent).disabled(selectedProfile == nil)
            }
            HStack {
                Button("Import…") { importProfile() }
                Button("Export…") { exportSelected() }.disabled(selectedProfile == nil)
                Spacer()
                Button("Rescan", systemImage: "arrow.clockwise") { reload() }
            }
            Text("Detection checks executable paths without running agents.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Trellis passes the executable and each argument directly. Profiles have no environment fields. Check arguments for secrets before exporting.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 560, idealWidth: 660, minHeight: 440)
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: CustomHarnessStore.didChange)) { _ in reload() }
        .sheet(item: $editor) { draft in
            CustomHarnessEditor(draft: draft) { profile in
                try save(profile)
                editor = nil
            } onCancel: { editor = nil }
        }
        .sheet(item: $imported) { profile in
            VStack(alignment: .leading, spacing: 14) {
                Text("Review Imported Agent").font(.title2)
                ScrollView { HarnessReview(profile: profile) }.frame(maxHeight: 320)
                Text("Importing saves this profile. It does not launch it.")
                    .font(.caption).foregroundStyle(.secondary)
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Spacer()
                    Button("Cancel") { imported = nil }
                    Button("Save Import") {
                        do { try save(profile); imported = nil }
                        catch { errorMessage = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding().frame(width: 540)
        }
        .alert("Agent Catalog", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    private var selectedProfile: CustomHarness? { profiles.first { $0.id == selection } }

    private func profileLabel(_ profile: CustomHarness) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(profile.name).lineLimit(1)
            Text(profile.executable).font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }.help(profile.executable)
    }

    private func reload() {
        do {
            profiles = try store.load()
            if !profiles.contains(where: { $0.id == selection }) { selection = nil }
            detected = HarnessDiscovery.discover(searchPath: HarnessDiscovery.searchPath, excluding: profiles)
            errorMessage = nil
            onChange(profiles)
        }
        catch { errorMessage = error.localizedDescription }
    }

    private func save(_ profile: CustomHarness) throws {
        var updated = try store.load().filter { $0.id != profile.id }
        updated.append(profile)
        updated.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try persist(updated, selecting: profile.id)
    }

    private func removeSelected() {
        guard let selection else { return }
        do { try persist(try store.load().filter { $0.id != selection }, selecting: nil) }
        catch { errorMessage = error.localizedDescription }
    }

    private func persist(_ updated: [CustomHarness], selecting id: UUID?) throws {
        try store.save(updated)
        profiles = updated
        selection = id
        detected = HarnessDiscovery.discover(searchPath: HarnessDiscovery.searchPath, excluding: profiles)
        errorMessage = nil
        onChange(updated)
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let data = try file.read(upToCount: 1_048_577) ?? Data()
            imported = try store.importPreview(from: data)
        }
        catch { errorMessage = error.localizedDescription }
    }

    private func exportSelected() {
        guard let profile = selectedProfile else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.name).trellis-harness.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportData(profile).write(to: url, options: .atomic) }
        catch { errorMessage = error.localizedDescription }
    }
}

@MainActor
private struct CustomHarnessEditor: View {
    @State var draft: Draft
    let onSave: (CustomHarness) throws -> Void
    let onCancel: () -> Void
    @State private var review: CustomHarness?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Name", text: $draft.name)
            HStack {
                TextField("Executable", text: $draft.executable)
                    .font(.body.monospaced())
                Button("Choose…") { chooseExecutable() }
                    .accessibilityLabel("Choose agent executable")
            }
            Picker("Integration", selection: $draft.integration) {
                Text("None").tag("")
                ForEach([LaunchProfile.codex, .opencode, .pi, .claude, .gemini]) { profile in
                    Text(profile.title).tag(profile.rawValue)
                }
            }
            Text("Select the CLI this executable runs to enable its supported model, history and memory options.")
                .font(.caption).foregroundStyle(.secondary)
            Section("Arguments") {
                ForEach(draft.arguments.indices, id: \.self) { index in
                    HStack {
                        TextField("Argument \(index + 1)", text: $draft.arguments[index])
                            .font(.body.monospaced())
                        Button("Remove", systemImage: "minus.circle") { draft.arguments.remove(at: index) }
                            .labelStyle(.iconOnly)
                    }
                }
                Button("Add Argument", systemImage: "plus") { draft.arguments.append("") }
                    .disabled(draft.arguments.count >= CustomHarness.maximumArguments)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Review Changes") {
                    do { review = try draft.profile() }
                    catch { errorMessage = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped).padding().frame(width: 620, height: 480)
        .sheet(item: $review) { profile in
            VStack(alignment: .leading, spacing: 14) {
                Text("Review Agent").font(.title2)
                ScrollView { HarnessReview(profile: profile) }.frame(maxHeight: 320)
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Spacer()
                    Button("Back") { review = nil }
                    Button("Save") {
                        do { try onSave(profile) }
                        catch { errorMessage = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                }
            }.padding().frame(width: 540)
        }
        .alert("Agent Settings", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.executable = url.standardizedFileURL.path
        if draft.name.isEmpty { draft.name = url.lastPathComponent }
    }
}

@MainActor
private struct HarnessReview: View {
    let profile: CustomHarness
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow { Text("Name").foregroundStyle(.secondary); Text(profile.name) }
            GridRow { Text("Executable").foregroundStyle(.secondary); Text(profile.executable).font(.body.monospaced()) }
            GridRow {
                Text("Integration").foregroundStyle(.secondary)
                Text(profile.integration.flatMap(LaunchProfile.init(rawValue:))?.title ?? "None")
            }
            GridRow {
                Text("Arguments").foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    if profile.arguments.isEmpty { Text("None").foregroundStyle(.secondary) }
                    ForEach(Array(profile.arguments.enumerated()), id: \.offset) { index, argument in
                        Text("[\(index)] \(argument)").font(.body.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
    }
}

private struct Draft: Identifiable {
    let id: UUID
    var name: String
    var executable: String
    var arguments: [String]
    var integration: String

    init() {
        id = UUID()
        name = ""
        executable = ""
        arguments = []
        integration = ""
    }

    init(_ profile: CustomHarness) {
        id = profile.id
        name = profile.name
        executable = profile.executable
        arguments = profile.arguments
        integration = profile.integration ?? ""
    }

    func profile() throws -> CustomHarness {
        try CustomHarness(id: id, name: name, executable: executable, arguments: arguments,
                          integration: integration.isEmpty ? nil : integration)
    }
}
