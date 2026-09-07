import Foundation

@main
enum MemoryStoreCheck {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-memory-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(root: root, projectID: "project-a")
        let created = try await store.propose(title: "Terminal boundary", body: "Keep memory away from terminal input.",
                                          kind: "constraint", source: "fixture-session")
        try await store.approve(created.id)
        let pages = try await store.pages(query: "terminal input")
        precondition(pages.count == 1 && pages[0].revision == 1)
        let exported = try await store.export(pages[0].id)
        precondition(String(decoding: exported, as: UTF8.self).contains("fixture-session"))

        let receipt = try await store.recordRetrieval(pages: pages, returnedBytes: 321)
        precondition(receipt.mechanism == "mcp" && receipt.returnedBytes == 321)
        precondition(receipt.pages.single?.id == pages[0].id && receipt.pages.single?.hash == pages[0].hash)
        let storedReceipts = try await store.receipts()
        precondition(storedReceipts.single?.id == receipt.id)
        try await expectFailure {
            _ = try await store.recordRetrieval(pages: pages, returnedBytes: MemoryStore.maximumReturnedBytes + 1)
        }
        for index in 0..<100 {
            _ = try await store.recordRetrieval(pages: pages, returnedBytes: index)
        }
        let retainedReceipts = try await store.receipts()
        let retainedPages = try await store.pages()
        precondition(retainedReceipts.count == MemoryStore.maximumReceipts)
        precondition(retainedPages.count == 1)
        let receiptDirectory = try onlyDirectory(named: "receipts", beneath: root)
        let receiptText = try FileManager.default.contentsOfDirectory(at: receiptDirectory, includingPropertiesForKeys: nil)
            .map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        precondition(!receiptText.contains("terminal input") && !receiptText.contains("Keep memory away"))

        let stale = try await store.propose(title: "Changed", body: "Replacement", kind: "decision",
                                       pageID: pages[0].id, source: "fixture-session")
        let pageFile = try onlyMarkdownFile(beneath: root)
        try Data("external edit".utf8).write(to: pageFile)
        try await expectFailure { try await store.approve(stale.id) }

        let isolated = try MemoryStore(root: root, projectID: "project-b")
        let isolatedPages = try await isolated.pages()
        let isolatedReceipts = try await isolated.receipts()
        precondition(isolatedPages.isEmpty)
        precondition(isolatedReceipts.isEmpty)

        // Applying an old review must preserve the replacement proposal until it is reviewed again.
        let isolatedRoot = root.appendingPathComponent("proposal-review")
        let reviewStore = try MemoryStore(root: isolatedRoot, projectID: "project-a")
        let reviewed = try await reviewStore.propose(title: "Reviewed content", body: "Displayed body", kind: "decision", source: "fixture")
        let reviewFile = try onlyJSONFile(in: onlyDirectory(named: "proposals", beneath: isolatedRoot))
        let changed = MemoryProposal(id: reviewed.id, title: reviewed.title, body: "Changed after review", kind: reviewed.kind,
                                     source: reviewed.source, pageID: reviewed.pageID, baseHash: reviewed.baseHash, status: reviewed.status)
        try JSONEncoder().encode(changed).write(to: reviewFile)
        try await expectFailure { try await reviewStore.approve(reviewed.id, expectedProposal: reviewed) }
        let unappliedPages = try await reviewStore.pages()
        precondition(unappliedPages.isEmpty)
        try await reviewStore.approve(changed.id, expectedProposal: changed)
        let reviewedPages = try await reviewStore.pages()
        precondition(reviewedPages.single?.body == changed.body)

        // Externally edited metadata must never turn proposal approval into an overflow trap.
        let revisionText = String(decoding: exported, as: UTF8.self)
            .replacingOccurrences(of: "\"revision\":1", with: "\"revision\":\(Int.max)")
        try Data(revisionText.utf8).write(to: pageFile)
        try await expectFailure {
            _ = try await store.propose(title: "Old draft", body: "Replacement", kind: "decision",
                                       pageID: pages[0].id, source: "fixture", expectedBaseHash: pages[0].hash)
        }
        let revisionLimited = try await store.propose(title: "Changed", body: "Replacement", kind: "decision",
                                                      pageID: pages[0].id, source: "fixture")
        try await expectFailure { try await store.approve(revisionLimited.id) }
        let unchangedRevision = try await store.export(pages[0].id)
        precondition(unchangedRevision == Data(revisionText.utf8))
        let revisionProposals = try await store.proposals()
        precondition(revisionProposals.first { $0.id == revisionLimited.id }?.status == "proposed")

