import Foundation

/// Owns cleanup after a window leaves the open-window collection, until quit can await it.
@MainActor
final class ClosingWorkspaceCleanup {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    var pendingCount: Int { tasks.count }

    func start(workspaceID: UUID, operation: @escaping @MainActor () async -> Void) {
        guard tasks[workspaceID] == nil else { return }
        tasks[workspaceID] = Task {
            await operation()
            tasks.removeValue(forKey: workspaceID)
        }
    }

    func waitForAll() async {
        // Another window can close while an earlier cancellation is awaiting its process.
        while !tasks.isEmpty {
            let pending = Array(tasks.values)
            for task in pending { await task.value }
        }
    }
}
