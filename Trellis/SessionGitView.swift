import SwiftUI

struct SessionGitView: View {
    @Environment(\.trellisSecondary) private var secondaryColor
    let directory: URL
    @ObservedObject var state: TerminalState
    var details: [WorkspaceAppearance.TabDetail] = [.branch, .diff]
    var host: String? = nil
    var harness = ""
    var model = ""
    @State private var snapshot: GitSnapshot?
    @State private var failure: String?
    private var path: String { state.workingDirectory ?? directory.path }

    var body: some View {
        Text(details.compactMap(detailText).joined(separator: " · "))
            .font(.caption).foregroundStyle(secondaryColor).lineLimit(1)
            .help(details.compactMap(detailText).joined(separator: " · "))
        .task(id: path + details.map(\.rawValue).joined() + (host ?? "")) {
            snapshot = nil; failure = nil
            guard host == nil, TerminalLocation.validatedPath(path) != nil, details.contains(.branch) || details.contains(.diff) else { return }
            while !Task.isCancelled {
                do { snapshot = try await GitSnapshot.load(directory: URL(fileURLWithPath: path)); failure = nil }
                catch is CancellationError { return }
                catch { snapshot = nil; failure = error.localizedDescription }
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    private func detailText(_ detail: WorkspaceAppearance.TabDetail) -> String? {
        switch detail {
        case .folder: return URL(fileURLWithPath: path).lastPathComponent
        case .branch: return snapshot?.branch ?? (failure == nil ? nil : "Git unavailable")
        case .diff: return snapshot.map { "+\($0.added) −\($0.removed)" + ($0.untrackedFiles > 0 ? " ?\($0.untrackedFiles)" : "") }
        case .host: return host ?? "Local"
        case .harness: return harness.isEmpty ? nil : harness
        case .configuredModel: return model.isEmpty ? nil : "Configured: " + model
        }
    }

}
