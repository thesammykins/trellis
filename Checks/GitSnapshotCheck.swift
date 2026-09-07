import Foundation

@main struct Check {
    static func main() async throws {
        let result = try GitSnapshot.parse(branch: "main", status: Data(" M a\0?? new\0R  newname\0oldname\0".utf8), numstat: Data("2\t1\ta\0-\t-\tbinary\0".utf8))
        precondition(result.added == 2 && result.removed == 1 && result.changedFiles == 2 && result.untrackedFiles == 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-git-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let absent = try await GitSnapshot.load(directory: folder)
        precondition(absent == nil)
        func git(_ args: [String]) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", folder.path] + args
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit(); precondition(process.terminationStatus == 0)
        }
        try git(["init", "-b", "fixture"])
        try Data("one\ntwo\n".utf8).write(to: folder.appendingPathComponent("file"))
        try git(["add", "file"])
        let unborn = try await GitSnapshot.load(directory: folder)
        precondition(unborn?.branch == "fixture" && unborn?.added == 2)
        try git(["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-m", "fixture"])
        try Data("one\nthree\nfour\n".utf8).write(to: folder.appendingPathComponent("file"))
        let changed = try await GitSnapshot.load(directory: folder)
        precondition(changed?.added == 2 && changed?.removed == 1)
        print("Git snapshots: parser, non-repository, unborn and changed repository passed")
    }
}
