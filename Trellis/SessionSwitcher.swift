import SwiftUI

struct SessionSwitcher: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var organization: SessionOrganization
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var categoryID: UUID?
    @State private var favouritesOnly = false
    @State private var newCategory = ""
    @State private var categoryNames: [UUID: String] = [:]
    @FocusState private var searchFocused: Bool

    private var sessions: [WorkspaceSession] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = workspace.sessions.filter { session in
            let matchesSearch = term.isEmpty || [session.displayTitle, session.directory.path, session.profile.title]
                .contains(where: { $0.localizedCaseInsensitiveContains(term) })
            return matchesSearch && (!favouritesOnly || session.favourite)
                && (categoryID == nil || organization.category(for: session.id) == categoryID)
        }
        return organized(filtered, by: organization.sort)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search sessions", text: $query).textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit(openFirstMatch)
                Picker("Sort", selection: Binding(get: { organization.sort }, set: { _ = organization.setSort($0) })) {
                    ForEach(SessionSort.allCases) { Text($0.title).tag($0) }
                }.frame(width: 130)
            }
            HStack {
                Picker("Category", selection: $categoryID) {
                    Text("All categories").tag(UUID?.none)
                    ForEach(organization.categories) { Text($0.name).tag(Optional($0.id)) }
                }
                Toggle("Favourites", isOn: $favouritesOnly)
                Spacer()
                TextField("New category", text: $newCategory).frame(width: 150)
                Button("Add") {
                    if let id = organization.createCategory(newCategory) { categoryNames[id] = newCategory.trimmingCharacters(in: .whitespacesAndNewlines); newCategory = "" }
                }
                    .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            DisclosureGroup("Manage Categories") {
                ForEach(organization.categories) { category in
                    HStack {
                        TextField("Category name", text: Binding(get: { categoryNames[category.id] ?? category.name }, set: { categoryNames[category.id] = $0 }))
                            .onSubmit { rename(category) }
                        Button("Rename") { rename(category) }
                        Button("Remove Category", role: .destructive) {
                            if organization.removeCategory(category.id) { categoryNames.removeValue(forKey: category.id) }
                        }
                    }
                }
                Text("Removing a category only clears its assignments. It never stops or removes sessions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = organization.readError { Text(error).foregroundStyle(.red).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
            List(sessions) { session in
                HStack {
                    Button { workspace.select(session); dismiss() } label: {
                        VStack(alignment: .leading) {
                            Text(session.displayTitle)
                            Text("\(session.profile.title) · \(session.directory.path)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Open \(session.displayTitle)")
                    if session.favourite { Image(systemName: "star.fill").foregroundStyle(.yellow).accessibilityLabel("Favourite") }
                    Spacer()
                    Picker("Category for \(session.displayTitle)", selection: Binding(get: { organization.category(for: session.id) }, set: { _ = organization.assign(session.id, to: $0) })) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(organization.categories) { Text($0.name).tag(Optional($0.id)) }
                    }.labelsHidden().frame(width: 150)
                }
            }
            HStack {
                Button("New Shell") { workspace.pendingSwitcherLaunch = "shell"; dismiss() }
                Button("New Agent") { workspace.pendingSwitcherLaunch = "agent"; dismiss() }
                Spacer()
                Button("Done") { dismiss() }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 420)
        .onAppear {
            categoryNames = Dictionary(uniqueKeysWithValues: organization.categories.map { ($0.id, $0.name) })
            searchFocused = true
        }
    }

    private func openFirstMatch() {
        guard let session = sessions.first else { return }
        workspace.select(session)
        dismiss()
    }

    private func rename(_ category: SessionCategory) {
        let name = categoryNames[category.id] ?? category.name
        if organization.renameCategory(category.id, to: name) { categoryNames[category.id] = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

struct SessionQuickLinks: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var organization: SessionOrganization

    private func sessions(in category: UUID?) -> [WorkspaceSession] {
        organized(workspace.sessions.filter { category == nil ? $0.favourite : organization.category(for: $0.id) == category }, by: organization.sort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !sessions(in: nil).isEmpty {
                Text("Favourites").font(.caption).foregroundStyle(.secondary)
                links(sessions(in: nil))
            }
            ForEach(organization.categories) { category in
                let matching = sessions(in: category.id)
                if !matching.isEmpty {
                    Text(category.name).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dropDestination(for: String.self) { items, _ in assign(items, to: category.id) }
                    links(matching)
                }
            }
        }
    }

    @ViewBuilder
    private func links(_ sessions: [WorkspaceSession]) -> some View {
        ForEach(sessions) { session in
            Button { workspace.select(session) } label: { Text(session.displayTitle).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(session.displayTitle)")
                .draggable("trellis-session:\(workspace.id.uuidString.lowercased()):\(session.id.uuidString)")
        }
    }

    private func assign(_ items: [String], to categoryID: UUID) -> Bool {
        guard let item = items.first,
              let sessionID = sessionID(from: item),
              workspace.sessions.contains(where: { $0.id == sessionID }) else { return false }
        return organization.assign(sessionID, to: categoryID)
    }

    private func sessionID(from item: String) -> UUID? {
        let pieces = item.split(separator: ":", maxSplits: 2).map(String.init)
        guard pieces.count == 3, pieces[0] == "trellis-session", pieces[1] == workspace.id.uuidString.lowercased(),
              let id = UUID(uuidString: pieces[2]) else { return nil }
        return id
    }
}

@MainActor private func organized(_ sessions: [WorkspaceSession], by sort: SessionSort) -> [WorkspaceSession] {
    guard sort != .manual else { return sessions }
    return sessions.sorted { left, right in
        switch sort {
        case .manual: false
        case .title: left.displayTitle.localizedCaseInsensitiveCompare(right.displayTitle) == .orderedAscending
        case .harness: left.profile.title.localizedCaseInsensitiveCompare(right.profile.title) == .orderedAscending
        case .directory: left.directory.path.localizedCaseInsensitiveCompare(right.directory.path) == .orderedAscending
        }
    }
}
