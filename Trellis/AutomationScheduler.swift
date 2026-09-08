import Combine
import Darwin
import Foundation

struct AutomationSchedule: Codable, Equatable, Identifiable, Sendable {
    enum Cadence: String, Codable, CaseIterable, Sendable { case interval, daily }
    enum Outcome: String, Codable, Sendable { case running, succeeded, failed, cancelled, interrupted, skipped }
    struct Run: Codable, Equatable, Sendable {
        var startedAt: Date
        var finishedAt: Date?
        var outcome: Outcome
        var output: String
        var exitCode: Int32?
    }

    var id = UUID()
    var name = ""
    var executable = ""
    var arguments: [String] = []
    var directory = ""
    var cadence = Cadence.interval
    var intervalMinutes = 60
    var hour = 9
    var minute = 0
    var timeZoneID = TimeZone.current.identifier
    var enabled = false
    var nextRun: Date?
    var lastRun: Run?

    var commandReview: String {
        let argumentsJSON = (try? JSONEncoder().encode(arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return "Executable: \(executable)\nArguments: \(argumentsJSON)\nWorking directory: \(directory)"
    }

    var frequency: String {
        if cadence == .interval { return "Every \(intervalMinutes) minute\(intervalMinutes == 1 ? "" : "s")" }
        return String(format: "Daily at %02d:%02d", hour, minute) + " · \(timeZoneID)"
    }

    func nextDate(after date: Date) -> Date? {
        guard (1...10_080).contains(intervalMinutes), (0...23).contains(hour),
              (0...59).contains(minute), let zone = TimeZone(identifier: timeZoneID) else { return nil }
        if cadence == .interval { return date.addingTimeInterval(Double(intervalMinutes) * 60) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }

    func validated(checkResources: Bool = true) throws -> Self {
        try NativeAgentTools.validateCommand(executable: executable, arguments: arguments)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 100,
              !name.utf8.contains(0), arguments.reduce(0, { $0 + $1.utf8.count }) <= 16_384,
              directory.hasPrefix("/"), directory != "/", directory.utf8.count <= 4_096,
              !directory.utf8.contains(0), URL(fileURLWithPath: directory).standardizedFileURL.path == directory,
              nextDate(after: Date()) != nil,
              nextRun.map(Self.validDate) ?? true,
              lastRun.map({ Self.validDate($0.startedAt) && ($0.finishedAt.map(Self.validDate) ?? true)
                  && $0.output.utf8.count <= AutomationScheduler.maximumOutputBytes }) ?? true else {
            throw AutomationFailure("Use a name up to 100 bytes, an absolute working directory, and a valid schedule. Arguments may total at most 16 KiB.")
        }
        guard checkResources else { return self }
        var result = self
        result.directory = URL(fileURLWithPath: directory).resolvingSymlinksInPath().standardizedFileURL.path
        result.executable = URL(fileURLWithPath: executable).resolvingSymlinksInPath().standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: result.directory, isDirectory: &isDirectory), isDirectory.boolValue,
              result.directory != "/", FileManager.default.isExecutableFile(atPath: result.executable),
              (try URL(fileURLWithPath: result.executable).resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
            throw AutomationFailure("Choose an existing local folder and executable file.")
        }
        return result
    }

    private static func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && (0...253_402_300_799).contains(date.timeIntervalSince1970)
    }
}

@MainActor
final class AutomationScheduler: ObservableObject {
    nonisolated static let maximumOutputBytes = 8 * 1024
    private static let maximumFileBytes = 1024 * 1024
    private static let maximumSchedules = 32
    @Published private(set) var schedules: [AutomationSchedule] = []
    @Published private(set) var runningIDs: Set<UUID> = []
    @Published private(set) var storageError: String?
    private struct State: Codable { let version: Int; let schedules: [AutomationSchedule] }
    private let storageURL: URL?
    private var timer: Timer?
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var isStopping = false

