import CryptoKit
import Darwin
import Foundation

struct MemoryPage: Identifiable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let kind: String
    let revision: Int
    let hash: String
}

struct MemoryProposal: Identifiable, Sendable, Codable {
    let id: UUID
    let title: String
    let body: String
    let kind: String
    let source: String
    let pageID: UUID
    let baseHash: String?
    var status: String
}

struct RetrievalReceipt: Identifiable, Sendable, Codable {
    struct Source: Sendable, Codable {
        let id: UUID
        let hash: String
    }

    let id: UUID
    let date: Date
    let mechanism: String
    let pages: [Source]
    let returnedBytes: Int
}

actor MemoryStore {
    static let maximumPages = 1_000
    static let maximumProposals = 1_000
    static let maximumTitleBytes = 200
    static let maximumBodyBytes = 100_000
    static let maximumSourceBytes = 4_000
    static let maximumQueryBytes = 4_096
    static let maximumPageFileBytes = 112_000
    static let maximumProposalFileBytes = 160_000
    static let maximumJournalFileBytes = 160_000
    static let maximumReceipts = 100
    static let maximumReceiptFileBytes = 96_000
    static let maximumReturnedBytes = 32 * 1024

    private static let kinds = Set(["decision", "constraint", "how-to", "reference", "lesson", "preference"])
    private let manager = FileManager.default
    private let projectID: String
    private let scope: URL
    private let wiki: URL
    private let proposalDirectory: URL
    private let journalDirectory: URL
    private let receiptDirectory: URL
    private var staged: [UUID: MemoryProposal] = [:]

    init(root: URL, projectID: String) throws {
        guard !projectID.isEmpty, projectID.utf8.count <= 200, !projectID.utf8.contains(0) else {
            throw Failure("Project ID must contain 1...200 bytes and no NUL characters.")
        }
        let requestedRoot = root.standardizedFileURL
        guard let canonicalParent = realpath(requestedRoot.deletingLastPathComponent().path, nil) else {
            throw Failure("The memory root parent does not exist.")
        }
        defer { free(canonicalParent) }
        let root = URL(fileURLWithPath: String(cString: canonicalParent), isDirectory: true)
            .appendingPathComponent(requestedRoot.lastPathComponent, isDirectory: true)
        guard root.isFileURL, root.path.hasPrefix("/"), !Self.containsSymlink(root) else {
            throw Failure("The memory root must be an absolute, symlink-free file URL.")
        }
        self.projectID = projectID
        scope = root.appendingPathComponent(Self.sha256(Data(projectID.utf8)), isDirectory: true)
        wiki = scope.appendingPathComponent("Memory/wiki", isDirectory: true)
        proposalDirectory = scope.appendingPathComponent("Memory/proposals", isDirectory: true)
        journalDirectory = scope.appendingPathComponent("Memory/journal", isDirectory: true)
        receiptDirectory = scope.appendingPathComponent("Memory/receipts", isDirectory: true)
        for directory in [scope, wiki, proposalDirectory, journalDirectory, receiptDirectory] {
            guard directory.path.hasPrefix(root.path + "/"), !Self.containsSymlink(directory) else {
                throw Failure("Memory storage escaped its project scope.")
            }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
        let initializedScope = scope
        let initializedProposals = proposalDirectory
        let initializedJournal = journalDirectory
        let initializedWiki = wiki
        let loaded = try Self.withWriterLock(scope: initializedScope) {
            var loaded: [UUID: MemoryProposal] = [:]
            try Self.loadProposals(from: initializedProposals, into: &loaded)
            try Self.reconcile(journals: initializedJournal, wiki: initializedWiki,
                               proposals: initializedProposals, staged: &loaded)
            return loaded
        }
        staged = loaded
    }

    func pages(query: String = "") throws -> [MemoryPage] {
        guard query.utf8.count <= Self.maximumQueryBytes, !query.utf8.contains(0) else {
            throw Failure("Search query exceeds 4 KiB or contains NUL.")
        }
        let files = try markdownFiles(in: wiki)
        guard files.count <= Self.maximumPages else { throw Failure("Project memory exceeds the 1,000 page limit.") }
        let needle = query.lowercased()
        return try files.compactMap { file in
            let page = try readPage(file)
            return needle.isEmpty || page.title.lowercased().contains(needle) || page.body.lowercased().contains(needle)
                ? page : nil
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func export(_ pageID: UUID) throws -> Data {
        let url = pageURL(pageID)
        let data = try boundedData(url)
        _ = try parsePage(data, expectedID: pageID)
        return data
    }

    func proposals() throws -> [MemoryProposal] {
        try withWriterLock {
            var current: [UUID: MemoryProposal] = [:]
            try Self.loadProposals(from: proposalDirectory, into: &current)
            staged = current
            return current.values.sorted { $0.id.uuidString < $1.id.uuidString }
        }
    }

    func receipts() throws -> [RetrievalReceipt] {
        try withWriterLock {
            try Self.loadReceipts(from: receiptDirectory)
                .sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }
        }
    }

    func recordRetrieval(pages: [MemoryPage], returnedBytes: Int,
                         mechanism: String = "mcp") throws -> RetrievalReceipt {
        try Task.checkCancellation()
        guard pages.count <= Self.maximumPages, (0...Self.maximumReturnedBytes).contains(returnedBytes),
              ["mcp", "native"].contains(mechanism), Set(pages.map(\.id)).count == pages.count,
              pages.allSatisfy({ Self.isHash($0.hash) }) else {
            throw Failure("Retrieval receipt fields are invalid or exceed their limits.")
        }
        let receipt = RetrievalReceipt(id: UUID(), date: Date(), mechanism: mechanism,
                                       pages: pages.map { .init(id: $0.id, hash: $0.hash) },
                                       returnedBytes: returnedBytes)
        return try withWriterLock {
            let current = try Self.loadReceipts(from: receiptDirectory)
                .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
            for expired in current.prefix(max(0, current.count - Self.maximumReceipts + 1)) {
                try removeFile(receiptURL(expired.id))
            }
            try writeJSON(receipt, to: receiptURL(receipt.id), maximumBytes: Self.maximumReceiptFileBytes)
            return receipt
        }
    }

    func propose(title: String, body: String, kind: String, pageID: UUID? = nil,
                 source: String) throws -> MemoryProposal {
        try Task.checkCancellation()
        let id = UUID()
        let target = pageID ?? UUID()
        return try withWriterLock {
            let proposal = MemoryProposal(id: id, title: title, body: body, kind: kind, source: source,
                                          pageID: target, baseHash: try pageID.map { try currentHash(for: $0) } ?? nil,
                                          status: "proposed")
            try validate(proposal)
            var current: [UUID: MemoryProposal] = [:]
            try Self.loadProposals(from: proposalDirectory, into: &current)
            guard current.count < Self.maximumProposals else { throw Failure("Project proposals exceed the 1,000 proposal limit.") }
            try writeJSON(proposal, to: proposalURL(id), maximumBytes: Self.maximumProposalFileBytes)
            staged = current
            staged[id] = proposal
            return proposal
        }
    }

    func approve(_ id: UUID) throws {
        try withWriterLock {
            try reloadProposals()
            guard var proposal = staged[id], proposal.status == "proposed" else {
                throw Failure("Proposal is unavailable or is not pending.")
            }
            try validate(proposal)
            let pageURL = self.pageURL(proposal.pageID)
            try rejectSymlink(pageURL)
            let oldData = manager.fileExists(atPath: pageURL.path) ? try boundedData(pageURL) : nil
            let currentHash = oldData.map(Self.sha256)
            guard currentHash == proposal.baseHash else {
                proposal.status = "stale"
                try persist(&proposal)
                throw Failure("Proposal is stale because the page changed after it was proposed.")
            }
            if oldData == nil {
                guard try markdownFiles(in: wiki).count < Self.maximumPages else {
                    throw Failure("Project memory exceeds the 1,000 page limit.")
                }
            }
            let revision = try oldData.map { try parsePage($0, expectedID: proposal.pageID).revision + 1 } ?? 1
            let newData = try encodePage(proposal, revision: revision)
            let transaction = Transaction(id: UUID(), proposalID: id, pageID: proposal.pageID,
                                          baseHash: currentHash, appliedHash: Self.sha256(newData),
                                          previousData: oldData, state: "prepared")
            try writeJSON(transaction, to: journalURL(transaction.id), maximumBytes: Self.maximumJournalFileBytes)
            try atomicWrite(newData, to: pageURL)
            proposal.status = "applied"
            try persist(&proposal)
            var completed = transaction
            completed.state = "applied"
            try writeJSON(completed, to: journalURL(transaction.id), maximumBytes: Self.maximumJournalFileBytes)
        }
    }

    func reject(_ id: UUID) throws {
        try withWriterLock {
            try reloadProposals()
            guard var proposal = staged[id], proposal.status == "proposed" || proposal.status == "stale" else {
                throw Failure("Proposal is unavailable or cannot be rejected.")
            }
            proposal.status = "rejected"
            try persist(&proposal)
        }
    }

    func rollback(_ id: UUID) throws {
        try withWriterLock {
            try reloadProposals()
            guard var proposal = staged[id], proposal.status == "applied" else {
                throw Failure("Only an applied proposal can be rolled back.")
            }
            let records = try transactionFiles().map { file in
                let transaction = try JSONDecoder().decode(Transaction.self,
                    from: Self.readRegularFile(file, maximumBytes: Self.maximumJournalFileBytes))
                guard transaction.id.uuidString.caseInsensitiveCompare(file.deletingPathExtension().lastPathComponent) == .orderedSame else {
                    throw Failure("Transaction filename does not match its ID.")
                }
                return transaction
            }
            guard var transaction = records.last(where: { $0.proposalID == id && $0.state == "applied" }),
                  transaction.pageID == proposal.pageID,
                  transaction.baseHash == transaction.previousData.map(Self.sha256),
                  (transaction.previousData?.count ?? 0) <= Self.maximumPageFileBytes,
                  Self.isHash(transaction.appliedHash), transaction.baseHash.map(Self.isHash) ?? true,
                  manager.fileExists(atPath: journalURL(transaction.id).path) else {
                throw Failure("The applied transaction journal is missing.")
            }
            let target = pageURL(transaction.pageID)
            try rejectSymlink(target)
            guard manager.fileExists(atPath: target.path), Self.sha256(try boundedData(target)) == transaction.appliedHash else {
                throw Failure("Rollback refused because the applied page was edited externally.")
            }
            transaction.state = "rollbackPrepared"
            try writeJSON(transaction, to: journalURL(transaction.id), maximumBytes: Self.maximumJournalFileBytes)
            if let previous = transaction.previousData { try atomicWrite(previous, to: target) }
            else { try removeFile(target) }
            proposal.status = "rolledBack"
            try persist(&proposal)
            transaction.state = "rolledBack"
            try writeJSON(transaction, to: journalURL(transaction.id), maximumBytes: Self.maximumJournalFileBytes)
        }
    }

    private func validate(_ proposal: MemoryProposal) throws {
        guard proposal.title.utf8.count > 0, proposal.title.utf8.count <= Self.maximumTitleBytes,
              proposal.body.utf8.count <= Self.maximumBodyBytes,
              proposal.source.utf8.count > 0, proposal.source.utf8.count <= Self.maximumSourceBytes,
              !proposal.title.utf8.contains(0), !proposal.body.utf8.contains(0), !proposal.source.utf8.contains(0),
              Self.kinds.contains(proposal.kind) else {
            throw Failure("Proposal fields exceed their limits or use an unsupported page kind.")
        }
    }

    private func encodePage(_ proposal: MemoryProposal, revision: Int) throws -> Data {
        let metadata = PageMetadata(schemaVersion: 1, id: proposal.pageID, title: proposal.title,
                                    projectID: projectID, kind: proposal.kind, reviewStatus: "approved",
                                    revision: revision, provenance: [proposal.source],
                                    reviewedAt: ISO8601DateFormatter().string(from: Date()))
        let json = try JSONEncoder.sorted.encode(metadata)
        var data = Data("---\n".utf8)
        data.append(json)
        data.append(Data("\n---\n\n".utf8))
        data.append(Data(proposal.body.utf8))
        guard data.count <= Self.maximumPageFileBytes else {
            throw Failure("Encoded memory page exceeds the 112,000 byte storage limit.")
        }
        return data
    }

    private func readPage(_ url: URL) throws -> MemoryPage {
        let data = try boundedData(url)
        let parsed = try parsePage(data, expectedID: UUID(uuidString: url.deletingPathExtension().lastPathComponent))
        guard parsed.metadata.projectID == projectID else { throw Failure("Page belongs to another project scope.") }
        return MemoryPage(id: parsed.metadata.id, title: parsed.metadata.title, body: parsed.body,
                          kind: parsed.metadata.kind, revision: parsed.metadata.revision, hash: Self.sha256(data))
    }

    private func parsePage(_ data: Data, expectedID: UUID?) throws -> (metadata: PageMetadata, body: String, revision: Int) {
        guard data.count <= Self.maximumPageFileBytes,
              let text = String(data: data, encoding: .utf8), text.hasPrefix("---\n"),
              let boundary = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) else {
            throw Failure("Memory page has malformed or oversized front matter.")
        }
        let jsonText = String(text[text.index(text.startIndex, offsetBy: 4)..<boundary.lowerBound])
        let jsonData = Data(jsonText.utf8)
        let object = try JSONSerialization.jsonObject(with: jsonData)
        guard let dictionary = object as? [String: Any], Set(dictionary.keys) == Set(PageMetadata.codingKeys) else {
            throw Failure("Memory page contains unsupported metadata.")
        }
        let metadata = try JSONDecoder().decode(PageMetadata.self, from: jsonData)
        guard metadata.schemaVersion == 1, metadata.id == expectedID, metadata.projectID == projectID,
              metadata.reviewStatus == "approved", metadata.revision > 0, Self.kinds.contains(metadata.kind),
              !metadata.provenance.isEmpty else { throw Failure("Memory page metadata is invalid.") }
        let start = boundary.upperBound
        let body = String(text[start...]).hasPrefix("\n") ? String(text[text.index(after: start)...]) : String(text[start...])
        guard metadata.title.utf8.count <= Self.maximumTitleBytes, body.utf8.count <= Self.maximumBodyBytes else {
            throw Failure("Memory page exceeds field limits.")
        }
        return (metadata, body, metadata.revision)
    }

    private func currentHash(for id: UUID) throws -> String? {
        let url = pageURL(id)
        try rejectSymlink(url)
        guard manager.fileExists(atPath: url.path) else { return nil }
        _ = try readPage(url)
        return Self.sha256(try boundedData(url))
    }

    private func markdownFiles(in directory: URL) throws -> [URL] {
        try rejectSymlink(directory)
        return try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            .filter { $0.pathExtension == "md" }
            .map { url in
                guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else {
                    throw Failure("Wiki contains a page without a generated UUID filename.")
                }
                try rejectSymlink(url)
                return url
            }
    }

    private func persist(_ proposal: inout MemoryProposal) throws {
        try writeJSON(proposal, to: proposalURL(proposal.id), maximumBytes: Self.maximumProposalFileBytes)
        staged[proposal.id] = proposal
    }

    private func reloadProposals() throws {
        var current: [UUID: MemoryProposal] = [:]
        try Self.loadProposals(from: proposalDirectory, into: &current)
        staged = current
    }

    private func withWriterLock<T>(_ operation: () throws -> T) throws -> T {
        try Self.withWriterLock(scope: scope, operation)
    }

    private static func withWriterLock<T>(scope: URL, _ operation: () throws -> T) throws -> T {
        let lock = scope.appendingPathComponent("Memory/.writer.lock")
        guard !containsSymlink(lock) else { throw Failure("Memory writer lock is a symlink.") }
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure("Could not open the memory writer lock.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw Failure("Could not acquire the memory writer lock.") }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try rejectSymlink(url)
        try Self.atomicWrite(data, to: url)
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let directoryFD = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directoryFD >= 0 else { throw Failure("Could not safely open the memory directory.") }
        defer { close(directoryFD) }
        let temporaryName = ".\(UUID().uuidString.lowercased()).tmp"
        let descriptor = openat(directoryFD, temporaryName, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW,
                                S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure("Could not create a staged memory file.") }
        var installed = false
        defer {
            close(descriptor)
            if !installed { unlinkat(directoryFD, temporaryName, 0) }
        }
        try data.withUnsafeBytes { bytes in
            var remaining = bytes.count
            var pointer = bytes.baseAddress
            while remaining > 0 {
                let count = Darwin.write(descriptor, pointer, remaining)
                guard count > 0 else { throw Failure("Could not write the staged memory file.") }
                remaining -= count
                pointer = pointer?.advanced(by: count)
            }
        }
        guard fsync(descriptor) == 0,
              renameat(directoryFD, temporaryName, directoryFD, url.lastPathComponent) == 0 else {
            throw Failure("Could not atomically install the memory file.")
        }
        installed = true
        _ = fsync(directoryFD)
    }

    private func removeFile(_ url: URL) throws {
        try rejectSymlink(url)
        let directoryFD = open(url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directoryFD >= 0 else { throw Failure("Could not safely open the memory directory.") }
        defer { close(directoryFD) }
        guard unlinkat(directoryFD, url.lastPathComponent, 0) == 0 else {
            throw Failure("Could not remove the rolled-back memory page.")
        }
        _ = fsync(directoryFD)
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL, maximumBytes: Int) throws {
        let data = try JSONEncoder.sorted.encode(value)
        guard data.count <= maximumBytes else { throw Failure("Encoded storage record exceeds its size limit.") }
        try atomicWrite(data, to: url)
    }

    private func boundedData(_ url: URL) throws -> Data {
        try rejectSymlink(url)
        return try Self.readRegularFile(url, maximumBytes: Self.maximumPageFileBytes)
    }

    private func rejectSymlink(_ url: URL) throws {
        guard url.path.hasPrefix(scope.path + "/") || url.path == scope.path,
              !Self.containsSymlink(url) else { throw Failure("Memory path escaped scope or contains a symlink.") }
    }

    private func pageURL(_ id: UUID) -> URL { wiki.appendingPathComponent(id.uuidString.lowercased() + ".md") }
    private func proposalURL(_ id: UUID) -> URL { proposalDirectory.appendingPathComponent(id.uuidString.lowercased() + ".json") }
    private func journalURL(_ id: UUID) -> URL { journalDirectory.appendingPathComponent(id.uuidString.lowercased() + ".json") }
    private func receiptURL(_ id: UUID) -> URL { receiptDirectory.appendingPathComponent(id.uuidString.lowercased() + ".json") }
    private func transactionFiles() throws -> [URL] {
        let files = try manager.contentsOfDirectory(at: journalDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        guard files.count <= Self.maximumProposals * 2 else { throw Failure("Transaction journal exceeds its entry limit.") }
        for file in files {
            guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else {
                throw Failure("Transaction journal contains an unsafe filename.")
            }
            try rejectSymlink(file)
            _ = try Self.regularFileSize(file, maximumBytes: Self.maximumJournalFileBytes)
        }
        return files
    }

    private static func containsSymlink(_ url: URL) -> Bool {
        var path = url.path
        while path != "/" {
            var info = stat()
            if lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFLNK { return true }
            path = (path as NSString).deletingLastPathComponent
        }
        return false
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func loadProposals(from directory: URL, into staged: inout [UUID: MemoryProposal]) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        guard files.count <= maximumProposals else { throw Failure("Project proposals exceed the 1,000 proposal limit.") }
        for file in files where file.pathExtension == "json" {
            guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else {
                throw Failure("Proposal storage contains an unsafe filename or symlink.")
            }
            let proposal = try JSONDecoder().decode(MemoryProposal.self,
                from: readRegularFile(file, maximumBytes: maximumProposalFileBytes))
            guard proposal.id.uuidString.caseInsensitiveCompare(file.deletingPathExtension().lastPathComponent) == .orderedSame else {
                throw Failure("Proposal filename does not match its ID.")
            }
            guard proposal.title.utf8.count > 0, proposal.title.utf8.count <= maximumTitleBytes,
                  proposal.body.utf8.count <= maximumBodyBytes,
                  proposal.source.utf8.count > 0, proposal.source.utf8.count <= maximumSourceBytes,
                  kinds.contains(proposal.kind),
                  ["proposed", "stale", "applied", "rejected", "rolledBack"].contains(proposal.status),
                  proposal.baseHash.map(isHash) ?? true else {
                throw Failure("Stored proposal contains invalid fields.")
            }
            staged[proposal.id] = proposal
        }
    }

    private static func loadReceipts(from directory: URL) throws -> [RetrievalReceipt] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        guard files.count <= maximumReceipts else { throw Failure("Retrieval receipt history exceeds 100 records.") }
        return try files.map { file in
            guard let fileID = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                throw Failure("Retrieval receipt storage contains an unsafe filename.")
            }
            let receipt = try JSONDecoder().decode(RetrievalReceipt.self,
                from: readRegularFile(file, maximumBytes: maximumReceiptFileBytes))
            guard receipt.id == fileID, ["mcp", "native"].contains(receipt.mechanism),
                  (0...maximumReturnedBytes).contains(receipt.returnedBytes),
                  receipt.pages.count <= maximumPages,
                  Set(receipt.pages.map(\.id)).count == receipt.pages.count,
                  receipt.pages.allSatisfy({ isHash($0.hash) }) else {
                throw Failure("Stored retrieval receipt contains invalid fields.")
            }
            return receipt
        }
    }

    private static func reconcile(journals: URL, wiki: URL, proposals: URL,
                                  staged: inout [UUID: MemoryProposal]) throws {
        let files = try FileManager.default.contentsOfDirectory(at: journals, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        guard files.count <= maximumProposals * 2 else { throw Failure("Transaction journal exceeds its entry limit.") }
        for file in files {
            guard let fileID = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                throw Failure("Transaction journal contains an unsafe filename.")
            }
            var transaction = try JSONDecoder().decode(Transaction.self,
                from: readRegularFile(file, maximumBytes: maximumJournalFileBytes))
            guard transaction.id == fileID, let proposal = staged[transaction.proposalID],
                  proposal.pageID == transaction.pageID,
                  transaction.baseHash == transaction.previousData.map(sha256),
                  (transaction.previousData?.count ?? 0) <= maximumPageFileBytes,
                  isHash(transaction.appliedHash), transaction.baseHash.map(isHash) ?? true else {
                throw Failure("Transaction journal contains inconsistent identifiers or hashes.")
            }
            let page = wiki.appendingPathComponent(transaction.pageID.uuidString.lowercased() + ".md")
            let current = FileManager.default.fileExists(atPath: page.path)
                ? sha256(try readRegularFile(page, maximumBytes: maximumPageFileBytes)) : nil
            switch transaction.state {
            case "prepared":
                if current == transaction.appliedHash {
                    try finish(transaction: &transaction, proposal: proposal, status: "applied",
                               state: "applied", proposalDirectory: proposals, journalFile: file, staged: &staged)
                } else if current == transaction.baseHash {
                    transaction.state = "aborted"
                    try writeEncoded(transaction, to: file, maximumBytes: maximumJournalFileBytes)
                } else {
                    throw Failure("An interrupted apply conflicts with an external page edit.")
                }
            case "rollbackPrepared":
                let restored = transaction.previousData.map(sha256)
                if current == restored {
                    try finish(transaction: &transaction, proposal: proposal, status: "rolledBack",
                               state: "rolledBack", proposalDirectory: proposals, journalFile: file, staged: &staged)
                } else if current == transaction.appliedHash {
                    transaction.state = "applied"
                    try writeEncoded(transaction, to: file, maximumBytes: maximumJournalFileBytes)
                } else {
                    throw Failure("An interrupted rollback conflicts with an external page edit.")
                }
            case "applied", "rolledBack", "aborted": break
            default: throw Failure("Transaction journal contains an unsupported state.")
            }
        }
    }

    private static func finish(transaction: inout Transaction, proposal: MemoryProposal, status: String, state: String,
                               proposalDirectory: URL, journalFile: URL,
                               staged: inout [UUID: MemoryProposal]) throws {
        var updated = proposal
        updated.status = status
        try writeEncoded(updated,
            to: proposalDirectory.appendingPathComponent(updated.id.uuidString.lowercased() + ".json"),
            maximumBytes: maximumProposalFileBytes)
        staged[updated.id] = updated
        transaction.state = state
        try writeEncoded(transaction, to: journalFile, maximumBytes: maximumJournalFileBytes)
    }

    private static func writeEncoded<T: Encodable>(_ value: T, to url: URL, maximumBytes: Int) throws {
        let data = try JSONEncoder.sorted.encode(value)
        guard data.count <= maximumBytes else { throw Failure("Encoded storage record exceeds its size limit.") }
        try atomicWrite(data, to: url)
    }

    private static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func regularFileSize(_ url: URL, maximumBytes: Int) throws -> Int {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= maximumBytes else {
            throw Failure("Stored file is not regular or exceeds its size limit.")
        }
        return Int(info.st_size)
    }

    private static func readRegularFile(_ url: URL, maximumBytes: Int) throws -> Data {
        _ = try regularFileSize(url, maximumBytes: maximumBytes)
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw Failure("Could not safely open a stored file.") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let data = try handle.readToEnd() ?? Data()
        guard data.count <= maximumBytes else { throw Failure("Stored file exceeds its size limit.") }
        return data
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

private struct PageMetadata: Codable {
    let schemaVersion: Int
    let id: UUID
    let title: String
    let projectID: String
    let kind: String
    let reviewStatus: String
    let revision: Int
    let provenance: [String]
    let reviewedAt: String

    static let codingKeys = ["schemaVersion", "id", "title", "projectID", "kind", "reviewStatus", "revision", "provenance", "reviewedAt"]
}

private struct Transaction: Codable {
    let id: UUID
    let proposalID: UUID
    let pageID: UUID
    let baseHash: String?
    let appliedHash: String
    let previousData: Data?
    var state: String
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
