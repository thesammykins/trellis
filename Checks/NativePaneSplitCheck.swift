import AppKit
import SwiftUI

@main
enum NativePaneSplitCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        let workspaceID = UUID()
        let name = "TrellisPane-" + workspaceID.uuidString + "-fixture"
        let suite = "NativePaneSplitCheck-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let content = AnyView(Color.clear.frame(minWidth: 160, maxWidth: .infinity, minHeight: 100, maxHeight: .infinity))
        func makeWindow(width: CGFloat = 1_000, persistenceID: String? = nil) -> (NSWindow, NativePaneSplitView.Controller) {
            let controller = NativePaneSplitView.Controller(vertical: false, persistenceID: persistenceID ?? name, first: content, second: content, defaults: defaults)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = controller
            window.setContentSize(NSSize(width: width, height: 600))
            window.contentView?.layoutSubtreeIfNeeded()
            controller.restoreDividerPosition()
            controller.splitView.layoutSubtreeIfNeeded()
            return (window, controller)
        }

        let (firstWindow, first) = makeWindow()
        let firstHost = first.first
        let secondHost = first.second
        first.splitView.setPosition(320, ofDividerAt: 0)
        first.splitView.layoutSubtreeIfNeeded()
        let expected = first.splitView.arrangedSubviews[0].frame.width
        precondition(abs(expected - 320) < 2, "Native divider did not honor its requested position")
        first.saveDividerPosition()
        first.first.rootView = content
        first.second.rootView = content
        first.splitView.layoutSubtreeIfNeeded()
        precondition(first.first === firstHost && first.second === secondHost)
        precondition(abs(first.splitView.arrangedSubviews[0].frame.width - expected) < 2, "Content update reset divider geometry")

        let (restoredWindow, restored) = makeWindow()
        precondition(abs(restored.splitView.arrangedSubviews[0].frame.width - expected) < 2, "Saved native divider position was not restored")
        let (resizedWindow, resized) = makeWindow(width: 800)
        precondition(abs(resized.splitView.arrangedSubviews[0].frame.width / 799 - expected / 999) < 0.002,
            "Restoration should retain proportions in a different window size")
        resizedWindow.close()
        NativePaneSplitView.balance(in: restoredWindow.contentView, workspaceID: workspaceID)
        let widths = restored.splitView.arrangedSubviews.map(\.frame.width)
        precondition(abs(widths[0] - widths[1]) < 2, "Explicit balance did not center the native divider")
        let (balancedWindow, balanced) = makeWindow()
        let balancedWidths = balanced.splitView.arrangedSubviews.map(\.frame.width)
        precondition(abs(balancedWidths[0] - balancedWidths[1]) < 2, "Explicit balance was not persisted")
        let ratioKey = "paneDividerRatio.v1." + name
        for invalid: Any in ["invalid", -0.1, 0, 1, Double.infinity] {
            defaults.set(invalid, forKey: ratioKey)
            let (invalidWindow, invalidController) = makeWindow()
            let widths = invalidController.splitView.arrangedSubviews.map(\.frame.width)
            precondition(abs(widths[0] - widths[1]) < 2, "Invalid saved ratio must leave native layout intact")
            invalidWindow.close()
        }
        defaults.set(0.99, forKey: ratioKey)
        let (boundedWindow, bounded) = makeWindow()
        precondition(bounded.splitView.arrangedSubviews.allSatisfy { $0.frame.width >= 160 }, "Restore must honor minimum pane sizes")
        boundedWindow.close()
        let (otherWindow, other) = makeWindow(persistenceID: name + "-another-window")
        let otherWidths = other.splitView.arrangedSubviews.map(\.frame.width)
        precondition(abs(otherWidths[0] - otherWidths[1]) < 2, "Different pane/window identities must not share geometry")
        otherWindow.close()
        firstWindow.close()
        restoredWindow.close()
        balancedWindow.close()
        print("PASS native divider persistence/restore, stable hosts, update geometry, Balance, resized bounds, invalid ratios and identity isolation")
    }
}
