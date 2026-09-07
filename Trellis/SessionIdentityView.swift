import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SessionIdentityIcon: View {
    let session: WorkspaceSession
    @ObservedObject var store: SessionIdentityStore

    var body: some View {
        let identity = store.identity(for: session.id)
        Group {
            if let data = identity.iconPNGData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let symbol = identity.iconSFsymbol {
                Image(systemName: symbol).resizable().scaledToFit().foregroundStyle(Color(hex: identity.accentHex) ?? .primary)
            } else {
                HarnessIcon(profile: session.profile)
            }
        }.frame(width: 18, height: 18).accessibilityHidden(true)
    }
}

struct SessionIdentityView: View {
    let session: WorkspaceSession
    @ObservedObject var store: SessionIdentityStore
    @Environment(\.dismiss) private var dismiss
    @State private var symbol = ""
    @State private var accent = Color.accentColor

    var body: some View {
        Form {
            Section("Icon") {
                TextField("SF Symbol", text: $symbol)
                HStack {
                    Button("Use SF Symbol") { _ = store.setSymbol(symbol, for: session.id) }
                    Button("Choose Image…", action: chooseImage)
                    Button("Reset", role: .destructive) { _ = store.reset(session.id); refresh() }
                }
                Text("Images are converted to a local 128-pixel PNG. SVG files are not accepted.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Accent") {
                ColorPicker("Session accent", selection: Binding(get: { accent }, set: { value in
                    accent = value
                    _ = store.setAccent(value.hexValue, for: session.id)
                }), supportsOpacity: false)
                Button("Clear accent") { _ = store.setAccent(nil, for: session.id); refresh() }
            }
            if let error = store.error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding()
        .frame(width: 440)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let identity = store.identity(for: session.id)
        symbol = identity.iconSFsymbol ?? ""
        accent = Color(hex: identity.accentHex) ?? .accentColor
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = store.importImage(from: url, for: session.id)
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(.sRGB, red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }

    var hexValue: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
}
