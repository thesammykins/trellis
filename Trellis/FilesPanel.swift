import AppKit
import SwiftUI

struct FilesPanel: View {
    let rootURL: URL?
    let locationLabel: String
    let unavailableReason: String?
    var onAskAgent: ((URL) -> Void)? = nil
    @State private var refreshID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Files").font(.headline)
                    if let rootURL {
                        Text(locationLabel + " · " + rootURL.path)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .help(rootURL.path)
                    }
                }
                Spacer()
                Button("Refresh files", systemImage: "arrow.clockwise") { refreshID = UUID() }
                    .labelStyle(.iconOnly).disabled(rootURL == nil)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)

            if let rootURL {
                FilesOutline(rootURL: rootURL.standardizedFileURL, refreshID: refreshID, onAskAgent: onAskAgent)
            } else {
                ContentUnavailableView(
                    "Files unavailable",
                    systemImage: "folder.badge.questionmark",
                    description: Text(unavailableReason ?? "The active session has no local folder to browse.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if rootURL != nil { refreshID = UUID() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Files, " + locationLabel)
    }
}

struct FilesEntry: Sendable, Equatable {
    let url: URL
    let isDirectory: Bool
    let isPackage: Bool
    let isSymbolicLink: Bool

    var canExpand: Bool { isDirectory && !isPackage && !isSymbolicLink }
}

enum FilesDirectoryReader {
    static let maximumEntries = 10_000
    static let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]

    static func children(of directory: URL, fileManager: FileManager = .default, maximumEntries: Int = maximumEntries) throws -> [FilesEntry] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )
        guard urls.count <= maximumEntries else { throw FilesDirectoryError.tooManyEntries(maximumEntries) }
        return try urls.map { url in
            let values = try url.resourceValues(forKeys: resourceKeys)
            return FilesEntry(
                url: url.standardizedFileURL,
                isDirectory: values.isDirectory == true,
                isPackage: values.isPackage == true,
                isSymbolicLink: values.isSymbolicLink == true
            )
        }.sorted {
            if $0.canExpand != $1.canExpand { return $0.canExpand }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }

    static func relativePath(for url: URL, root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents), components.count > rootComponents.count else { return nil }
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }
}

enum FilesDirectoryError: LocalizedError {
    case tooManyEntries(Int)

    var errorDescription: String? {
        switch self {
        case let .tooManyEntries(limit): "This folder has more than \(limit.formatted()) items. Choose a narrower folder."
        }
    }
}

