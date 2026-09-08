import Foundation

@main
enum AutomationScheduleCheck {
    @MainActor
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("trellis-automation-check-\(UUID().uuidString)").resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let now = Date()
        let scheduler = AutomationScheduler(storageDirectory: root.appendingPathComponent("state"))
        defer { scheduler.stop() }
        precondition(scheduler.schedules.isEmpty && scheduler.storageError == nil)
        var command = AutomationSchedule()
        command.name = "Exact arguments"
        command.executable = "/usr/bin/printf"
        command.arguments = ["%s", "spaces ' quotes $(not-a-command)\n"]
        command.directory = root.path
        command.intervalMinutes = 1
        precondition(!command.enabled)
        try scheduler.save(command, now: now)
        try expectFailure { try scheduler.runNow(command.id) }
        try expectFailure { try scheduler.setEnabled(command.id, enabled: true) }
        command.enabled = true
        try expectFailure { try scheduler.save(command) }
        try scheduler.save(command, authorized: true, now: now)
        precondition(scheduler.schedules[0].nextRun == now.addingTimeInterval(60))

        try scheduler.runNow(command.id, authorized: true, now: now)
        precondition(scheduler.runningIDs.contains(command.id))
        // The durable attempt must exist before the child has a chance to finish.
        let pending = AutomationScheduler(storageDirectory: root.appendingPathComponent("state"))
        precondition(pending.schedules[0].lastRun?.outcome == .running)
        let interruptedDirectory = root.appendingPathComponent("interrupted")
        try manager.createDirectory(at: interruptedDirectory, withIntermediateDirectories: true)
        try manager.copyItem(at: root.appendingPathComponent("state/automations.json"),
                             to: interruptedDirectory.appendingPathComponent("automations.json"))
        let interrupted = AutomationScheduler(storageDirectory: interruptedDirectory)
        interrupted.start(now: now)
        defer { interrupted.stop() }
        precondition(interrupted.schedules[0].lastRun?.outcome == .interrupted)
        precondition(!interrupted.schedules[0].enabled && interrupted.schedules[0].nextRun == nil)
        precondition(interrupted.runningIDs.isEmpty)
        try expectFailure { try scheduler.runNow(command.id, authorized: true) }
        try expectFailure { try scheduler.save(command, authorized: true) }
        try expectFailure { try scheduler.remove(command.id) }
        try await settled(scheduler)
        precondition(scheduler.schedules[0].lastRun?.outcome == .succeeded)
        precondition(scheduler.schedules[0].lastRun?.output == command.arguments[1])
        let completed = scheduler.schedules[0].lastRun
        scheduler.checkSchedules(now: now.addingTimeInterval(1))
        precondition(scheduler.runningIDs.isEmpty && scheduler.schedules[0].lastRun == completed)

        // A missed due time advances once, without launching catch-up work.
        scheduler.checkSchedules(now: now.addingTimeInterval(600))
        precondition(scheduler.runningIDs.isEmpty)
        precondition(scheduler.schedules[0].lastRun?.outcome == .skipped)
        precondition(scheduler.schedules[0].nextRun == now.addingTimeInterval(660))
        scheduler.checkSchedules(now: now.addingTimeInterval(660))
        try await settled(scheduler)
        precondition(scheduler.schedules[0].lastRun?.outcome == .succeeded)
        let lastScheduled = scheduler.schedules[0].lastRun
        scheduler.checkSchedules(now: now.addingTimeInterval(661))
        precondition(scheduler.runningIDs.isEmpty && scheduler.schedules[0].lastRun == lastScheduled)

        let relaunched = AutomationScheduler(storageDirectory: root.appendingPathComponent("state"))
        defer { relaunched.stop() }
        relaunched.start(now: now.addingTimeInterval(3_600))
        precondition(relaunched.runningIDs.isEmpty)
        precondition(relaunched.schedules[0].nextRun == now.addingTimeInterval(3_660))

        var slow = command
        slow.id = UUID()
        slow.name = "Cancellation"
        slow.enabled = false
        slow.executable = "/bin/sleep"
        slow.arguments = ["20"]
        try scheduler.save(slow)
        try scheduler.runNow(slow.id, authorized: true)
        try await Task.sleep(for: .milliseconds(100))
        scheduler.cancel(slow.id)
        try await settled(scheduler)
        precondition(scheduler.schedules.first(where: { $0.id == slow.id })?.lastRun?.outcome == .cancelled)

        var long = command
        long.id = UUID()
        long.name = "Bounded output"
        long.enabled = false
        long.arguments = ["%10000s", "a"]
        try scheduler.save(long)
        try scheduler.runNow(long.id, authorized: true)
        try await settled(scheduler)
        let output = scheduler.schedules.first(where: { $0.id == long.id })!.lastRun!.output
        precondition(output.utf8.count <= AutomationScheduler.maximumOutputBytes)
        precondition(output.hasSuffix("[Only the first 8 KiB are retained.]"))

