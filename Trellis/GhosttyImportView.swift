import SwiftUI
import UniformTypeIdentifiers

struct GhosttyImportView: View {
    private let baseline: TerminalPreferences
    private let baselineTheme: AppTheme?
    private let catalog: ThemeCatalog
    private let onApply: (TerminalPreferences, AppTheme?) throws -> Void
    @State private var choosesFile = false
    @State private var review: GhosttyImport.Review?
    @State private var error: String?
    @State private var applied = false

    init(
        baseline: TerminalPreferences = .load(),
        baselineTheme: AppTheme? = nil,
        catalog: ThemeCatalog = .load(customDirectory: ThemeCatalog.customThemesDirectory),
        onApply: @escaping (TerminalPreferences, AppTheme?) throws -> Void
    ) {
        self.baseline = baseline
        self.baselineTheme = baselineTheme
        self.catalog = catalog
        self.onApply = onApply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Import Ghostty Configuration").font(.title2)
                Spacer()
                Button("Choose File…") { choosesFile = true }
            }
            Text("Trellis reads one local file and shows every supported or skipped directive. It never follows includes, runs commands, or changes Ghostty.")
                .font(.callout).foregroundStyle(.secondary)

            Text("In the file chooser, press ⇧⌘G to enter ~/.config/ghostty/ or ~/Library/Application Support/com.mitchellh.ghostty/. Choose config or config.ghostty.").font(.caption).foregroundStyle(.secondary)

            if let review {
                List {
                    Section("Detected settings") {
                        if review.detected.isEmpty { Text("No supported settings found.").foregroundStyle(.secondary) }
                        ForEach(review.detected) { finding in row(finding) }
                    }
                    Section("Skipped") {
                        if review.skipped.isEmpty { Text("Nothing skipped.").foregroundStyle(.secondary) }
                        ForEach(review.skipped) { finding in row(finding) }
                    }
                }
                HStack {
                    Text(review.sourceName).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply") { apply(review) }.disabled(review.detected.isEmpty || applied)
                }
            } else {
                ContentUnavailableView("Choose a Ghostty config", systemImage: "doc.badge.plus", description: Text("Nothing changes until you review the result and click Apply."))
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if applied { Text("Imported settings applied.").foregroundStyle(.green) }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 520)
        .fileImporter(isPresented: $choosesFile, allowedContentTypes: [.plainText, .data], allowsMultipleSelection: false) { result in
            review = nil
            error = nil
            applied = false
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                review = try GhosttyImport.read(url, baseline: baseline, baselineTheme: baselineTheme, catalog: catalog)
            } catch let caught { error = caught.localizedDescription }
        }
    }

    @ViewBuilder private func row(_ finding: GhosttyImport.Finding) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Line \(finding.line)").monospacedDigit().foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
            Text(finding.key).font(.system(.body, design: .monospaced)).frame(width: 180, alignment: .leading)
            Text(finding.summary)
        }
    }

    private func apply(_ review: GhosttyImport.Review) {
        do {
            try onApply(review.preferences, review.appTheme)
            error = nil
            applied = true
        } catch let caught {
            error = caught.localizedDescription
            applied = false
        }
    }
}
