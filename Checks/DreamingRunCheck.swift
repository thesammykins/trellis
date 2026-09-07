import Foundation

@main
enum DreamingRunCheck {
    actor Calls {
        var count = 0
        func next(_ output: String) -> String { count += 1; return output }
    }

    enum FixtureError: Error { case failed }

    actor RetryCalls {
        var count = 0
        func next() throws -> String {
            count += 1
            if count == 1 { throw FixtureError.failed }
            return #"{"proposals":[]}"#
        }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-dreaming-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try MemoryStore(root: root.appendingPathComponent("memory"), projectID: "enabled-project")
        let seed = try await store.propose(title: "Approved input", body: "Keep provider calls tool-free.",
                                           kind: "constraint", source: "fixture")
        try await store.approve(seed.id)
        let configuration = DirectModelConfiguration(baseURL: "https://api.example.test/v1", model: "fixture-model",
                                                     api: .responses, maxOutputTokens: 256)

        let emptyCalls = Calls()
        let emptyStore = try MemoryStore(root: root.appendingPathComponent("empty-memory"), projectID: "enabled-project")
        let empty = try DreamingRun(directory: root.appendingPathComponent("empty-runs")) { _, _, _ in
            await emptyCalls.next(#"{"proposals":[]}"#)
        }
        let emptyMessage = try await empty.run(store: emptyStore, configuration: configuration, apiKey: "fixture")
        let emptyCallCount = await emptyCalls.count
        let emptyRecords = try await empty.records()
        precondition(emptyMessage.contains("No provider request"))
        precondition(emptyCallCount == 0)
        precondition(emptyRecords.single?.status == "skipped")

        let boundedSnapshotRoot = root.appendingPathComponent("bounded-snapshot-memory")
        let boundedSnapshotStore = try MemoryStore(root: boundedSnapshotRoot, projectID: "snapshot-project")
        let wiki = try onlyDirectory(named: "wiki", beneath: boundedSnapshotRoot)
        try writeApprovedPage(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                              title: "Oversized", body: String(repeating: "x", count: 70 * 1024),
                              projectID: "snapshot-project", to: wiki)
        try writeApprovedPage(id: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
                              title: "Fits", body: "Include this approved page.",
                              projectID: "snapshot-project", to: wiki)
        let boundedSnapshotCalls = Calls()
        let boundedSnapshot = try DreamingRun(directory: root.appendingPathComponent("bounded-snapshot-runs")) { _, _, _ in
            await boundedSnapshotCalls.next(#"{"proposals":[]}"#)
        }
        _ = try await boundedSnapshot.run(store: boundedSnapshotStore, configuration: configuration, apiKey: "fixture")
        let boundedSnapshotCallCount = await boundedSnapshotCalls.count
        precondition(boundedSnapshotCallCount == 1)

        let calls = Calls()
        let run = try DreamingRun(directory: root.appendingPathComponent("runs")) { _, _, _ in
            await calls.next(#"{"proposals":[{"title":"Consolidated","body":"Keep direct requests tool-free.","kind":"lesson"}]}"#)
        }
        _ = try await run.run(store: store, configuration: configuration, apiKey: "fixture")
        let staged = try await store.proposals()
        precondition(staged.filter { $0.title == "Consolidated" && $0.status == "proposed" }.count == 1)
        let approvedPages = try await store.pages()
        precondition(approvedPages.count == 1)
        let reopened = try DreamingRun(directory: root.appendingPathComponent("runs")) { _, _, _ in
            await calls.next(#"{"proposals":[]}"#)
        }
        _ = try await reopened.run(store: store, configuration: configuration, apiKey: "fixture")
        let successfulRetryMessage = try await reopened.run(
            store: store, configuration: configuration, apiKey: "fixture", retry: true)
        let callCount = await calls.count
        precondition(callCount == 1)
        precondition(successfulRetryMessage.contains("already succeeded"))

        // ISO-8601 records share a second; UUID order must not hide a successful retry.
        let tiedDirectory = root.appendingPathComponent("tied-runs")
        try FileManager.default.createDirectory(at: tiedDirectory, withIntermediateDirectories: false)
        let successfulRecord = try await run.records().single!
        let tiedEncoder = JSONEncoder()
        tiedEncoder.dateEncodingStrategy = .iso8601
        for (id, status) in [("00000000-0000-0000-0000-000000000001", "succeeded"),
                             ("ffffffff-ffff-ffff-ffff-ffffffffffff", "failed")] {
            let record = DreamingRecord(id: UUID(uuidString: id)!, status: status, message: "Fixture", date: successfulRecord.date,
                deduplicationKey: successfulRecord.deduplicationKey, snapshotHash: successfulRecord.snapshotHash,
                model: successfulRecord.model, endpoint: successfulRecord.endpoint, api: successfulRecord.api,
                sources: successfulRecord.sources)
            try tiedEncoder.encode(record).write(to: tiedDirectory.appendingPathComponent(id + ".json"))
        }
        let tiedCalls = Calls()
        let tied = try DreamingRun(directory: tiedDirectory) { _, _, _ in
            await tiedCalls.next(#"{"proposals":[]}"#)
        }
        for retry in [false, true] {
            let message = try await tied.run(store: store, configuration: configuration, apiKey: "fixture", retry: retry)
            precondition(message.contains("already succeeded"), "Successful retries must survive timestamp ties")
        }
        let tiedCallCount = await tiedCalls.count
        precondition(tiedCallCount == 0)

        let invalidStore = try MemoryStore(root: root.appendingPathComponent("invalid-memory"), projectID: "enabled-project")
        let invalidSeed = try await invalidStore.propose(title: "Approved", body: "Fixture", kind: "reference", source: "fixture")
        try await invalidStore.approve(invalidSeed.id)
        let invalid = try DreamingRun(directory: root.appendingPathComponent("invalid-runs")) { _, _, _ in
            #"{"proposals":[{"title":"Valid","body":"Would be partial","kind":"lesson"},{"title":"Bad","body":"Nope","kind":"unsupported"}]}"#
        }
        try await expectFailure { try await invalid.run(store: invalidStore, configuration: configuration, apiKey: "fixture") }
        let invalidProposals = try await invalidStore.proposals()
        let invalidRecords = try await invalid.records()
        precondition(invalidProposals.count == 1 && invalidProposals.allSatisfy { $0.title != "Valid" })
        precondition(invalidRecords.single?.status == "failed")

        let failedCalls = RetryCalls()
        let failedDirectory = root.appendingPathComponent("failed-runs")
        let failed = try DreamingRun(directory: failedDirectory) { _, _, _ in try await failedCalls.next() }
        try await expectFailure { try await failed.run(store: invalidStore, configuration: configuration, apiKey: "fixture") }
        let failedRecords = try await failed.records()
        precondition(failedRecords.single?.status == "failed")
        let failedReopened = try DreamingRun(directory: failedDirectory) { _, _, _ in try await failedCalls.next() }
        let automaticRetryMessage = try await failedReopened.run(
            store: invalidStore, configuration: configuration, apiKey: "fixture")
        let callsBeforeRetry = await failedCalls.count
        precondition(callsBeforeRetry == 1 && automaticRetryMessage.contains("explicit retry"))
        let explicitRetryMessage = try await failedReopened.run(
            store: invalidStore, configuration: configuration, apiKey: "fixture", retry: true)
        let callsAfterRetry = await failedCalls.count
        let retriedRecords = try await failedReopened.records()
        precondition(callsAfterRetry == 2 && retriedRecords.count == 2)
        precondition(explicitRetryMessage.contains("prior uncertain or failed attempt"))

        let cancelled = try DreamingRun(directory: root.appendingPathComponent("cancelled-runs")) { _, _, _ in throw CancellationError() }
        try await expectFailure { try await cancelled.run(store: invalidStore, configuration: configuration, apiKey: "fixture") }
        let cancelledRecords = try await cancelled.records()
        let invalidPages = try await invalidStore.pages()
        precondition(cancelledRecords.single?.status == "cancelled")
        precondition(invalidPages.count == 1)

        let partialStore = try MemoryStore(root: root.appendingPathComponent("partial-memory"), projectID: "enabled-project")
        let partialSeed = try await partialStore.propose(title: "Approved", body: "Fixture", kind: "reference", source: "fixture")
        try await partialStore.approve(partialSeed.id)
        let proposalDirectory = try onlyDirectory(named: "proposals", beneath: root.appendingPathComponent("partial-memory"))
        for _ in 0..<998 {
            let id = UUID()
            let proposal = MemoryProposal(id: id, title: "Capacity", body: "Fixture", kind: "reference",
                                          source: "fixture", pageID: UUID(), baseHash: nil, status: "rejected")
            try JSONEncoder().encode(proposal).write(
                to: proposalDirectory.appendingPathComponent(id.uuidString.lowercased() + ".json"))
        }
        let partialCalls = Calls()
        let partialDirectory = root.appendingPathComponent("partial-runs")
        let partial = try DreamingRun(directory: partialDirectory) { _, _, _ in
            await partialCalls.next(#"{"proposals":[{"title":"First","body":"Staged","kind":"lesson"},{"title":"Second","body":"Blocked","kind":"lesson"}]}"#)
        }
        try await expectFailure { try await partial.run(store: partialStore, configuration: configuration, apiKey: "fixture") }
        let partialRecords = try await partial.records()
        let partialProposals = try await partialStore.proposals()
        precondition(partialRecords.single?.message.contains("after staging 1 proposal") == true)
        precondition(partialProposals.count == MemoryStore.maximumProposals)
        let partialReopened = try DreamingRun(directory: partialDirectory) { _, _, _ in
            await partialCalls.next(#"{"proposals":[]}"#)
        }
        let partialDedupMessage = try await partialReopened.run(
            store: partialStore, configuration: configuration, apiKey: "fixture")
        let partialCallCount = await partialCalls.count
        precondition(partialCallCount == 1)
        precondition(partialDedupMessage.contains("after staging 1 proposal"))

        let boundedDirectory = root.appendingPathComponent("bounded-runs")
        _ = try DreamingRun(directory: boundedDirectory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        for _ in 0...1_000 {
            let id = UUID()
            let record = DreamingRecord(id: id, status: "skipped", message: "Fixture", date: Date(),
                                        deduplicationKey: String(repeating: "a", count: 64),
                                        snapshotHash: String(repeating: "b", count: 64), model: "fixture",
                                        endpoint: "https://example.test/v1", api: .responses, sources: [])
            try encoder.encode(record).write(to: boundedDirectory.appendingPathComponent(id.uuidString.lowercased() + ".json"))
        }
        expectInitFailure(boundedDirectory)

        let oversizedDirectory = root.appendingPathComponent("oversized-runs")
        _ = try DreamingRun(directory: oversizedDirectory)
        try Data(repeating: 0x20, count: 96 * 1024 + 1).write(
            to: oversizedDirectory.appendingPathComponent(UUID().uuidString.lowercased() + ".json"))
        expectInitFailure(oversizedDirectory)

        print("PASS dreaming skip-empty, pending-only proposals, restart deduplication, truthful partial failure, bounded records, validation, and cancellation")
    }

    @MainActor
    private static func expectFailure(_ operation: () async throws -> String) async throws {
        do { _ = try await operation(); preconditionFailure("Expected failure") } catch {}
    }

    private static func expectInitFailure(_ directory: URL) {
        do { _ = try DreamingRun(directory: directory); preconditionFailure("Expected record validation failure") }
        catch {}
    }

    private static func onlyDirectory(named name: String, beneath root: URL) throws -> URL {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey])!
        let matches = enumerator.compactMap { $0 as? URL }.filter {
            $0.lastPathComponent == name && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        precondition(matches.count == 1)
        return matches[0]
    }

    private static func writeApprovedPage(id: UUID, title: String, body: String, projectID: String, to wiki: URL) throws {
        let metadata: [String: Any] = [
            "schemaVersion": 1, "id": id.uuidString, "title": title, "projectID": projectID,
            "kind": "reference", "reviewStatus": "approved", "revision": 1,
            "provenance": ["fixture"], "reviewedAt": "2026-09-07T00:00:00Z",
        ]
        let header = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        var data = Data("---\n".utf8)
        data.append(header)
        data.append(Data("\n---\n\n\(body)".utf8))
        try data.write(to: wiki.appendingPathComponent(id.uuidString.lowercased() + ".md"))
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
