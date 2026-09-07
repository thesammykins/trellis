import SwiftUI
import CryptoKit

@MainActor
final class MemoryModel: ObservableObject {
    @Published var pages: [MemoryPage] = []
    @Published var proposals: [MemoryProposal] = []
    @Published var receipts: [RetrievalReceipt] = []
    @Published var error: String?
    private(set) var store: MemoryStore?

    func load(project: URL) async {
        pages = []; proposals = []; receipts = []; error = nil; store = nil
        do {
            let location = try MemoryIntegration(project: project)
            store = try MemoryStore(root: location.root, projectID: location.projectID)
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh(query: String = "") async {
        guard let store else { return }
        do {
            pages = try await store.pages(query: query)
            proposals = try await store.proposals()
            receipts = try await store.receipts()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func propose(title: String, body: String, kind: String, pageID: UUID?, source: String = "User draft in Trellis") async -> Bool {
        guard let store else { return false }
        do {
            _ = try await store.propose(title: title, body: body, kind: kind, pageID: pageID, source: source)
            await refresh()
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func decide(_ proposal: MemoryProposal, action: String) async {
        guard let store else { return }
        do {
            switch action {
            case "approve": try await store.approve(proposal.id)
            case "reject": try await store.reject(proposal.id)
            case "rollback": try await store.rollback(proposal.id)
            default: return
            }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func export(_ page: MemoryPage) async {
        guard let store else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = page.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".md"
        guard await panel.begin() == .OK, let url = panel.url else { return }
        do { try await store.export(page.id).write(to: url, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
}

struct MemoryPanel: View {
    let project: URL
    var selectedText: () -> String?
    var sharingEnabled = false
    var initialSection = "pages"
    var onSectionChange: (String) -> Void
    @StateObject private var model = MemoryModel()
    @State private var section: String
    @State private var query = ""
    @State private var kindFilter = "all"
    @State private var selectedPageID: UUID?
    @State private var draftOpen = false
    @State private var draftID: UUID?
    @State private var title = ""
    @State private var bodyText = ""
    @State private var kind = "decision"
    @State private var review: MemoryProposal?
    @State private var busy = false

    init(project: URL,
         selectedText: @escaping () -> String?,
         sharingEnabled: Bool = false,
         initialSection: String = "pages",
         onSectionChange: @escaping (String) -> Void = { _ in }) {
        self.project = project
        self.selectedText = selectedText
        self.sharingEnabled = sharingEnabled
        self.initialSection = initialSection
        self.onSectionChange = onSectionChange
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            switch section {
            case "context": contextLibrary
            case "review": reviewLibrary
            default: pageLibrary
            }
        }
        .frame(minWidth: section == "context" ? 300 : 500, maxWidth: .infinity, maxHeight: .infinity)
        .task(id: project) { await model.load(project: project) }
        .onChange(of: initialSection) { section = initialSection }
        .onChange(of: section) { onSectionChange(section) }
        .sheet(isPresented: $draftOpen) { draft }
        .sheet(item: $review) { proposal in reviewView(proposal) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(initialSection == "context" ? "Session Context" : initialSection == "review" ? "Review Changes" : "Project Memory").font(.title2.weight(.semibold))
                    Text(project.lastPathComponent + " · " + project.path)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh(query: query) } }
                    .labelStyle(.iconOnly).help("Refresh project memory")
                if initialSection != "context" { Button("New Note", systemImage: "square.and.pencil") { newDraft("") } }
            }
        }.padding(16)
    }

    private var filteredPages: [MemoryPage] {
        kindFilter == "all" ? model.pages : model.pages.filter { $0.kind == kindFilter }
    }

    private var pageLibrary: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search approved pages", text: $query)
                    .onSubmit { Task { await model.refresh(query: query) } }
                Picker("Type", selection: $kindFilter) {
                    Text("All").tag("all")
                    ForEach(["decision", "constraint", "how-to", "reference", "lesson", "preference"], id: \.self) { Text($0.capitalized).tag($0) }
                }.labelsHidden().frame(width: 130)
                Button("Keep Selection") {
                    guard let text = selectedText(), !text.isEmpty else {
                        model.error = "Select terminal text first, then choose Keep Selection."
                        return
                    }
                    newDraft(text)
                }
            }.padding(12)
            if model.pages.isEmpty {
                ContentUnavailableView("No project memory yet.", systemImage: "book.closed", description: Text("Keep a decision from this session, or add a note."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    if geometry.size.width >= 650 {
                        HSplitView {
                            pageList.frame(minWidth: 160, idealWidth: 220, maxWidth: 320)
                            documentPane.frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        VStack(spacing: 0) {
                            pageList.frame(minHeight: 180, maxHeight: 240)
                            Divider()
                            documentPane
                        }
                    }
                }
            }
        }
    }

    private var pageList: some View {
        List(filteredPages, selection: $selectedPageID) { page in
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title).lineLimit(1)
                Text(page.kind.capitalized + " · revision \(page.revision)").font(.caption).foregroundStyle(.secondary)
            }.tag(page.id)
        }
        .listStyle(.sidebar)
        .onChange(of: filteredPages.map(\.id)) { ids in
            if let selectedPageID, !ids.contains(selectedPageID) { self.selectedPageID = nil }
        }
    }

    @ViewBuilder
    private var documentPane: some View {
        if let page = model.pages.first(where: { $0.id == selectedPageID }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.title).font(.title2.weight(.semibold))
                        Text("Approved · \(page.kind.capitalized) · revision \(page.revision)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") { edit(page) }
                    Button("Export") { Task { await model.export(page) } }
                }
                Text("Scope: \(project.lastPathComponent) · \(project.path)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Divider()
                ScrollView {
                    Text(page.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 16)
                }
                Text("Hash \(page.hash.prefix(12))").font(.caption2.monospaced()).foregroundStyle(.secondary)
            }.padding(16)
        } else {
            ContentUnavailableView("Select a memory page", systemImage: "doc.text", description: Text("Choose an approved page to read its content and metadata."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var contextLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sharingEnabled ? "Memory tools enabled for this session" : "Memory tools are off for this session").font(.headline)
            Text("Enabled means available. A returned page is tool output; it does not prove the model used it.").font(.caption).foregroundStyle(.secondary)
            if model.receipts.isEmpty {
                ContentUnavailableView("No recorded retrievals", systemImage: "clock.arrow.circlepath", description: Text("Retrieval history for this project appears here."))
            } else {
                List(model.receipts) { receipt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Returned · \(receipt.mechanism.uppercased())").font(.headline)
                        Text(receipt.date.formatted(date: .abbreviated, time: .shortened))
                        Text("\(receipt.pages.count) pages · \(receipt.returnedBytes) bytes").font(.caption)
                        ForEach(receipt.pages, id: \.id) { source in
                            Text(source.id.uuidString.prefix(8) + " · " + source.hash.prefix(12)).font(.caption2.monospaced())
                        }
                    }.accessibilityElement(children: .combine)
                }.listStyle(.inset)
            }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var reviewLibrary: some View {
        Group {
            if model.proposals.isEmpty {
                ContentUnavailableView("No proposals to review", systemImage: "checkmark.circle", description: Text("New notes and edits remain proposals until you approve and apply them."))
            } else {
                List(model.proposals) { proposal in
                    Button { review = proposal } label: {
                        VStack(alignment: .leading) {
                            Text(proposal.title).font(.headline)
                            Text(proposal.kind.capitalized + " · " + proposal.status.capitalized).font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }.listStyle(.inset)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func newDraft(_ text: String) {
        draftID = nil; title = ""; bodyText = text; kind = "decision"; draftOpen = true
    }
    private func edit(_ page: MemoryPage) {
        draftID = page.id
        title = page.title
        bodyText = page.body
        kind = page.kind
        draftOpen = true
    }
    private var draft: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draftID == nil ? "Propose a note" : "Propose an edit").font(.title2)
            TextField("Title", text: $title)
            Picker("Kind", selection: $kind) {
                ForEach(["decision", "constraint", "how-to", "reference", "lesson", "preference"], id: \.self) { Text($0).tag($0) }
            }
            PlainTextEditor(text: $bodyText, label: "Memory body").frame(minHeight: 300)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel") { draftOpen = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Proposal") {
                    busy = true
                    Task {
                        if await model.propose(title: title, body: bodyText, kind: kind, pageID: draftID) {
                            draftOpen = false; section = "review"
                        }
                        busy = false
                    }
                }.disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 650)
    }
    private func reviewView(_ proposal: MemoryProposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(proposal.title).font(.title2)
            Text("\(proposal.kind) · \(proposal.status) · \(proposal.source)").font(.caption)
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text("Current approved page").font(.headline)
                    ScrollView { Text(model.pages.first { $0.id == proposal.pageID }?.body ?? "New page").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
                Divider()
                VStack(alignment: .leading) {
                    Text("Proposed content").font(.headline)
                    ScrollView { Text(proposal.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }.frame(height: 350)
            if let error = model.error { Text(error).foregroundStyle(.orange).font(.caption) }
            HStack {
                Button("Close") { review = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                if proposal.status == "proposed" || proposal.status == "stale" {
                    Button("Reject") { decide(proposal, "reject") }
                }
                if proposal.status == "proposed" {
                    Button("Approve and Apply") { decide(proposal, "approve") }
                }
                if proposal.status == "applied" {
                    Button("Roll Back") { decide(proposal, "rollback") }
                }
            }.disabled(busy)
        }.padding(24).frame(width: 820)
    }
    private func decide(_ proposal: MemoryProposal, _ action: String) {
        busy = true
        Task {
            await model.decide(proposal, action: action)
            busy = false
            if model.error == nil { review = nil }
        }
    }
}
