import SwiftUI

struct RemoteSessionView: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var hostAlias = ""
    @State private var directory = ""
    @State private var nickname = ""
    @State private var sessionName = "trellis-\(UUID().uuidString)"
    @State private var tmuxExecutable = "tmux"
    @State private var create = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remote Session").font(.title2)
            Form {
                TextField("SSH host or user@host", text: $hostAlias)
                TextField("Absolute remote directory", text: $directory)
                TextField("Session name (optional)", text: $nickname)
                TextField("Remote tmux executable", text: $tmuxExecutable)
                    Text("Use tmux from the remote login PATH, or an absolute path such as /opt/homebrew/bin/tmux.")
                        .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)

            Text(create
                 ? "Creates a persistent tmux session on the remote host. Closing this local terminal disconnects it; the remote session keeps running."
                 : "Attaches only to the recorded tmux session. If it is missing, Trellis does not create a replacement session.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Uses your existing OpenSSH host or user@host with strict host-key checking. Trellis does not override host-key verification or forward your SSH agent.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(create ? "Start Remote Session" : "Attach Remote Session", action: start)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func start() {
        do {
            let profile = try RemoteProfile(hostAlias: hostAlias, directory: directory, sessionName: sessionName,
                                            tmuxExecutable: tmuxExecutable)
            if workspace.startRemote(profile, create: create, nickname: nickname.isEmpty ? nil : nickname) { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
