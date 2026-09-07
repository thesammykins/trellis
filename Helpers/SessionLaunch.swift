import Darwin
import Foundation

private struct LaunchEnvelope: Decodable {
    let executable: String
    let arguments: [String]
    let workingDirectory: String
}

private struct LaunchFailure: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

private func launch() throws {
    guard CommandLine.arguments.count == 1,
          let rawPath = getenv("TRELLIS_LAUNCH_ENVELOPE") else {
        throw LaunchFailure("Expected a launch envelope and no command-line arguments")
    }
    let path = String(cString: rawPath)
    guard path.hasPrefix("/") else { throw LaunchFailure("Envelope path must be absolute") }
    let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
    guard descriptor >= 0 else { throw LaunchFailure("Cannot open launch envelope") }
    defer { close(descriptor) }
    var info = stat()
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0,
          fstat(descriptor, &info) == 0,
          (info.st_mode & S_IFMT) == S_IFREG,
          info.st_uid == getuid(), (info.st_mode & 0o7777) == 0o600,
          info.st_nlink == 1, info.st_size > 0, info.st_size <= 65_536 else {
        throw LaunchFailure("Launch envelope must be an unused, owned, private regular file under 64 KiB")
    }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = read(descriptor, &buffer, buffer.count)
        if count < 0 && errno == EINTR { continue }
        guard count >= 0 else { throw LaunchFailure("Cannot read launch envelope") }
        if count == 0 { break }
        guard data.count + count <= 65_536 else { throw LaunchFailure("Launch envelope exceeds 64 KiB") }
        data.append(contentsOf: buffer.prefix(count))
    }
    let envelope: LaunchEnvelope
    do { envelope = try JSONDecoder().decode(LaunchEnvelope.self, from: data) }
    catch { throw LaunchFailure("Invalid launch envelope JSON") }
    let values = [envelope.executable, envelope.workingDirectory] + envelope.arguments
    guard envelope.executable.hasPrefix("/"), envelope.workingDirectory.hasPrefix("/"),
          envelope.arguments.count <= 256,
          values.allSatisfy({ !$0.utf8.contains(0) && $0.utf8.count <= 16_384 }),
          values.reduce(0, { $0 + $1.utf8.count + 1 }) <= 65_536 else {
        throw LaunchFailure("Invalid executable, working directory or arguments")
    }
    guard chdir(envelope.workingDirectory) == 0 else { throw LaunchFailure("Cannot enter working directory") }
    // Holding the lock until exec prevents concurrent reuse of the same open file.
    guard unlink(path) == 0 else { throw LaunchFailure("Cannot consume launch envelope") }
    guard unsetenv("TRELLIS_LAUNCH_ENVELOPE") == 0 else { throw LaunchFailure("Cannot clear launch envelope environment") }
    var arguments: [UnsafeMutablePointer<CChar>?] = []
    defer { arguments.forEach { free($0) } }
    for value in [envelope.executable] + envelope.arguments {
        guard let copy = strdup(value) else { throw LaunchFailure("Cannot allocate launch arguments") }
        arguments.append(copy)
    }
    arguments.append(nil)
    execv(envelope.executable, &arguments)
    throw LaunchFailure("Cannot execute requested program: \(String(cString: strerror(errno)))")
}

do { try launch() }
catch {
    FileHandle.standardError.write(Data("Trellis launch failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
