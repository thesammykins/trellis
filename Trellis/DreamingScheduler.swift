import Combine
import Darwin
import Foundation

struct DreamingSchedule: Codable, Equatable, Sendable {
    let projectPath: String
    var hour: Int
    var minute: Int
    var timeZoneID: String
    var enabled: Bool
}

@MainActor
final class DreamingScheduler: ObservableObject {
    @Published private(set) var schedules: [DreamingSchedule] = []
    @Published private(set) var reports: [String: String] = [:]
    @Published private(set) var running = false

    private struct State: Codable {
        let version: Int
        var schedules: [DreamingSchedule]
        var attemptedDays: [String: String]
    }

    private static let maximumFileBytes = 256 * 1024
    private let manager = FileManager.default
    private var state = State(version: 1, schedules: [], attemptedDays: [:])
    private var storageURL: URL?
    private var persistenceDisabled = false
    private var timer: Timer?
    private var activeTask: Task<Void, Never>?

    init() {
        do {
            let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
                .appendingPathComponent(AppStorageLocation.directoryName, isDirectory: true)
            try manager.createDirectory(at: support, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try Self.rejectSymlink(support)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
            let file = support.appendingPathComponent("dreaming-schedules.json")
            storageURL = file
            if manager.fileExists(atPath: file.path) {
                state = try Self.load(file, manager: manager)
                schedules = state.schedules
            }
        } catch {
            persistenceDisabled = true
            reports["storage"] = "Dreaming schedules are unavailable: \(error.localizedDescription). The existing file was not changed."
        }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkSchedules() }
        }
        Task { await checkSchedules() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancelRun()
    }

    func cancelRun() {
        activeTask?.cancel()
    }

    func configure(project: URL, enabled: Bool, hour: Int, minute: Int, timeZoneID: String) throws {
        guard !persistenceDisabled else { throw ScheduleFailure("Schedule storage is disabled until its error is resolved.") }
        let path = try Self.projectPath(project)
        guard (0...23).contains(hour), (0...59).contains(minute), TimeZone(identifier: timeZoneID) != nil else {
            throw ScheduleFailure("Choose a valid time and IANA time zone.")
        }
        let schedule = DreamingSchedule(projectPath: path, hour: hour, minute: minute,
                                        timeZoneID: timeZoneID, enabled: enabled)
        var candidate = state
        if let index = candidate.schedules.firstIndex(where: { $0.projectPath == path }) { candidate.schedules[index] = schedule }
        else { candidate.schedules.append(schedule) }
        candidate.schedules.sort { $0.projectPath < $1.projectPath }
        try persist(candidate)
        state = candidate
        schedules = state.schedules
    }

    func runNow(project: URL, retry: Bool = false) async {
        guard activeTask == nil else {
            reports[project.path] = "Another Dreaming run is already active."
            return
        }
        await launch(project: project, retry: retry)
    }

    static func isEligible(_ schedule: DreamingSchedule, at date: Date, attemptedLocalDay: String?) -> Bool {
        guard schedule.enabled, (0...23).contains(schedule.hour), (0...59).contains(schedule.minute),
              let zone = TimeZone(identifier: schedule.timeZoneID) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let year = components.year, let month = components.month, let day = components.day,
              let hour = components.hour, let minute = components.minute else { return false }
        let localDay = String(format: "%04d-%02d-%02d", year, month, day)
        let elapsedMinutes = hour * 60 + minute - (schedule.hour * 60 + schedule.minute)
        return attemptedLocalDay != localDay && (0..<5).contains(elapsedMinutes)
    }

    static func localDay(for date: Date, timeZoneID: String) -> String? {
        guard let zone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = values.year, let month = values.month, let day = values.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func checkSchedules(now: Date = Date()) async {
        guard activeTask == nil else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            reports["scheduler"] = "Dreaming skipped while Low Power Mode is enabled."
            return
        }
        for schedule in state.schedules where Self.isEligible(
            schedule, at: now, attemptedLocalDay: state.attemptedDays[schedule.projectPath]
        ) {
            guard let day = Self.localDay(for: now, timeZoneID: schedule.timeZoneID) else { continue }
            var candidate = state
            candidate.attemptedDays[schedule.projectPath] = day
            do { try persist(candidate) }
            catch {
                reports[schedule.projectPath] = "Dreaming was not started because its attempt could not be recorded: \(error.localizedDescription)"
                return
            }
            state = candidate
            await launch(project: URL(fileURLWithPath: schedule.projectPath, isDirectory: true), retry: false)
            return
        }
    }