        try Data("---\n{}\n---\ncorrupt".utf8).write(to: pageFile)
        try await expectFailure { _ = try await store.pages() }

        let cleanRoot = root.appendingPathComponent("rollback")
        let rollbackStore = try MemoryStore(root: cleanRoot, projectID: "project-a")
        let rollback = try await rollbackStore.propose(title: "Rollback", body: "Applied body", kind: "lesson", source: "fixture")
        try await rollbackStore.approve(rollback.id)
        let rollbackFile = try onlyMarkdownFile(beneath: cleanRoot)
        try Data("external edit".utf8).write(to: rollbackFile)
        try await expectFailure { try await rollbackStore.rollback(rollback.id) }
        let externallyEdited = try String(contentsOf: rollbackFile, encoding: .utf8)
        precondition(externallyEdited == "external edit")

        let recoveryRoot = root.appendingPathComponent("recovery")
        let recoveryStore = try MemoryStore(root: recoveryRoot, projectID: "project-a")
        let pending = try await recoveryStore.propose(title: "Pending", body: "Not written", kind: "reference", source: "fixture")
        let recoveryJournal = try onlyDirectory(named: "journal", beneath: recoveryRoot)
        let interruptedID = UUID()
        let interrupted: [String: Any] = [
            "id": interruptedID.uuidString, "proposalID": pending.id.uuidString,
            "pageID": pending.pageID.uuidString, "baseHash": NSNull(),
            "appliedHash": String(repeating: "a", count: 64), "previousData": NSNull(), "state": "prepared",
        ]
        try JSONSerialization.data(withJSONObject: interrupted).write(
            to: recoveryJournal.appendingPathComponent(interruptedID.uuidString.lowercased() + ".json"))
        let recovered = try MemoryStore(root: recoveryRoot, projectID: "project-a")
        let recoveredProposals = try await recovered.proposals()
        precondition(recoveredProposals.first { $0.id == pending.id }?.status == "proposed")
        let recoveredJournal = try JSONSerialization.jsonObject(with: Data(contentsOf:
            recoveryJournal.appendingPathComponent(interruptedID.uuidString.lowercased() + ".json"))) as! [String: Any]
        precondition(recoveredJournal["state"] as? String == "aborted")

        let rollbackRecoveryRoot = root.appendingPathComponent("rollback-recovery")
        let rollbackRecoveryStore = try MemoryStore(root: rollbackRecoveryRoot, projectID: "project-a")
        let applied = try await rollbackRecoveryStore.propose(title: "Applied", body: "Remove me", kind: "lesson", source: "fixture")
        try await rollbackRecoveryStore.approve(applied.id)
        let appliedPage = try onlyMarkdownFile(beneath: rollbackRecoveryRoot)
        let appliedJournal = try onlyJSONFile(in: onlyDirectory(named: "journal", beneath: rollbackRecoveryRoot))
        var journalObject = try JSONSerialization.jsonObject(with: Data(contentsOf: appliedJournal)) as! [String: Any]
        journalObject["state"] = "rollbackPrepared"
        try JSONSerialization.data(withJSONObject: journalObject).write(to: appliedJournal)
        try FileManager.default.removeItem(at: appliedPage)
        let rollbackRecovered = try MemoryStore(root: rollbackRecoveryRoot, projectID: "project-a")
        let rollbackRecoveredProposals = try await rollbackRecovered.proposals()
        precondition(rollbackRecoveredProposals.first { $0.id == applied.id }?.status == "rolledBack")

