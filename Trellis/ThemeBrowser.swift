import AppKit
import SwiftUI

struct ThemeBrowser: View {
    let catalog: ThemeCatalog
    let onApply: (AppTheme, String) throws -> Void

    @State private var query = ""
    @State private var selectedID: String
    @State private var draft: AppTheme
    @State private var status = ""

    init(catalog: ThemeCatalog, onApply: @escaping (AppTheme, String) throws -> Void) {
        self.catalog = catalog
        self.onApply = onApply
        let selected = catalog.themes.first(where: { $0.id == ThemeSelection.load() }) ?? catalog.themes.first ?? .graphite
        _selectedID = State(initialValue: selected.id)
        _draft = State(initialValue: selected)
    }

    private var filteredThemes: [AppTheme] {
        query.isEmpty ? catalog.themes : catalog.themes.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Find a theme", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 8)
                List(filteredThemes, selection: $selectedID) { theme in
                    ThemePreview(theme: theme).tag(theme.id)
                }

                if !catalog.diagnostics.isEmpty {
                    DisclosureGroup("Import notes (\(catalog.diagnostics.count))") {
                        ForEach(catalog.diagnostics.prefix(20)) { diagnostic in
                            Text("\(diagnostic.source): \(diagnostic.message)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minWidth: 320, idealWidth: 420)

            VStack(spacing: 12) {
            Form {
                TextField("Name", text: $draft.name)
                Picker("Appearance", selection: $draft.appearance) { Text("Light").tag(AppTheme.Appearance.light); Text("Dark").tag(AppTheme.Appearance.dark) }
                ThemeColorField("Background", value: $draft.colors.background)
                ThemeColorField("Surface", value: $draft.colors.surface)
                ThemeColorField("Text", value: $draft.colors.text)
                ThemeColorField("Secondary", value: $draft.colors.secondary)
                ThemeColorField("Accent", value: $draft.colors.accent)
                ThemeColorField("Border", value: $draft.colors.border)
                ThemeColorField("Terminal foreground", value: $draft.colors.terminalForeground)
                ThemeColorField("Terminal background", value: $draft.colors.terminalBackground)
                DisclosureGroup("Terminal palette") {
                Grid(alignment: .leading) {
                    ForEach(0..<8, id: \.self) { row in
                        GridRow {
                            ForEach(0..<2, id: \.self) { column in
                                let index = row + column * 8
                                ThemeColorField("Palette \(index)", value: $draft.colors.terminalPalette[index])
                            }
                        }
                    }
                }
                }
                ThemePreview(theme: draft, detailed: true).frame(height: 160)
            }.formStyle(.grouped)
                if let error = draft.validationError { Text(error).foregroundStyle(.red).font(.caption) }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("Duplicate") { duplicate() }
                    Button("Import…") { importTheme() }
                    Button("Export…") { exportTheme() }
                    Spacer()
                    Button("Apply") { apply() }.buttonStyle(.borderedProminent).disabled(draft.validationError != nil)
                }
            }
            .padding(12)
            .frame(minWidth: 390, idealWidth: 520)
        }
        .frame(minWidth: 760, minHeight: 560)
        .onChange(of: selectedID) { _, id in if let theme = catalog.themes.first(where: { $0.id == id }) { draft = theme } }
    }

    private func duplicate() {
        draft.id = "custom.\(UUID().uuidString)"
        draft.name += " Copy"
        draft.attribution = "Custom theme based on \(draft.attribution)"
        selectedID = draft.id
    }

    private func apply() {
        do {
            if let original = catalog.themes.first(where: { $0.id == draft.id }), original != draft {
                draft.id = "custom.\(UUID().uuidString)"
            }
            if draft.id.hasPrefix("custom.") { _ = try ThemeCatalog.saveCustom(draft) }
            try onApply(draft, draft.ghosttyColorConfiguration())
            status = "Applied \(draft.name)."
        } catch { status = error.localizedDescription }
    }

    private func importTheme() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ThemeCatalog.readBounded(url)
            if url.pathExtension.lowercased() == "json" { draft = try AppTheme.importData(data) }
            else {
                guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                let (theme, notes) = ThemeCatalog.parseGhosttyTheme(named: url.deletingPathExtension().lastPathComponent, text: text)
                guard let theme else { status = notes.map(\.message).joined(separator: " "); return }
                draft = theme
                draft.attribution = "Imported Ghostty theme · " + url.lastPathComponent
                status = notes.map(\.message).joined(separator: " ")
            }
            draft.id = "custom.\(UUID().uuidString)"; selectedID = draft.id
            status = "Imported. Apply to save. " + status
        }
        catch { status = error.localizedDescription }
    }

    private func exportTheme() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "\(draft.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try draft.exportedData().write(to: url, options: .atomic); status = "Exported \(url.lastPathComponent)." }
        catch { status = error.localizedDescription }
    }
}

private struct ThemeColorField: View {
    let label: String
    @Binding var value: String
    init(_ label: String, value: Binding<String>) { self.label = label; _value = value }
    var body: some View { TextField(label, text: $value).textFieldStyle(.roundedBorder).fontDesign(.monospaced) }
}

private struct ThemePreview: View {
    let theme: AppTheme
    var detailed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(theme.name).font(.headline).foregroundStyle(color(theme.colors.text))
            Text(theme.attribution).lineLimit(1).font(.caption).foregroundStyle(color(theme.colors.secondary))
            HStack(spacing: 4) { ForEach(Array(theme.colors.terminalPalette.prefix(8).enumerated()), id: \.offset) { _, value in Circle().fill(color(value)).frame(width: 9, height: 9) } }
            if detailed {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Shell", systemImage: "terminal").foregroundStyle(color(theme.colors.accent))
                        Text("main · +12 −3").foregroundStyle(color(theme.colors.secondary))
                    }.font(.caption).padding(10).background(color(theme.colors.surface))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("~/project  ❯ git status")
                        Text("On branch main").foregroundStyle(color(theme.colors.terminalPalette[2]))
                    }.font(.system(.caption, design: .monospaced)).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(color(theme.colors.terminalForeground)).background(color(theme.colors.terminalBackground))
                }.clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color(theme.colors.background)).clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color(theme.colors.border)))
        .accessibilityElement(children: .combine).accessibilityLabel("\(theme.name), \(theme.appearance.rawValue) theme")
    }

    private func color(_ hex: String) -> Color {
        let value = UInt64(hex, radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
