import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceAppearanceView: View {
    @ObservedObject var store: WorkspaceAppearanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var presetName = ""

    @State private var verticalDetails = false
    @State private var page = "Tabs"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Workspace Layout").font(.title2)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Changes apply immediately.").foregroundStyle(.secondary)
            Toggle("Override defaults for this project", isOn: Binding(get: { store.hasProjectOverride }, set: { enabled in perform { try store.setProjectOverride(enabled) } }))
            Picker("Layout settings", selection: $page) {
                Text("Tabs").tag("Tabs")
                Text("Sidebar").tag("Sidebar")
                Text("Presets").tag("Presets")
            }.pickerStyle(.segmented)
            Group {
                switch page {
                case "Sidebar": sidebarPage
                case "Presets": presetsPage
                default: tabsPage
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            Text("Preview · example labels").font(.caption).foregroundStyle(.secondary)
            Text(preview(verticalDetails ? store.preferences.verticalDetails : store.preferences.horizontalDetails))
                .font(.caption).lineLimit(2)
            Text("\(store.preferences.sidebarSections.map(\.title).joined(separator: " · ")) · Inspector \(store.preferences.inspectorSide.rawValue)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if let error = message ?? store.error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
        }.padding(20).frame(width: 600, height: 600)
    }

    private var tabsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Tab density", selection: binding(\.density)) {
                Text("Compact").tag(WorkspaceAppearance.Density.compact)
                Text("Comfortable").tag(WorkspaceAppearance.Density.comfortable)
            }
            HStack {
                Text("Vertical width")
                Slider(value: binding(\.verticalTabWidth), in: 160...360, step: 10)
                    .accessibilityLabel("Vertical tab width")
                Text("\(Int(store.preferences.verticalTabWidth)) pt").monospacedDigit().frame(width: 55)
            }
            Picker("Details for", selection: $verticalDetails) {
                Text("Horizontal tabs").tag(false)
                Text("Vertical tabs").tag(true)
            }.pickerStyle(.segmented)
            if verticalDetails { details("Vertical", keyPath: \.verticalDetails) }
            else { details("Horizontal", keyPath: \.horizontalDetails) }
            Spacer(minLength: 0)
        }.padding(16)
    }

    private var sidebarPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Inspector side", selection: binding(\.inspectorSide)) {
                Text("Left").tag(WorkspaceAppearance.InspectorSide.left)
                Text("Right").tag(WorkspaceAppearance.InspectorSide.right)
            }
            Text("Sidebar sections").font(.headline)
            ForEach(store.preferences.sidebarSections) { section in
                HStack {
                    Text(section.title)
                    Spacer()
                    moveButtons(section, title: "sidebar " + section.title, values: store.preferences.sidebarSections, keyPath: \.sidebarSections)
                    Button("Hide " + section.title) { edit { $0.sidebarSections.removeAll { $0 == section } } }
                }
            }
            ForEach(WorkspaceAppearance.SidebarSection.allCases.filter { !store.preferences.sidebarSections.contains($0) }) { section in
                Button("Show " + section.title) { edit { $0.sidebarSections.append(section) } }
                    .accessibilityLabel("Show sidebar " + section.title)
            }
            Spacer(minLength: 0)
        }.padding(16)
    }

    private var presetsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets contain layout settings only.").foregroundStyle(.secondary)
            HStack {
                TextField("Preset name", text: $presetName)
                Button("Save Preset") { perform { try store.savePreset(named: presetName) } }
            }
            Menu("Load Preset") {
                ForEach(store.savedPresets) { preset in
                    Button(preset.name) { perform { try store.update(preset.preferences) } }
                }
            }.disabled(store.savedPresets.isEmpty)
            HStack {
                Button("Import Preset…", action: importPreset)
                Button("Export Preset…", action: exportPreset)
            }
            Spacer(minLength: 0)
            Button("Reset Layout") { perform { try store.reset() } }
        }.padding(16)
    }
    private func details(_ title: String, keyPath: WritableKeyPath<WorkspaceAppearance, [WorkspaceAppearance.TabDetail]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
                ForEach(store.preferences[keyPath: keyPath]) { detail in
                    HStack {
                        Text(detail.title)
                        Spacer()
                        moveButtons(detail, title: title + " " + detail.title, values: store.preferences[keyPath: keyPath], keyPath: keyPath)
                        Button { edit { $0[keyPath: keyPath].removeAll { $0 == detail } } } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Hide " + title + " " + detail.title)
                    }
                }
                ForEach(WorkspaceAppearance.TabDetail.allCases.filter { !store.preferences[keyPath: keyPath].contains($0) }) { detail in
                    Button("Show " + detail.title) { edit { $0[keyPath: keyPath].append(detail) } }
                        .accessibilityLabel("Show " + title + " tab " + detail.title)
                }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func moveButtons<T: Equatable>(_ item: T, title: String, values: [T], keyPath: WritableKeyPath<WorkspaceAppearance, [T]>) -> some View {
        HStack(spacing: 3) {
            Button { move(item, offset: -1, keyPath: keyPath) } label: { Image(systemName: "arrow.up") }
                .disabled(values.first == item).accessibilityLabel("Move " + title + " earlier")
            Button { move(item, offset: 1, keyPath: keyPath) } label: { Image(systemName: "arrow.down") }
                .disabled(values.last == item).accessibilityLabel("Move " + title + " later")
        }
    }
    private func move<T: Equatable>(_ item: T, offset: Int, keyPath: WritableKeyPath<WorkspaceAppearance, [T]>) {
        edit { value in
            guard let index = value[keyPath: keyPath].firstIndex(of: item), value[keyPath: keyPath].indices.contains(index + offset) else { return }
            value[keyPath: keyPath].swapAt(index, index + offset)
        }
    }
    private func binding<T>(_ keyPath: WritableKeyPath<WorkspaceAppearance, T>) -> Binding<T> {
        Binding(get: { store.preferences[keyPath: keyPath] }, set: { newValue in edit { $0[keyPath: keyPath] = newValue } })
    }
    private func edit(_ change: (inout WorkspaceAppearance) -> Void) {
        var value = store.preferences
        change(&value)
        perform { try store.update(value) }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); message = nil } catch { message = error.localizedDescription }
    }
    private func preview(_ details: [WorkspaceAppearance.TabDetail]) -> String {
        details.map { detail in
            switch detail {
            case .folder: return "Project"
            case .branch: return "main"
            case .diff: return "+3 −1"
            case .host: return "Local"
            case .harness: return "Shell"
            case .configuredModel: return "Model if configured"
            }
        }.joined(separator: " · ")
    }
    private func exportPreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Trellis Layout.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try store.exportPreset().write(to: url, options: .atomic) }
    }
    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 16_384 else { throw AppearanceFailure("A layout preset must be under 16 KiB.") }
            try store.importPreset(Data(contentsOf: url))
        }
    }
}
