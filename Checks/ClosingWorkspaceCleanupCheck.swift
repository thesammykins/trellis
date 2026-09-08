import Foundation

@main
struct ClosingWorkspaceCleanupCheck {
    @MainActor static func main() async {
        let cleanup = ClosingWorkspaceCleanup()
        let first = Gate(), second = Gate()
        let firstID = UUID(), secondID = UUID()
        var stopped: [UUID] = []
        var openWindows = Set([firstID])
        var quitReplied = false

        cleanup.start(workspaceID: firstID) {
            await first.wait()
            stopped.append(firstID)
        }
        cleanup.start(workspaceID: firstID) { preconditionFailure("Duplicate window cleanup ran") }
        openWindows.remove(firstID)
        let quit = Task { @MainActor in
            await cleanup.waitForAll()
            quitReplied = true
        }
        await waitUntil { first.entered }
        precondition(openWindows.isEmpty && cleanup.pendingCount == 1)
        precondition(!quitReplied && stopped.isEmpty, "Quit or shutdown outran chat cleanup")

        // A further close during termination must join the same drain.
        cleanup.start(workspaceID: secondID) {
            await second.wait()
            stopped.append(secondID)
        }
        await waitUntil { second.entered }
        first.resume()
        await waitUntil { stopped.contains(firstID) }
        precondition(!quitReplied && cleanup.pendingCount == 1)
        second.resume()
        await quit.value
        precondition(quitReplied && Set(stopped) == Set([firstID, secondID]))
        precondition(cleanup.pendingCount == 0)
        await cleanup.waitForAll()
        print("PASS closing-window cleanup: retained after removal, duplicate suppression, late close drain, shutdown ordering and completed ownership release")
    }

    @MainActor private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("Cleanup fixture did not reach its suspension point")
    }

    @MainActor private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        var entered: Bool { continuation != nil }
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func resume() { continuation?.resume(); continuation = nil }
    }
}
