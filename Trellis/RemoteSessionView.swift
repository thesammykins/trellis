import SwiftUI

struct RemoteSessionView: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var hostAlias = ""
    @State private var directory = ""
    @State private var nickname = ""
    @State private var sessionName = "trellis-\(UUID().uuidString)"
    @State private var tmuxExecutable = "tmux"
    @State private var mode = RemoteProfile.Mode.shell
    @State private var editingLocation: RemoteLocation?
    @State private var error: String?

    init(workspace: Workspace, location: RemoteLocation? = nil, initialMode: RemoteProfile.Mode = .shell) {
        self.workspace = workspace
        _hostAlias = State(initialValue: location?.hostAlias ?? "")
        _directory = State(initialValue: location?.directory ?? "")
        _nickname = State(initialValue: location?.name ?? "")
        _tmuxExecutable = State(initialValue: location?.tmuxExecutable ?? "tmux")
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SSH Connection").font(.title2)
            Picker("Session type", selection: $mode) {
                Text("SSH shell").tag(RemoteProfile.Mode.shell)
                Text("Persistent tmux").tag(RemoteProfile.Mode.tmux)
            }.pickerStyle(.segmented)
            Form {
                TextField("SSH host or user@host", text: $hostAlias)
                TextField(mode == .shell ? "Remote directory (optional)" : "Absolute remote directory", text: $directory)
                TextField("Session name (optional)", text: $nickname)
                if mode == .tmux {
                    TextField("Remote tmux executable", text: $tmuxExecutable)
                    Text("Use tmux from the remote login PATH, or an absolute path such as /opt/homebrew/bin/tmux.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Text(mode == .tmux
                 ? "Creates a persistent tmux session on the remote host. Closing this local terminal disconnects it; the remote session keeps running."
                 : "Opens an ordinary SSH login without tmux. Its shell ends when this connection closes; reconnecting starts a new shell. Leave the folder blank to use the server’s default.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Uses your existing OpenSSH host or user@host with strict host-key checking. Trellis does not override host-key verification or forward your SSH agent.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save Location…") {
                    editingLocation = RemoteLocation(name: nickname.isEmpty ? hostAlias : nickname,
                        hostAlias: hostAlias, directory: directory, tmuxExecutable: tmuxExecutable)
                }
                Spacer()
                Button(mode == .tmux ? "Create tmux Session" : "Connect SSH", action: start)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .sheet(item: $editingLocation) { location in RemoteLocationEditor(location: location, store: .shared) }
    }

    private func start() {
        do {
            let profile = try mode == .shell ? RemoteProfile(hostAlias: hostAlias, directory: directory)
                : RemoteProfile(hostAlias: hostAlias, directory: directory, sessionName: sessionName, tmuxExecutable: tmuxExecutable)
            if workspace.startRemote(profile, create: mode == .tmux, nickname: nickname.isEmpty ? nil : nickname) { dismiss() }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RemoteLocationEditor: View {
    @State var location: RemoteLocation
    @ObservedObject var store: RemoteLocationStore
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SSH Favorite").font(.title2)
            Form {
                TextField("Name", text: $location.name)
                TextField("SSH host or user@host", text: $location.hostAlias)
                TextField("Remote directory (optional)", text: $location.directory)
                DisclosureGroup("Persistent session options") {
                    TextField("Remote tmux executable", text: $location.tmuxExecutable)
                    Text("Creating a tmux session requires an absolute remote folder. Ordinary SSH can use the server’s default folder.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            Text("Saving records this location only. It does not connect, inspect the host or store credentials.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Favorite") {
                    do { try store.save(location); dismiss() } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520)
    }
}
