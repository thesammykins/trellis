import Foundation

struct AgentInstallation: Sendable {
    let executable: String
    let version: String

    static var searchPath: String {
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let defaults = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var paths = inherited.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        for path in defaults where !paths.contains(path) { paths.append(path) }
        return paths.joined(separator: ":")
    }

    static func inspect(_ profile: LaunchProfile) async throws -> AgentInstallation {
        try await Task.detached(priority: .utility) {
            let path = try profile.executable(searchPath: searchPath)
            let version = try probe(executable: path, arguments: ["--version"])
            return AgentInstallation(executable: path, version: version)
        }.value
    }

    // A file prevents a verbose/broken version command from filling a pipe and deadlocking.
    static func probe(executable: String, arguments: [String], timeout: TimeInterval = 5,
                      acceptedExitStatuses: Set<Int32> = [0], outputLimit: Int = 512, allowEmpty: Bool = false) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Trellis-probe-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("output")
        guard FileManager.default.createFile(atPath: output.path, contents: nil,
                                            attributes: [.posixPermissions: 0o600]) else {
            throw ProbeError("Could not create version output file.")
        }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning {
            let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if ProcessInfo.processInfo.systemUptime >= deadline || size > 65_536 {
                process.terminate()
                let stopDeadline = ProcessInfo.processInfo.systemUptime + 0.5
                while process.isRunning && ProcessInfo.processInfo.systemUptime < stopDeadline { Thread.sleep(forTimeInterval: 0.01) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw ProbeError("Version check exceeded its time or output limit.")
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        let reader = try FileHandle(forReadingFrom: output)
        defer { try? reader.close() }
        let data = try reader.read(upToCount: 65_537) ?? Data()
        guard data.count <= 65_536, acceptedExitStatuses.contains(process.terminationStatus) else {
            throw ProbeError("Version check failed (exit \(process.terminationStatus)).")
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowEmpty || !text.isEmpty else { throw ProbeError("The tool returned no version information.") }
        return String(text.prefix(min(65_536, max(0, outputLimit))))
    }
}

private struct ProbeError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
