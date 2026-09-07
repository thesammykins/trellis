import SwiftUI

/// macOS 27 hides menu images by default; these harness identities explicitly opt in.
struct HarnessMenu: NSViewRepresentable {
    let custom: [CustomHarness]
    let onAgent: (LaunchProfile) -> Void
    let onCustom: (CustomHarness) -> Void
    let onManage: () -> Void
    let onRemote: () -> Void
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("New Agent")
        button.toolTip = "Choose an agent harness"
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let menu = NSMenu(title: "New Agent")
        menu.addItem(withTitle: "New Agent", action: nil, keyEquivalent: "")
        for (index, profile) in Coordinator.profiles.enumerated() {
            let item = NSMenuItem(title: profile.title, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
            item.image = HarnessIcon.menuImage(profile, dark: scheme == .dark)
            item.preferredImageVisibility = .visible
            item.target = context.coordinator; item.tag = index
            menu.addItem(item)
        }
        if !custom.isEmpty { menu.addItem(.separator()) }
        for (index, harness) in custom.enumerated() {
            let item = NSMenuItem(title: harness.name, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
            item.preferredImageVisibility = .visible
            item.target = context.coordinator; item.tag = 100 + index
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (tag, title, symbol) in [(-1, "Manage Custom Agents…", "slider.horizontal.3"),
                                     (-2, "Persistent Local Shell (tmux)", "rectangle.split.2x1"),
                                     (-3, "SSH / tmux…", "network")] {
            let item = NSMenuItem(title: title, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
            item.preferredImageVisibility = .visible
            item.target = context.coordinator; item.tag = tag
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        button.menu = menu
    }
    @MainActor final class Coordinator: NSObject {
        static let profiles: [LaunchProfile] = [.codex, .opencode, .pi, .claude, .gemini]
        var parent: HarnessMenu
        init(_ parent: HarnessMenu) { self.parent = parent }
        @objc func choose(_ sender: NSMenuItem) {
            switch sender.tag {
            case -1: parent.onManage()
            case -2: parent.onAgent(.tmux)
            case -3: parent.onRemote()
            case 100...:
                let index = sender.tag - 100
                if parent.custom.indices.contains(index) { parent.onCustom(parent.custom[index]) }
            default:
                if Self.profiles.indices.contains(sender.tag) { parent.onAgent(Self.profiles[sender.tag]) }
            }
        }
    }
}
