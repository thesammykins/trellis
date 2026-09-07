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
        let open = NSMenuItem(title: "Open Agent…", action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
        open.target = context.coordinator; open.tag = -4
        menu.addItem(open)
        for (index, harness) in custom.enumerated() {
            let item = NSMenuItem(title: harness.name, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
            item.image = HarnessIcon.menuImage(harness.integration.flatMap(LaunchProfile.init(rawValue:)) ?? .custom, dark: scheme == .dark)
            item.preferredImageVisibility = .visible
            item.target = context.coordinator; item.tag = 100 + index
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (tag, title, symbol) in [(-1, "Manage Agents…", "slider.horizontal.3"),
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
        var parent: HarnessMenu
        init(_ parent: HarnessMenu) { self.parent = parent }
        @objc func choose(_ sender: NSMenuItem) {
            switch sender.tag {
            case -4: parent.onAgent(.custom)
            case -1: parent.onManage()
            case -2: parent.onAgent(.tmux)
            case -3: parent.onRemote()
            case 100...:
                let index = sender.tag - 100
                if parent.custom.indices.contains(index) { parent.onCustom(parent.custom[index]) }
            default: break
            }
        }
    }
}
