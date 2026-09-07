import SwiftUI

struct SessionBrowser: View {
    @ObservedObject var workspace: Workspace
    @State private var host = ""
    @State private var remoteExecutable = "/opt/homebrew/bin/tmux"
    @State private var rows: [PersistentSession] = []
    @State private var loadedHost: String?
    @State private var loadedExecutable = ""
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false
    @State private var ending: PersistentSession?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Persistent Sessions").font(.title2); Spacer(); Button("Done") { dismiss() } }
            TextField("SSH user@host (blank for Local)", text: $host)
            if !host.isEmpty { TextField("Remote tmux executable", text: $remoteExecutable) }
            HStack {
                Menu("Saved Hosts") {
                    ForEach(Array(Set(workspace.sessions.compactMap { $0.remote?.hostAlias })).sorted(), id: \.self) { saved in
                        Button(saved) {
                            host = saved
                            remoteExecutable = workspace.sessions.first { $0.remote?.hostAlias == saved }?.remote?.tmuxExecutable ?? "tmux"
                            loaded = false; rows = []
                        }
                    }
                }
                Spacer()
                Button("Refresh", action: refresh).disabled(busy)
            }
            if busy { ProgressView().controlSize(.small) }
            if let error { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
            if loaded && rows.isEmpty { ContentUnavailableView("No tmux sessions", systemImage: "terminal", description: Text("Create one from New Agent → Persistent Local Shell or SSH.")) }
            List(rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(nickname(for: row)).fontWeight(.medium)
                        Text("\(loadedHost ?? "Local") · \(row.windows) windows · \(row.attached > 0 ? "Attached" : "Detached")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Attach") { attach(row) }.disabled(busy || !isCurrent(row))
                    Button("End…", role: .destructive) { ending = row }.disabled(busy || !isCurrent(row))
                }.padding(.vertical, 4)
            }.listStyle(.plain)
            Text("Refresh queries only this host. End stops the selected session and all its panes; other sessions remain running.").font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 660, height: 500)
        .onChange(of: host) { loaded = false; rows = [] }
        .onChange(of: remoteExecutable) { loaded = false; rows = [] }
        .alert("End \(ending.map(nickname) ?? "session")?", isPresented: Binding(get: { ending != nil }, set: { if !$0 { ending = nil } })) {
            Button("Cancel", role: .cancel) { ending = nil }
            Button("End Session", role: .destructive) { if let ending { end(ending) } }
        } message: { Text("Stops this tmux session on \(loadedHost ?? "Local"), including every pane. This cannot be undone.") }
        .task { refresh() }
    }
    private var matchesQuery: Bool { loaded && loadedHost == (host.isEmpty ? nil : host) && (host.isEmpty || loadedExecutable == remoteExecutable) }
    private func isCurrent(_ row: PersistentSession) -> Bool {
        matchesQuery && rows.contains { $0.id == row.id && $0.name == row.name && $0.created == row.created }
    }
    private func nickname(for row: PersistentSession) -> String {
        workspace.sessions.first {
            guard $0.remote?.hostAlias == loadedHost else { return false }
            let name = $0.remote?.sessionName ?? $0.multiplexer?.sessionName
            let created = $0.remote?.sessionCreated ?? $0.multiplexer?.sessionCreated
            return (name == row.id || name == row.name) && (created == nil || created == row.created)
        }?.displayTitle ?? row.readableName
    }
    private func refresh() {
        guard !busy else { return }
        busy = true; error = nil; loaded = false; rows = []
        let target = host.isEmpty ? nil : host, path = remoteExecutable
        Task {
            defer { busy = false }
            do {
                let executable = try target == nil ? MultiplexerProfile.executable(searchPath: AgentInstallation.searchPath) : path
                let sessions = try await PersistentSessions(host: target, executable: executable).list()
                guard target == (host.isEmpty ? nil : host), target == nil || path == remoteExecutable else { return }
                loadedHost = target; loadedExecutable = executable; rows = sessions; loaded = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func attach(_ row: PersistentSession) {
        guard isCurrent(row) else { error = "Session changed. Refresh before attaching."; return }
        do {
            if let loadedHost {
                let profile = try RemoteProfile(hostAlias: loadedHost, directory: "/", sessionName: row.id,
                                                tmuxExecutable: loadedExecutable, sessionCreated: row.created)
                if workspace.startRemote(profile, create: false, nickname: nickname(for: row)) { dismiss() }
            } else if workspace.attachLocal(try MultiplexerProfile(sessionName: row.id, sessionCreated: row.created),
                                            nickname: nickname(for: row)) { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
    private func end(_ row: PersistentSession) {
        busy = true; error = nil
        let service = PersistentSessions(host: loadedHost, executable: loadedExecutable)
        Task {
            do { try await service.end(row); rows.removeAll { $0.id == row.id } }
            catch { self.error = error.localizedDescription }
            busy = false; ending = nil
        }
    }
}
