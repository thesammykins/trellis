import SwiftUI

/// The caller presents this only while arranging panes, so terminal input remains unobstructed otherwise.
struct PaneDropOverlay: View {
    @ObservedObject var workspace: Workspace
    let target: UUID

    static func dragItem(workspaceID: UUID, source: UUID) -> NSItemProvider {
        return NSItemProvider(object: ("trellis-session:" + workspaceID.uuidString + ":" + source.uuidString) as NSString)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Drag a tab to move its session").font(.caption).foregroundStyle(.secondary)
            zone(.above).frame(height: 42)
            HStack(spacing: 6) {
                zone(.left).frame(maxWidth: .infinity)
                zone(.swap).frame(maxWidth: .infinity, maxHeight: .infinity)
                zone(.right).frame(maxWidth: .infinity)
            }.frame(minHeight: 64, maxHeight: .infinity)
            zone(.below).frame(height: 42)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func zone(_ position: PaneDropPosition) -> some View {
        PaneDropZone(position: position) { token in
            let parts = token.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "trellis-session",
                  UUID(uuidString: String(parts[1])) == workspace.id,
                  let source = UUID(uuidString: String(parts[2])), source != target else { return false }
            return workspace.movePane(source: source, target: target, position: position)
        }
    }
}

private struct PaneDropZone: View {
    let position: PaneDropPosition
    let accept: (String) -> Bool
    @State private var targeted = false

    var body: some View {
        Text(position.title)
            .font(position == .swap ? .headline : .callout)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(targeted ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(targeted ? Color.accentColor : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
            .accessibilityLabel("Move pane: " + position.title)
            .dropDestination(for: String.self) { values, _ in
                guard values.count == 1, let token = values.first, token.utf8.count <= 128 else { return false }
                return accept(token)
            } isTargeted: { targeted = $0 }
    }
}