        let retryRoot = root.appendingPathComponent("rollback-retry")
        let retryStore = try MemoryStore(root: retryRoot, projectID: "project-a")
        let retryProposal = try await retryStore.propose(title: "Retry", body: "Applied", kind: "lesson", source: "fixture")
        try await retryStore.approve(retryProposal.id)
        let retryJournal = try onlyJSONFile(in: onlyDirectory(named: "journal", beneath: retryRoot))
        var retryObject = try JSONSerialization.jsonObject(with: Data(contentsOf: retryJournal)) as! [String: Any]
        retryObject["state"] = "rollbackPrepared"
        try JSONSerialization.data(withJSONObject: retryObject).write(to: retryJournal)
        let retryRecovered = try MemoryStore(root: retryRoot, projectID: "project-a")
        let retryRecoveredProposals = try await retryRecovered.proposals()
        precondition(retryRecoveredProposals.first { $0.id == retryProposal.id }?.status == "applied")
        try await retryRecovered.rollback(retryProposal.id)
        let retryPages = try await retryRecovered.pages()
        precondition(retryPages.isEmpty)

        let serializationRoot = root.appendingPathComponent("serialized-size")
        let serializationStore = try MemoryStore(root: serializationRoot, projectID: "project-a")
        _ = try await serializationStore.propose(title: "Escaped", body: String(repeating: "\n", count: 60_000),
                                                 kind: "reference", source: "fixture")
        let serializationReloaded = try MemoryStore(root: serializationRoot, projectID: "project-a")
        let serializationProposals = try await serializationReloaded.proposals()
        precondition(serializationProposals.count == 1)
        try await expectFailure {
            _ = try await serializationReloaded.propose(title: "Too escaped",
                body: String(repeating: "\u{1}", count: 100_000), kind: "reference", source: "fixture")
        }
        let afterRejectedSerialization = try MemoryStore(root: serializationRoot, projectID: "project-a")
        let afterRejectedSerializationProposals = try await afterRejectedSerialization.proposals()
        precondition(afterRejectedSerializationProposals.count == 1)

        let oversizedPage = try await afterRejectedSerialization.propose(title: "Large page",
            body: String(repeating: "a", count: 100_000), kind: "reference",
            source: String(repeating: "\u{1}", count: 4_000))
        try await expectFailure { try await afterRejectedSerialization.approve(oversizedPage.id) }
        let afterRejectedPage = try MemoryStore(root: serializationRoot, projectID: "project-a")
        let afterRejectedPageProposals = try await afterRejectedPage.proposals()
        precondition(afterRejectedPageProposals.count == 2)

        try assertSymlinkRejected(root: root.appendingPathComponent("proposal-link"), directory: "proposals")
        try assertSymlinkRejected(root: root.appendingPathComponent("journal-link"), directory: "journal")
        let receiptLinkRoot = root.appendingPathComponent("receipt-link")
        let receiptLinkStore = try MemoryStore(root: receiptLinkRoot, projectID: "project-a")
        let receiptLink = try onlyDirectory(named: "receipts", beneath: receiptLinkRoot)
            .appendingPathComponent(UUID().uuidString.lowercased() + ".json")
        try FileManager.default.createSymbolicLink(at: receiptLink, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        try await expectFailure { _ = try await receiptLinkStore.receipts() }
        print("PASS memory apply/read/stale/scope/corrupt/rollback, retrieval receipts, interrupted recovery, and symlink rejection")
    }

    private static func onlyMarkdownFile(beneath root: URL) throws -> URL {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
        precondition(files.count == 1)
        return files[0]
    }

    private static func onlyDirectory(named name: String, beneath root: URL) throws -> URL {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])!
        let matches = enumerator.compactMap { $0 as? URL }.filter {
            $0.lastPathComponent == name && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        precondition(matches.count == 1)
        return matches[0]
    }

    private static func onlyJSONFile(in directory: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        precondition(files.count == 1)
        return files[0]
    }

    private static func assertSymlinkRejected(root: URL, directory: String) throws {
        _ = try MemoryStore(root: root, projectID: "project-a")
        let target = try onlyDirectory(named: directory, beneath: root)
            .appendingPathComponent(UUID().uuidString.lowercased() + ".json")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        do {
            _ = try MemoryStore(root: root, projectID: "project-a")
            preconditionFailure("Symlinked \(directory) entry was accepted")
        } catch {}
    }

    @MainActor
    private static func expectFailure(_ operation: () async throws -> Void) async throws {
        do { try await operation(); preconditionFailure("Expected failure") } catch {}
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