    init(storageDirectory: URL? = nil) {
        var file: URL?
        do {
            let support: URL
            if let storageDirectory { support = storageDirectory }
            else {
                support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true).appendingPathComponent(AppStorageLocation.directoryName, isDirectory: true)
            }
            guard support.isFileURL else { throw AutomationFailure("Automation storage requires a local folder.") }
            try Self.rejectSymlink(support)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            file = support.appendingPathComponent("automations.json")
            if let file {
                try Self.rejectSymlink(file)
                if FileManager.default.fileExists(atPath: file.path) {
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    guard values.isRegularFile == true, let size = values.fileSize, size <= Self.maximumFileBytes else {
                        throw AutomationFailure("Automation storage must be a regular file smaller than 1 MiB.")
                    }
                    let data = try Data(contentsOf: file)
                    guard data.count <= Self.maximumFileBytes else { throw AutomationFailure("Automation storage exceeds 1 MiB.") }
                    let decoded = try JSONDecoder().decode(State.self, from: data)
                    guard decoded.version == 1, decoded.schedules.count <= Self.maximumSchedules,
                          Set(decoded.schedules.map(\.id)).count == decoded.schedules.count else {
                        throw AutomationFailure("Automation storage contains an invalid version or duplicate schedules.")
                    }
                    schedules = try decoded.schedules.map { try $0.validated(checkResources: false) }
                }
            }
        } catch { storageError = "Automations are unavailable: \(error.localizedDescription) The existing file was not changed." }
        storageURL = file
    }

    func start(now: Date = Date()) {
        guard timer == nil, storageError == nil else { return }
        var restored = schedules
        for index in restored.indices {
            if restored[index].lastRun?.outcome == .running {
                restored[index].lastRun?.outcome = .interrupted
                restored[index].lastRun?.finishedAt = now
                restored[index].lastRun?.output = "Trellis closed during this attempt. Its process state is unknown. Review before resuming."
                restored[index].enabled = false
                restored[index].nextRun = nil
            }
            if restored[index].enabled && (restored[index].nextRun ?? .distantPast) <= now {
                restored[index].nextRun = restored[index].nextDate(after: now)
            }
        }
        do { if restored != schedules { try commit(restored) } }
        catch { storageError = error.localizedDescription; return }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSchedules() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for task in tasks.values { task.cancel() }
    }

    func stopAndWait() async {
        isStopping = true
        let pending = Array(tasks.values)
        stop()
        for task in pending { await task.value }
    }

    func save(_ schedule: AutomationSchedule, authorized: Bool = false, now: Date = Date()) throws {
        guard !runningIDs.contains(schedule.id) else { throw AutomationFailure("Stop this automation before editing it.") }
        guard !schedule.enabled || authorized else { throw AutomationFailure("Review and allow automatic execution before enabling this command.") }
        var value = try schedule.validated()
        value.nextRun = value.enabled ? value.nextDate(after: now) : nil
        value.lastRun = schedules.first(where: { $0.id == value.id })?.lastRun
        var candidate = schedules
        if let index = candidate.firstIndex(where: { $0.id == value.id }) { candidate[index] = value }
        else { candidate.append(value) }
        guard candidate.count <= Self.maximumSchedules else { throw AutomationFailure("Keep at most 32 automations.") }
        try commit(candidate)
    }

    func setEnabled(_ id: UUID, enabled: Bool, authorized: Bool = false, now: Date = Date()) throws {
        guard var value = schedules.first(where: { $0.id == id }) else { throw AutomationFailure("This automation no longer exists.") }
        guard !enabled || authorized else { throw AutomationFailure("Review and allow automatic execution before resuming.") }
        value.enabled = enabled
        if enabled {
            let validated = try value.validated()
            guard validated.executable == value.executable, validated.directory == value.directory else {
                throw AutomationFailure("The executable or working folder now resolves elsewhere. Edit and review the automation again.")
            }
        }
        value.nextRun = enabled ? value.nextDate(after: now) : nil
        var candidate = schedules
        candidate[candidate.firstIndex(where: { $0.id == id })!] = value
        try commit(candidate)
    }

    func remove(_ id: UUID) throws {
        guard !runningIDs.contains(id) else { throw AutomationFailure("Stop this automation before deleting it.") }
        try commit(schedules.filter { $0.id != id })
    }

    func cancel(_ id: UUID) { tasks[id]?.cancel() }

    func runNow(_ id: UUID, authorized: Bool = false, now: Date = Date()) throws {
        guard authorized else { throw AutomationFailure("Review the command before running it.") }
        try launch(id, now: now)
    }

