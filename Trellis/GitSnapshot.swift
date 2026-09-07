import Foundation

struct GitSnapshot: Equatable, Sendable {
    let branch: String
    let added: Int
    let removed: Int
    let changedFiles: Int
    let untrackedFiles: Int

    static func load(directory: URL) async throws -> GitSnapshot? {
        let worker = Task.detached(priority: .utility) { try inspect(directory) }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func inspect(_ directory: URL) throws -> GitSnapshot? {
        guard directory.isFileURL, directory.path.hasPrefix("/") else { throw Failure("Invalid Git directory") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-git-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        func git(_ arguments: [String]) throws -> (Int32, Data) {
            try Task.checkCancellation()
            let file = root.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let output = try FileHandle(forWritingTo: file)
            defer { try? output.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["--no-pager", "-c", "core.fsmonitor=false", "-C", directory.path] + arguments
            var environment = ProcessInfo.processInfo.environment
            environment["GIT_OPTIONAL_LOCKS"] = "0"
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            defer {
                if process.isRunning { process.terminate(); kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            }
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw Failure("Git status timed out") }
                let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
                guard size <= 1_048_576 else { throw Failure("Git status exceeds 1 MiB") }
                Thread.sleep(forTimeInterval: 0.02)
            }
            let input = try FileHandle(forReadingFrom: file)
            defer { try? input.close() }
            let data = try input.read(upToCount: 1_048_577) ?? Data()
            guard data.count <= 1_048_576 else { throw Failure("Git status exceeds 1 MiB") }
            return (process.terminationStatus, data)
        }
        let check = try git(["rev-parse", "--is-inside-work-tree"])
        guard check.0 == 0, String(decoding: check.1, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "true" else { return nil }
        let symbolic = try git(["symbolic-ref", "--short", "-q", "HEAD"])
        let branchResult = symbolic.0 == 0 ? symbolic : try git(["rev-parse", "--short", "HEAD"])
        guard branchResult.0 == 0 else { throw Failure("Git branch is unavailable") }
        let branch = String(decoding: branchResult.1, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let status = try git(["status", "--porcelain=v1", "-z", "--untracked-files=normal"])
        guard status.0 == 0 else { throw Failure("Git status is unavailable") }
        let head = try git(["rev-parse", "--verify", "HEAD"])
        let options = ["diff", "--no-ext-diff", "--no-textconv", "--numstat", "-z"]
        var stats: Data
        if head.0 == 0 {
            let result = try git(options + ["HEAD", "--"])
            guard result.0 == 0 else { throw Failure("Git diff is unavailable") }
            stats = result.1
        } else {
            // With no first commit, report staged plus unstaged deltas, excluding untracked contents.
            let staged = try git(options + ["--cached", "--"]), unstaged = try git(options + ["--"])
            guard staged.0 == 0, unstaged.0 == 0 else { throw Failure("Git diff is unavailable") }
            stats = staged.1 + unstaged.1
        }
        return try parse(branch: branch, status: status.1, numstat: stats)
    }

    static func parse(branch: String, status: Data, numstat: Data) throws -> GitSnapshot {
        guard branch.utf8.count <= 256 else { throw Failure("Git branch name is too long") }
        var changed = 0, untracked = 0
        let records = status.split(separator: 0)
        var index = 0
        while index < records.count {
            let record = records[index]
            guard record.count >= 3, record[record.startIndex + 2] == 32 else { throw Failure("Invalid Git status") }
            let codes = Array(record.prefix(2))
            if codes == [63, 63] { untracked += 1 }
            else { changed += 1 }
            index += codes.contains(82) || codes.contains(67) ? 2 : 1
        }
        var added = 0, removed = 0
        let changes = numstat.split(separator: 0, omittingEmptySubsequences: false)
        index = 0
        while index < changes.count, !changes[index].isEmpty {
            let parts = changes[index].split(separator: 9, maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { throw Failure("Invalid Git diff statistics") }
            func number(_ bytes: Data.SubSequence) throws -> Int {
                let value = String(decoding: bytes, as: UTF8.self)
                if value == "-" { return 0 }
                guard let n = Int(value), (0...100_000_000).contains(n) else { throw Failure("Invalid Git line count") }
                return n
            }
            added += try number(parts[0]); removed += try number(parts[1])
            index += parts[2].isEmpty ? 3 : 1
        }
        return .init(branch: branch, added: added, removed: removed, changedFiles: changed, untrackedFiles: untracked)
    }
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }
}
