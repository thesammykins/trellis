import SwiftUI

struct WorkspaceHomeView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject private var locations = RemoteLocationStore.shared
    @AppStorage("homeSessionDisplay") private var display = "grid"
    @AppStorage("homeSessionSort") private var sort = "recent"
    @AppStorage("homeShowStopped") private var showsStopped = true
    @State private var query = ""
    @State private var editingLocation: RemoteLocation?
    @State private var tmuxLocation: RemoteLocation?
    @State private var error: String?

    private var allSessions: [WorkspaceSession] { workspace.onOpenSessions?() ?? workspace.sessions }
    private var sessions: [WorkspaceSession] {
        allSessions.filter { session in
            query.isEmpty || [session.displayTitle, session.harnessTitle, session.directory.path, session.remote?.hostAlias ?? ""]
                .contains { $0.localizedStandardContains(query) }
        }.sorted {
            if $0.favourite != $1.favourite { return $0.favourite }
            if sort == "project", $0.directory != $1.directory { return $0.directory.path.localizedStandardCompare($1.directory.path) == .orderedAscending }
            if $0.lastUsedAt != $1.lastUsedAt { return ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    private var savedLocations: [RemoteLocation] {
        locations.locations.filter { query.isEmpty || [$0.name, $0.hostAlias, $0.directory].contains { $0.localizedStandardContains(query) } }
    }
    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 12, alignment: .leading)] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Home").font(.title2.bold())
                        Text("Sessions and favorites across your windows").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    TextField("Search sessions and locations", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    Picker("Session layout", selection: $display) {
                        Image(systemName: "square.grid.2x2").tag("grid").accessibilityLabel("Grid")
                        Image(systemName: "list.bullet").tag("list").accessibilityLabel("List")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 76)
                }
                if allSessions.isEmpty && query.isEmpty {
                    ContentUnavailableView {
                        Label("Start a session", systemImage: "terminal")
                    } description: {
                        Text("Open a shell or agent. Its tab and layout will be saved for your next visit.")
                    } actions: {
                        Button("New Shell", action: workspace.newShell)
                        Button("Open Agent…", action: workspace.requestNewSession)
                    }
                }
                if !query.isEmpty && sessions.isEmpty {
                    Text("No matching sessions.").font(.callout).foregroundStyle(.secondary)
                }
                sessionSection("Open sessions", values: sessions.filter { $0.isRunning || $0.hasActiveChat })
                if showsStopped { sessionSection("Saved sessions", values: sessions.filter { !$0.isRunning && !$0.hasActiveChat }) }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("SSH favorites").font(.headline)
                        Spacer()
                        Button("Add Favorite", systemImage: "plus") { editingLocation = RemoteLocation() }
                    }
                    if let issue = locations.error { Text(issue).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    if savedLocations.isEmpty {
                        Text(query.isEmpty ? "Save a host and folder for an ordinary SSH login or a separate tmux session." : "No matching SSH favorites.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(savedLocations) { location in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Label(location.name, systemImage: "server.rack").font(.headline).lineLimit(1)
                                        Spacer(minLength: 4)
                                        Menu {
                                            Button("New tmux Session…") { tmuxLocation = location }
                                            Button("Edit Favorite…") { editingLocation = location }
                                            Button("Remove Favorite", role: .destructive) {
                                                do { try locations.remove(location.id) } catch { self.error = error.localizedDescription }
                                            }
                                        } label: { Image(systemName: "ellipsis") }
                                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for " + location.name)
                                    }
                                    Text(location.hostAlias + (location.directory.isEmpty ? "" : " · " + location.directory))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    Button("Connect SSH") { connect(location) }.controlSize(.small)
                                }.padding(12).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                Text("Saved tabs restore their identities and layouts. Processes stay stopped until you start or connect; tmux workload status is unknown until checked.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editingLocation) { location in RemoteLocationEditor(location: location, store: locations) }
        .sheet(item: $tmuxLocation) { location in RemoteSessionView(workspace: workspace, location: location, initialMode: .tmux) }
    }

    @ViewBuilder private func sessionSection(_ title: String, values: [WorkspaceSession]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(title).font(.headline); Text(values.count.formatted()).font(.caption).foregroundStyle(.secondary) }
                if display == "list" {
                    LazyVStack(spacing: 0) {
                        ForEach(values) { session in
                            sessionButton(session, compact: true)
                            if session.id != values.last?.id { Divider() }
                        }
                    }.background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(values) { sessionButton($0, compact: false) }
                    }
                }
            }
        }
    }

    private func sessionButton(_ session: WorkspaceSession, compact: Bool) -> some View {
        Button { workspace.openExistingSession(session) } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Image(systemName: session.remote == nil ? "terminal" : "network").font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(session.displayTitle).font(.headline).lineLimit(1)
                            if session.favourite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.secondary) }
                        }
                        Text(session.remote.map { $0.hostAlias + ($0.directory.isEmpty ? "" : " · " + $0.directory) } ?? session.directory.path)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    if compact { Text(status(session)).font(.caption).foregroundStyle(.secondary); Text(windowLabel(session)).font(.caption).foregroundStyle(.secondary) }
                }
                if !compact {
                    HStack {
                        Label(status(session), systemImage: session.isRunning || session.hasActiveChat ? "circle.fill" : "stop.circle")
                        Spacer(minLength: 2)
                        Text(windowLabel(session))
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }.padding(12).frame(maxWidth: .infinity, minHeight: compact ? 56 : 92, alignment: .leading)
                .contentShape(Rectangle())
                .background(compact ? Color.clear : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
            .help("Open " + session.harnessTitle + " · " + status(session))
            .accessibilityLabel("Open " + session.displayTitle + ", " + status(session) + ", " + windowLabel(session))
            .contextMenu {
                Button("Open in Its Window") { workspace.openExistingSession(session) }
                Button(session.favourite ? "Remove Favorite" : "Favorite Session") { session.workspace?.toggleFavourite(session) }
            }
    }

    private func status(_ session: WorkspaceSession) -> String {
        if session.chatNeedsApproval { return "Chat needs approval" }
        if session.hasActiveChat { return "Chat working" }
        if session.isRunning { return session.remote == nil ? "Running" : "SSH process open" }
        return session.isPersistent ? "Disconnected" : "Stopped"
    }
    private func windowLabel(_ session: WorkspaceSession) -> String {
        if session.workspace === workspace { return "This window" }
        return session.workspace == nil ? "Saved" : "Another window"
    }
    private func connect(_ location: RemoteLocation) {
        do {
            let profile = try location.profile(persistent: false)
            if workspace.startRemote(profile, create: false, nickname: location.name) { error = nil }
        } catch { self.error = error.localizedDescription }
    }
}

struct HomePreferencesView: View {
    @AppStorage("homeSessionDisplay") private var display = "grid"
    @AppStorage("homeSessionSort") private var sort = "recent"
    @AppStorage("homeShowStopped") private var showsStopped = true
    var body: some View {
        Picker("Session layout", selection: $display) { Text("Grid").tag("grid"); Text("List").tag("list") }
        Picker("Session order", selection: $sort) { Text("Recently used").tag("recent"); Text("Project").tag("project") }
        Toggle("Show stopped sessions on Home", isOn: $showsStopped)
        Text("Window layout and selection are saved automatically. Opening Trellis does not restart saved sessions or SSH connections.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