    func checkSchedules(now: Date = Date()) {
        guard !isStopping, storageError == nil else { return }
        for schedule in schedules where schedule.enabled && (schedule.nextRun ?? .distantFuture) <= now {
            do {
                if runningIDs.contains(schedule.id) || tasks.count >= 4 || now.timeIntervalSince(schedule.nextRun!) >= 60 {
                    var candidate = schedules
                    let index = candidate.firstIndex(where: { $0.id == schedule.id })!
                    candidate[index].nextRun = schedule.nextDate(after: now)
                    if !runningIDs.contains(schedule.id) {
                        candidate[index].lastRun = .init(startedAt: now, finishedAt: now, outcome: .skipped,
                            output: "Missed this run while Trellis was asleep or busy. Missed runs are not replayed.", exitCode: nil)
                    }
                    try commit(candidate)
                } else { try launch(schedule.id, now: now) }
            } catch { storageError = error.localizedDescription; return }
        }
    }

    private func launch(_ id: UUID, now: Date) throws {
        guard !isStopping else { throw AutomationFailure("Trellis is quitting. No new automations can start.") }
        guard storageError == nil else { throw AutomationFailure(storageError ?? "Automation storage is unavailable.") }
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { throw AutomationFailure("This automation no longer exists.") }
        guard !runningIDs.contains(id), tasks.count < 4 else { throw AutomationFailure("An attempt is already running, or four automations are active. Try again after one finishes.") }
        let snapshot = schedules[index]
        var candidate = schedules
        candidate[index].nextRun = snapshot.enabled ? snapshot.nextDate(after: now) : nil
        candidate[index].lastRun = .init(startedAt: now, finishedAt: nil, outcome: .running, output: "", exitCode: nil)
        // Recording the attempt first prevents an app restart from replaying an uncertain command.
        try commit(candidate)
        runningIDs.insert(id)
        tasks[id] = Task { [weak self] in
            guard let self else { return }
            let result: AutomationSchedule.Run
            do {
                let validated = try snapshot.validated()
                guard validated.executable == snapshot.executable, validated.directory == snapshot.directory else {
                    throw AutomationFailure("The executable or working folder now resolves elsewhere. Edit and review the automation again.")
                }
                let tools = try NativeAgentTools(directory: URL(fileURLWithPath: snapshot.directory))
                let request = NativeToolRequest(id: UUID(), callID: id.uuidString, name: "run_command",
                    invocation: .runCommand(executable: snapshot.executable, arguments: snapshot.arguments, directory: snapshot.directory))
                let output = try await tools.execute(tools.prepared(request))
                let text = output.output + (output.truncated ? "\n[Command output was truncated.]" : "")
                result = .init(startedAt: now, finishedAt: Date(), outcome: output.exitCode == 0 ? .succeeded : .failed,
                               output: Self.boundedOutput(text), exitCode: output.exitCode)
            } catch is CancellationError {
                result = .init(startedAt: now, finishedAt: Date(), outcome: .cancelled, output: "Stopped by you or because Trellis closed.", exitCode: nil)
            } catch {
                result = .init(startedAt: now, finishedAt: Date(), outcome: .failed,
                               output: Self.boundedOutput(error.localizedDescription), exitCode: nil)
            }
            var completed = self.schedules
            if let index = completed.firstIndex(where: { $0.id == id }) {
                completed[index].lastRun = result
                do { try self.commit(completed) }
                catch {
                    self.schedules = completed
                    self.storageError = "The last result could not be saved: \(error.localizedDescription) Automatic runs are paused."
                }
            }
            self.tasks[id] = nil
            self.runningIDs.remove(id)
        }
    }

    private func commit(_ candidate: [AutomationSchedule]) throws {
        guard storageError == nil, let storageURL else { throw AutomationFailure(storageError ?? "Automation storage is unavailable.") }
        try Self.rejectSymlink(storageURL.deletingLastPathComponent())
        try Self.rejectSymlink(storageURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(State(version: 1, schedules: candidate))
        guard data.count <= Self.maximumFileBytes else { throw AutomationFailure("Automation storage exceeds 1 MiB.") }
        let temporary = storageURL.deletingLastPathComponent().appendingPathComponent(".automations-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard rename(temporary.path, storageURL.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        schedules = candidate
    }

    private static func rejectSymlink(_ url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
            throw AutomationFailure("Automation storage cannot be a symbolic link.")
        }
    }

    private static func boundedOutput(_ text: String) -> String {
        guard text.utf8.count > maximumOutputBytes else { return text }
        let suffix = "\n[Only the first 8 KiB are retained.]"
        var bytes = Data(text.utf8.prefix(maximumOutputBytes - suffix.utf8.count))
        while String(data: bytes, encoding: .utf8) == nil { bytes.removeLast() }
        return String(decoding: bytes, as: UTF8.self) + suffix
    }
}

private struct AutomationFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
