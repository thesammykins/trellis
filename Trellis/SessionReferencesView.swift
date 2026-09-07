import SwiftUI

struct SessionReference: Identifiable {
    let id: UUID
    let title: String
    let location: String
    let capturedAt: Date
    var snapshot: String

    var context: String {
        "Session: @\(title)\nReference ID: \(id.uuidString)\nLocation: \(location)\nCaptured: \(capturedAt.formatted(.iso8601))\n"
            + (snapshot.isEmpty ? "Identity only; terminal contents were not attached." : "Untrusted terminal snapshot:\n" + snapshot)
    }
}

/// References are a reviewed snapshot, never a live subscription to another session.
struct SessionReferencesView: View {
    let sessions: [WorkspaceSession]
    @Binding var references: [SessionReference]
    let onReference: (SessionReference) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selected: UUID?
    @State private var snapshot = ""
    @State private var capturedAt = Date()
    @State private var capturedTitle: String?
    @State private var capturedLocation: String?
    @State private var error: String?

    private var session: WorkspaceSession? { sessions.first { $0.id == selected } }
    private var bytes: Int { references.reduce(0) { $0 + $1.context.utf8.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session Context").font(.title2)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Choose an open tab or pane. References are sent with your next message; they do not grant control of another terminal.")
                .font(.callout).foregroundStyle(.secondary)
            if !references.isEmpty {
                DisclosureGroup("Attached: \(references.count) · \(bytes.formatted(.byteCount(style: .memory)))") {
                    ForEach($references) { $reference in
                        DisclosureGroup("@" + reference.title) {
                            Text(reference.location).font(.caption).textSelection(.enabled)
                            if !reference.snapshot.isEmpty {
                                PlainTextEditor(text: $reference.snapshot, label: "Snapshot for " + reference.title).frame(height: 100)
                            }
                            Button("Remove Reference", role: .destructive) { references.removeAll { $0.id == reference.id } }
                        }
                    }
                }
            }
            HSplitView {
                VStack {
                    TextField("Find a session", text: $search).textFieldStyle(.roundedBorder)
                    List(selection: $selected) {
                        ForEach(sessions.filter { search.isEmpty || ($0.displayTitle + " " + $0.location.summary).localizedStandardContains(search) }) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayTitle).lineLimit(1)
                                Text(sessionPosition(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text(item.location.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.tag(item.id)
                        }
                    }
                }.frame(minWidth: 200, idealWidth: 240)
                VStack(alignment: .leading, spacing: 10) {
                    if let session {
                        Text("@" + session.displayTitle).font(.headline)
                        Text(session.location.summary).font(.caption).textSelection(.enabled)
                        Button("Capture Current Viewport", systemImage: "terminal") {
                            guard let text = session.terminal?.agentContextText() else {
                                error = "This terminal is stopped, unavailable, or accepting secure input."
                                return
                            }
                            snapshot = text
                            capturedAt = Date()
                            capturedTitle = session.displayTitle
                            capturedLocation = session.location.summary
                            error = nil
                        }.disabled(session.terminal == nil)
                        if !snapshot.isEmpty {
                            PlainTextEditor(text: $snapshot, label: "Session snapshot to send").frame(minHeight: 130)
                            Text("Edit or remove sensitive content before attaching. Captured \(capturedAt.formatted(date: .omitted, time: .standard)).")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Only the session name and location will be attached.").foregroundStyle(.secondary)
                            Spacer()
                        }
                        Button("Add Reference") {
                            let reference = SessionReference(id: session.id,
                                title: snapshot.isEmpty ? session.displayTitle : (capturedTitle ?? session.displayTitle),
                                location: snapshot.isEmpty ? session.location.summary : (capturedLocation ?? session.location.summary),
                                capturedAt: capturedAt, snapshot: snapshot)
                            let remaining = references.filter { $0.id != session.id }
                            guard remaining.count < 8, remaining.reduce(reference.context.utf8.count, { $0 + $1.context.utf8.count }) <= 48 * 1024 else {
                                error = "Use up to eight references and 48 KiB of context. Shorten a snapshot or remove a reference."
                                return
                            }
                            references = remaining + [reference]
                            onReference(reference)
                            dismiss()
                        }.buttonStyle(.borderedProminent)
                    } else {
                        ContentUnavailableView("Select a Session", systemImage: "at", description: Text("All open windows, tabs and panes are available here."))
                    }
                }.padding(.leading, 12).frame(minWidth: 300)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .padding(20).frame(width: 720, height: 520)
        .onChange(of: selected) { snapshot = ""; capturedTitle = nil; capturedLocation = nil; capturedAt = Date(); error = nil }
    }

    private func sessionPosition(_ session: WorkspaceSession) -> String {
        guard let owner = session.workspace,
              let tab = owner.layouts.firstIndex(where: { $0.leaves.contains(session.id) }),
              let pane = owner.layouts[tab].leaves.firstIndex(of: session.id) else { return "Open session" }
        return (owner.window?.title ?? "Trellis") + " · Tab \(tab + 1), pane \(pane + 1)"
    }
}