    private func launch(project: URL, retry: Bool) async {
        guard activeTask == nil else { return }
        running = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.execute(project: project, retry: retry)
        }
        activeTask = task
        await task.value
        activeTask = nil
        running = false
    }

    private func execute(project: URL, retry: Bool) async {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            reports[project.path] = "Dreaming skipped while Low Power Mode is enabled."
            return
        }
        guard UserDefaults.standard.string(forKey: "modelRoute") == "direct" else {
            reports[project.path] = "Unattended Dreaming is unavailable for the selected model route. Choose Direct API."
            return
        }
        do {
            let location = try MemoryIntegration(project: project)
            let store = try MemoryStore(root: location.root, projectID: location.projectID)
            let baseURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "https://api.openai.com/v1"
            let model = UserDefaults.standard.string(forKey: "apiModel") ?? ""
            guard let api = DirectAPI(rawValue: UserDefaults.standard.string(forKey: "apiKind") ?? "responses") else {
                throw ScheduleFailure("The selected direct API kind is invalid.")
            }
            let key = try EndpointKey.read(endpoint: baseURL)
            let parent = location.root.appendingPathComponent("Dreaming", isDirectory: true)
            try Self.rejectSymlink(parent)
            try manager.createDirectory(at: parent, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try Self.rejectSymlink(parent)
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            let run = try DreamingRun(directory: parent.appendingPathComponent(location.projectID, isDirectory: true))
            reports[project.path] = try await run.run(
                store: store,
                configuration: .init(baseURL: baseURL, model: model, api: api, maxOutputTokens: 2048),
                apiKey: key,
                retry: retry
            )
        } catch is CancellationError {
            reports[project.path] = "Dreaming was cancelled."
        } catch {
            reports[project.path] = "Dreaming failed: \(error.localizedDescription)"
        }
    }

    private func persist(_ candidate: State) throws {
        guard !persistenceDisabled, let storageURL else { throw ScheduleFailure("Schedule storage is unavailable.") }
        try Self.rejectSymlink(storageURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(candidate)
        guard data.count <= Self.maximumFileBytes else { throw ScheduleFailure("Schedule storage exceeds 256 KiB.") }
        let temporary = storageURL.deletingLastPathComponent().appendingPathComponent(".dreaming-schedules.\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if rename(temporary.path, storageURL.path) != 0 {
            let code = errno
            try? manager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    private static func load(_ file: URL, manager: FileManager) throws -> State {
        try rejectSymlink(file)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey])
        let size = try manager.attributesOfItem(atPath: file.path)[.size] as? NSNumber
        guard values.isRegularFile == true, let size, size.intValue <= maximumFileBytes else {
            throw ScheduleFailure("Schedule storage must be a bounded regular file.")
        }
        let data = try Data(contentsOf: file)
        guard data.count <= maximumFileBytes else { throw ScheduleFailure("Schedule storage exceeds 256 KiB.") }
        let decoded = try JSONDecoder().decode(State.self, from: data)
        guard decoded.version == 1, decoded.schedules.count <= 1_000,
              Set(decoded.schedules.map(\.projectPath)).count == decoded.schedules.count,
              decoded.attemptedDays.count <= 1_000 else { throw ScheduleFailure("Schedule storage is invalid.") }
        for schedule in decoded.schedules {
            guard (0...23).contains(schedule.hour), (0...59).contains(schedule.minute),
                  TimeZone(identifier: schedule.timeZoneID) != nil,
                  schedule.projectPath.utf8.count <= 4096,
                  !schedule.projectPath.utf8.contains(0), schedule.projectPath != "/",
                  URL(fileURLWithPath: schedule.projectPath).path == schedule.projectPath
            else { throw ScheduleFailure("Schedule storage contains invalid values.") }
        }
        guard decoded.attemptedDays.allSatisfy({ path, day in
            path.utf8.count <= 4096 && !path.utf8.contains(0) && path.hasPrefix("/") && Self.validDay(day)
        }) else { throw ScheduleFailure("Schedule storage contains invalid attempt records.") }
        return decoded
    }

    private static func projectPath(_ project: URL) throws -> String {
        guard project.isFileURL else { throw ScheduleFailure("Dreaming projects must use local file URLs.") }
        let path = project.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix("/"), path != "/", path.utf8.count <= 4096 else {
            throw ScheduleFailure("Dreaming requires a bounded absolute project path.")
        }
        return path
    }

    private static func rejectSymlink(_ file: URL) throws {
        var information = stat()
        if lstat(file.path, &information) == 0, (information.st_mode & S_IFMT) == S_IFLNK {
            throw ScheduleFailure("Dreaming schedule storage cannot be a symlink.")
        }
    }

    private static func validDay(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return false }
        return Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) != nil
    }
}

private struct ScheduleFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
