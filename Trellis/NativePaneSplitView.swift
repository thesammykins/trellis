import SwiftUI

/// AppKit owns divider geometry; the SwiftUI children still use session-owned terminal surfaces.
struct NativePaneSplitView: NSViewControllerRepresentable {
    let vertical: Bool
    let persistenceID: String
    let first: AnyView
    let second: AnyView

    func makeNSViewController(context: Context) -> Controller {
        Controller(vertical: vertical, persistenceID: persistenceID, first: first, second: second)
    }

    func updateNSViewController(_ controller: Controller, context: Context) {
        // View updates must never reset a user's divider position or replace the hosting controllers.
        controller.first.rootView = first
        controller.second.rootView = second
    }

    @MainActor
    static func balance(in view: NSView?, workspaceID: UUID) {
        guard let view else { return }
        view.layoutSubtreeIfNeeded()
        if let split = view as? NSSplitView,
           split.identifier?.rawValue.hasPrefix("TrellisPane-" + workspaceID.uuidString + "-") == true,
           split.arrangedSubviews.count == 2 {
            let length = split.isVertical ? split.bounds.width : split.bounds.height
            if length > split.dividerThickness {
                split.setPosition((length - split.dividerThickness) / 2, ofDividerAt: 0)
                split.layoutSubtreeIfNeeded()
                (split as? DividerView)?.onUserResize?()
            }
        }
        for child in view.subviews { balance(in: child, workspaceID: workspaceID) }
    }

    @MainActor
    final class Controller: NSSplitViewController {
        let first: NSHostingController<AnyView>
        let second: NSHostingController<AnyView>
        private let defaults: UserDefaults
        private let persistenceKey: String
        private var pendingFraction: CGFloat?

        init(vertical: Bool, persistenceID: String, first: AnyView, second: AnyView, defaults: UserDefaults = .standard) {
            self.first = NSHostingController(rootView: first)
            self.second = NSHostingController(rootView: second)
            self.defaults = defaults
            persistenceKey = "paneDividerRatio.v1." + persistenceID
            if let fraction = defaults.object(forKey: persistenceKey) as? Double,
               fraction.isFinite, fraction > 0, fraction < 1 {
                pendingFraction = fraction
            }
            super.init(nibName: nil, bundle: nil)
            let divider = DividerView()
            splitView = divider
            divider.onUserResize = { [weak self] in self?.saveDividerPosition() }
            // PaneLayout's vertical flag describes stacked rows; NSSplitView describes its divider.
            splitView.isVertical = !vertical
            splitView.dividerStyle = .thin
            for child in [self.first, self.second] {
                let item = NSSplitViewItem(viewController: child)
                item.minimumThickness = vertical ? 100 : 160
                item.canCollapse = false
                addSplitViewItem(item)
            }
            splitView.identifier = NSUserInterfaceItemIdentifier(persistenceID)
        }

        override func viewDidLayout() {
            super.viewDidLayout()
            restoreDividerPosition()
        }

        func restoreDividerPosition() {
            guard let fraction = pendingFraction, splitView.window != nil,
                  splitView.arrangedSubviews.count == 2 else { return }
            let length = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            // Wait past the hosting controller's initial minimum-sized frame before applying saved proportions.
            let minimum = splitViewItems.reduce(0) { $0 + $1.minimumThickness } + splitView.dividerThickness
            guard length > minimum else { return }
            pendingFraction = nil
            let position = (length - splitView.dividerThickness) * fraction
            splitView.setPosition(min(max(position, splitView.minPossiblePositionOfDivider(at: 0)),
                                      splitView.maxPossiblePositionOfDivider(at: 0)), ofDividerAt: 0)
        }

        func saveDividerPosition() {
            guard splitView.arrangedSubviews.count == 2 else { return }
            let length = (splitView.isVertical ? splitView.bounds.width : splitView.bounds.height) - splitView.dividerThickness
            let firstLength = splitView.isVertical ? first.view.frame.width : first.view.frame.height
            let fraction = firstLength / length
            guard fraction.isFinite, fraction > 0, fraction < 1 else { return }
            pendingFraction = nil
            defaults.set(Double(fraction), forKey: persistenceKey)
        }

        required init?(coder: NSCoder) { fatalError("Storyboard initialization is unsupported") }
    }

    @MainActor
    final class DividerView: NSSplitView {
        var onUserResize: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            let previous = arrangedSubviews.first?.frame
            super.mouseDown(with: event)
            if previous != arrangedSubviews.first?.frame { onUserResize?() }
        }
    }
}