private struct FilesOutline: NSViewRepresentable {
    let rootURL: URL
    let refreshID: UUID
    var onAskAgent: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(rootURL: rootURL) }

    func makeNSView(context: Context) -> NSScrollView {
        let outline = NSOutlineView()
        let column = NSTableColumn(identifier: .init("file"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowSizeStyle = .small
        outline.style = .sourceList
        outline.autosaveExpandedItems = false
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        outline.registerForDraggedTypes([.fileURL])
        outline.menu = context.coordinator.menu
        outline.setAccessibilityLabel("Files in " + rootURL.path)
        context.coordinator.outline = outline
        context.coordinator.onAskAgent = onAskAgent
        context.coordinator.refreshID = refreshID

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = outline
        context.coordinator.reload(rootURL: rootURL)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.onAskAgent = onAskAgent
        guard context.coordinator.rootURL != rootURL || context.coordinator.refreshID != refreshID else { return }
        context.coordinator.refreshID = refreshID
        context.coordinator.reload(rootURL: rootURL)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        private(set) var rootURL: URL
        var refreshID = UUID()
        var onAskAgent: ((URL) -> Void)?
        weak var outline: NSOutlineView?
        private var roots: [Node] = []
        private var loadGeneration = UUID()
        lazy var menu: NSMenu = {
            let menu = NSMenu(title: "File")
            menu.delegate = self
            for (title, action) in [
                ("Open in Default App", #selector(openSelected)),
                ("Reveal in Finder", #selector(revealSelected)),
                ("Copy Path", #selector(copyPath)),
                ("Copy Relative Path", #selector(copyRelativePath)),
                ("Ask Trellis Agent…", #selector(askAgent))
            ] { menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self }
            return menu
        }()

        init(rootURL: URL) { self.rootURL = rootURL }

        func reload(rootURL: URL) {
            let sameRoot = self.rootURL == rootURL
            self.rootURL = rootURL
            outline?.setAccessibilityLabel("Files in " + rootURL.path)
            loadGeneration = UUID()
            let expanded = sameRoot ? roots.flatMap(expandedNodes) : []
            if !sameRoot || roots.isEmpty { roots = [.status("Loading…")] }
            outline?.reloadData()
            load(into: nil, directory: rootURL, generation: loadGeneration) { [weak self] in
                guard let self else { return }
                for node in expanded where node.entry?.canExpand == true {
                    self.load(into: node, directory: node.entry!.url, generation: self.loadGeneration)
                }
            }
        }

        private func load(into parent: Node?, directory: URL, generation: UUID, completion: (() -> Void)? = nil) {
            Task { [weak self, weak parent] in
                let result = await Task.detached(priority: .userInitiated) {
                    Result { try FilesDirectoryReader.children(of: directory) }
                }.value
                guard let self, generation == self.loadGeneration else { return }
                let nodes: [Node]
                switch result {
                case let .success(value): nodes = value.isEmpty ? [.status("No files")] : value.map(Node.entry)
                case let .failure(error): nodes = [.status(error.localizedDescription)]
                }
                if let parent { parent.children = reconcile(parent.children, with: nodes) }
                else { roots = reconcile(roots, with: nodes) }
                outline?.reloadItem(parent, reloadChildren: true)
                completion?()
            }
        }

        private func reconcile(_ existing: [Node], with new: [Node]) -> [Node] {
            new.map { candidate in
                guard let url = candidate.entry?.url,
                      let retained = existing.first(where: { $0.entry?.url == url }) else { return candidate }
                return retained
            }
        }

        private func expandedNodes(_ node: Node) -> [Node] {
            guard outline?.isItemExpanded(node) == true else { return [] }
            return [node] + node.children.flatMap(expandedNodes)
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            (item as? Node)?.children.count ?? roots.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            (item as? Node)?.children[index] ?? roots[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? Node)?.entry?.canExpand == true
        }

        func outlineViewItemWillExpand(_ notification: Notification) {
            guard let node = notification.userInfo?["NSObject"] as? Node,
                  let entry = node.entry, entry.canExpand, !node.loaded else { return }
            node.loaded = true; node.children = [.status("Loading…")]
            outline?.reloadItem(node, reloadChildren: true)
            load(into: node, directory: entry.url, generation: loadGeneration)
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("FileCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCell(identifier)
            if let entry = node.entry {
                cell.textField?.stringValue = entry.url.lastPathComponent
                cell.imageView?.image = NSWorkspace.shared.icon(forFile: entry.url.path)
                cell.toolTip = entry.url.path
                cell.setAccessibilityLabel((entry.isSymbolicLink ? "Symbolic link, " : entry.isPackage ? "Package, " : entry.isDirectory ? "Folder, " : "File, ") + entry.url.lastPathComponent)
            } else {
                cell.textField?.stringValue = node.status ?? ""
                cell.imageView?.image = NSImage(systemSymbolName: node.status == "Loading…" ? "hourglass" : node.status == "Empty folder" ? "folder" : "exclamationmark.triangle", accessibilityDescription: nil)
                cell.setAccessibilityLabel(node.status ?? "File status")
            }
            return cell
        }

        private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            image.imageScaling = .scaleProportionallyDown
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            text.lineBreakMode = .byTruncatingMiddle
            cell.imageView = image; cell.textField = text
            cell.addSubview(image); cell.addSubview(text)
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16), image.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
            (item as? Node)?.entry?.url as NSURL?
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            let enabled = selectedURL != nil
            menu.items.forEach { $0.isEnabled = enabled }
            menu.item(withTitle: "Ask Trellis Agent…")?.isEnabled = enabled && onAskAgent != nil
            menu.item(withTitle: "Copy Relative Path")?.isEnabled = selectedURL.flatMap { FilesDirectoryReader.relativePath(for: $0, root: rootURL) } != nil
        }

        private var selectedURL: URL? {
            guard let outline else { return nil }
            let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
            guard row >= 0, let node = outline.item(atRow: row) as? Node else { return nil }
            return node.entry?.url
        }

        @objc private func openSelected() {
            guard let selectedURL, !NSWorkspace.shared.open(selectedURL) else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn’t open \(selectedURL.lastPathComponent)"
            alert.informativeText = "No application accepted this item."
            if let window = outline?.window { alert.beginSheetModal(for: window) }
            else { alert.runModal() }
        }
        @objc private func askAgent() { if let selectedURL { onAskAgent?(selectedURL) } }
        @objc private func revealSelected() { if let selectedURL { NSWorkspace.shared.activateFileViewerSelecting([selectedURL]) } }
        @objc private func copyPath() { if let selectedURL { copy(selectedURL.path) } }
        @objc private func copyRelativePath() {
            if let selectedURL, let path = FilesDirectoryReader.relativePath(for: selectedURL, root: rootURL) { copy(path) }
        }
        private func copy(_ value: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        }
    }
}

private final class Node: NSObject {
    let entry: FilesEntry?
    let status: String?
    var children: [Node] = []
    var loaded = false

    private init(entry: FilesEntry?, status: String?) { self.entry = entry; self.status = status }
    static func entry(_ entry: FilesEntry) -> Node { Node(entry: entry, status: nil) }
    static func status(_ text: String) -> Node { Node(entry: nil, status: text) }
}
