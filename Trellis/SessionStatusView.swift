import SwiftUI

@MainActor
struct SessionStatusView: View {
    let id: UUID
    let profileTitle: String
    let isRunning: Bool
    @ObservedObject var state: TerminalState
    var nickname: String? = nil
    var compact = false
    var showsProfile = true

    var body: some View {
        HStack(spacing: 4) {
            if !compact { Text(title).lineLimit(1) }
            if showsProfile && !compact && title != profileTitle { Text(profileTitle).font(.caption).foregroundStyle(.secondary) }
            Label(status, systemImage: statusSymbol)
                .font(.caption)
                .labelStyle(.iconOnly)
                .help(status)
        }
        .help(title + " · " + profileTitle + " · " + status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(profileTitle), \(status)")
    }

    private var title: String {
        nickname ?? (state.title.isEmpty ? profileTitle : state.title)
    }

    private var status: String {
        if let exitCode = state.exitCode { return "Exited \(exitCode)" }
        return isRunning ? "Running" : "Stopped"
    }

    private var statusSymbol: String {
        if state.exitCode != nil { return "exclamationmark.circle" }
        return isRunning ? "circle.fill" : "stop.circle"
    }
}