        var daily = command
        daily.cadence = .daily
        daily.timeZoneID = "Australia/Melbourne"
        daily.hour = 2
        daily.minute = 1
        let firstDSTOccurrence = Date(timeIntervalSince1970: 1_775_314_860) // 2026-04-05 02:01 AEDT
        let secondDSTOccurrence = firstDSTOccurrence.addingTimeInterval(3_600)
        precondition(daily.nextDate(after: firstDSTOccurrence)! > secondDSTOccurrence)
        daily.timeZoneID = "Invalid/Zone"
        try expectFailure { _ = try daily.validated() }
        var invalid = command
        invalid.arguments = ["bad\0argument"]
        try expectFailure { try scheduler.save(invalid) }
        invalid = command
        invalid.intervalMinutes = 0
        try expectFailure { _ = try invalid.validated() }

        // Persist failures must prevent the command from starting and preserve the target file.
        let unsafeDirectory = root.appendingPathComponent("unsafe")
        let unsafe = AutomationScheduler(storageDirectory: unsafeDirectory)
        try unsafe.save(command, authorized: true)
        let stateFile = unsafeDirectory.appendingPathComponent("automations.json")
        let untouched = root.appendingPathComponent("untouched.json")
        try Data("untouched".utf8).write(to: untouched)
        try manager.removeItem(at: stateFile)
        try manager.createSymbolicLink(at: stateFile, withDestinationURL: untouched)
        try expectFailure { try unsafe.runNow(command.id, authorized: true) }
        precondition(unsafe.runningIDs.isEmpty)
        let preservedText = try String(contentsOf: untouched, encoding: .utf8)
        precondition(preservedText == "untouched")
        let rejected = AutomationScheduler(storageDirectory: unsafeDirectory)
        precondition(rejected.storageError != nil && rejected.schedules.isEmpty)

        let malformedDirectory = root.appendingPathComponent("malformed")
        try manager.createDirectory(at: malformedDirectory, withIntermediateDirectories: true)
        let badFile = malformedDirectory.appendingPathComponent("automations.json")
        let badData = Data("{\"version\":99,\"schedules\":[]}".utf8)
        try badData.write(to: badFile)
        let malformed = AutomationScheduler(storageDirectory: malformedDirectory)
        precondition(malformed.storageError != nil && malformed.schedules.isEmpty)
        let preservedData = try Data(contentsOf: badFile)
        precondition(preservedData == badData)

        // A saved path replaced by a symlink requires fresh review before resuming or running.
        let originalFolder = root.appendingPathComponent("original")
        let differentFolder = root.appendingPathComponent("different")
        try manager.createDirectory(at: originalFolder, withIntermediateDirectories: true)
        try manager.createDirectory(at: differentFolder, withIntermediateDirectories: true)
        var moved = command
        moved.id = UUID()
        moved.enabled = false
        moved.directory = originalFolder.path
        try scheduler.save(moved)
        try manager.removeItem(at: originalFolder)
        try manager.createSymbolicLink(at: originalFolder, withDestinationURL: differentFolder)
        try expectFailure { try scheduler.setEnabled(moved.id, enabled: true, authorized: true) }
        try scheduler.runNow(moved.id, authorized: true)
        try await settled(scheduler)
        precondition(scheduler.schedules.first(where: { $0.id == moved.id })?.lastRun?.outcome == .failed)
        try scheduler.runNow(slow.id, authorized: true)
        try await Task.sleep(for: .milliseconds(100))
        await scheduler.stopAndWait()
        precondition(scheduler.runningIDs.isEmpty)
        precondition(scheduler.schedules.first(where: { $0.id == slow.id })?.lastRun?.outcome == .cancelled)
        let stopped = AutomationScheduler(storageDirectory: root.appendingPathComponent("state"))
        precondition(stopped.schedules.first(where: { $0.id == slow.id })?.lastRun?.outcome == .cancelled)
        try expectFailure { try scheduler.runNow(command.id, authorized: true) }
        scheduler.checkSchedules(now: now.addingTimeInterval(7_200))
        precondition(scheduler.runningIDs.isEmpty)
        print("PASS automations: exact argv, opt-in execution, durable attempts, duplicate prevention, missed runs/restart/DST, cancellation and quit cleanup, output bounds, invalid storage and moved-path review")
    }

    @MainActor
    private static func settled(_ scheduler: AutomationScheduler) async throws {
        for _ in 0..<500 {
            if scheduler.runningIDs.isEmpty { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Automation did not finish within five seconds")
    }

    private static func expectFailure(_ action: () throws -> Void) throws {
        var rejected = false
        do { try action() } catch { rejected = true }
        precondition(rejected, "Expected this unsafe action to be rejected")
    }
}
