import AppKit
import SwiftUI

@MainActor
struct CustomHarnessView: View {
    let store: CustomHarnessStore
    let onLaunch: (CustomHarness) -> Void
    let onChange: ([CustomHarness]) -> Void

    @State private var profiles: [CustomHarness] = []
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
            List(profiles, selection: $selection) { profile in
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                    Text(profile.executable).font(.caption.monospaced()).foregroundStyle(.secondary)
                }.tag(profile.id)
            }
            .frame(minHeight: 220)

            HStack {
                Button("Add") { editor = Draft() }
                Button("Edit") {
                    if let profile = selectedProfile { editor = Draft(profile) }
                }.disabled(selectedProfile == nil)
                Button("Remove", role: .destructive) { removeSelected() }.disabled(selectedProfile == nil)
                Spacer()
                Button("Import…") { importProfile() }
                Button("Export…") { exportSelected() }.disabled(selectedProfile == nil)
                Button("Launch") { if let profile = selectedProfile { onLaunch(profile) } }
                    .buttonStyle(.borderedProminent).disabled(selectedProfile == nil)
            }
            Text("Trellis passes the executable and each argument directly. Profiles have no environment fields. Check arguments for secrets before exporting.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 360)
        .task { reload() }
        .sheet(item: $editor) { draft in
            CustomHarnessEditor(draft: draft) { profile in
                save(profile)
                editor = nil
            } onCancel: { editor = nil }
        }
        .sheet(item: $imported) { profile in
            VStack(alignment: .leading, spacing: 14) {
                Text("Review Imported Harness").font(.title2)
                HarnessReview(profile: profile)
                Text("Importing saves this profile. It does not launch it.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { imported = nil }
                    Button("Save Import") { save(profile); imported = nil }.buttonStyle(.borderedProminent)
                }
            }.padding().frame(width: 540)
        }
        .alert("Custom Harness", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    private var selectedProfile: CustomHarness? { profiles.first { $0.id == selection } }

    private func reload() {
        do { profiles = try store.load() }
        catch { errorMessage = error.localizedDescription }
    }

    private func save(_ profile: CustomHarness) {
        var updated = profiles.filter { $0.id != profile.id }
        updated.append(profile)
        updated.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist(updated, selecting: profile.id)
    }

    private func removeSelected() {
        guard let selection else { return }
        persist(profiles.filter { $0.id != selection }, selecting: nil)
    }

    private func persist(_ updated: [CustomHarness], selecting id: UUID?) {
        do {
            try store.save(updated)
            profiles = updated
            selection = id
            onChange(updated)
        } catch { errorMessage = error.localizedDescription }
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
    let onSave: (CustomHarness) -> Void
    let onCancel: () -> Void
    @State private var review: CustomHarness?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            TextField("Name", text: $draft.name)
            TextField("Executable", text: $draft.executable)
                .font(.body.monospaced())
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
                Text("Review Harness").font(.title2)
                HarnessReview(profile: profile)
                HStack {
                    Spacer()
                    Button("Back") { review = nil }
                    Button("Save") { onSave(profile) }.buttonStyle(.borderedProminent)
                }
            }.padding().frame(width: 540)
        }
        .alert("Invalid Harness", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
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

    init() {
        id = UUID()
        name = ""
        executable = ""
        arguments = []
    }

    init(_ profile: CustomHarness) {
        id = profile.id
        name = profile.name
        executable = profile.executable
        arguments = profile.arguments
    }

    func profile() throws -> CustomHarness {
        try CustomHarness(id: id, name: name, executable: executable, arguments: arguments)
    }
}
