import SwiftUI

struct ModelConnectionsView: View {
    @ObservedObject private var store = ModelConnectionStore.shared
    @State private var editing: ModelConnection?
    @State private var removing: ModelConnection?
    @State private var error: String?
    let onUse: (ModelConnection) -> Void

    var body: some View {
        Section("Saved API Connections") {
            if let error = error ?? store.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            ForEach(store.connections) { connection in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(connection.name).fontWeight(.medium)
                        Text(connection.endpoint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text(connection.model.isEmpty ? "Choose a model after connecting" : connection.model)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Use") { onUse(connection) }.help("Use this connection for new Trellis Agent conversations")
                    Menu {
                        Button("Edit…") { editing = connection }
                        Button("Remove Connection…", role: .destructive) { removing = connection }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton)
                        .accessibilityLabel("Manage \(connection.name)").frame(width: 24)
                }
            }
            Menu("Add API Connection", systemImage: "plus") {
                ForEach(ModelProviderPreset.allCases) { provider in
                    Button(provider.name) { editing = .init(name: provider.name, endpoint: provider.endpoint, api: provider.api) }
                }
            }.disabled(store.error != nil)
            Text("API connections use provider keys. Consumer subscriptions use their supported agent sign-in. Saved connections share the Keychain key for an identical endpoint.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $editing) { connection in
            ModelConnectionEditor(connection: connection) { value in try store.save(value) }
        }
        .confirmationDialog("Remove \(removing?.name ?? "connection")?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("Remove Connection", role: .destructive) {
                    guard let removing else { return }
                    do { try store.remove(removing.id); self.removing = nil }
                    catch { self.error = error.localizedDescription }
                }
            } message: { Text("This removes the saved setup. Its Keychain key and active conversations are retained.") }
    }
}

private struct ModelConnectionEditor: View {
    @State var connection: ModelConnection
    let save: (ModelConnection) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var credentialRevision = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("API Connection").font(.title2.bold()).padding()
            Form {
                Section("Provider") {
                    TextField("Name", text: $connection.name)
                    TextField("API base URL", text: $connection.endpoint)
                    Picker("API", selection: $connection.api) {
                        Text("Responses").tag(DirectAPI.responses)
                        Text("Chat Completions").tag(DirectAPI.chatCompletions)
                    }
                    EndpointKeyControls(endpoint: connection.endpoint) { credentialRevision = UUID() }
                }
                Section("Model") {
                    DirectModelCatalogPicker(baseURL: connection.endpoint,
                        apiKey: { try EndpointKey.read(endpoint: connection.endpoint) }, modelID: $connection.model,
                        credentialRevision: credentialRevision)
                    DisclosureGroup("Custom model ID") { TextField("Exact model identifier", text: $connection.model) }
                    Picker("Reasoning", selection: $connection.reasoning) {
                        Text("Provider default").tag("")
                        ForEach(DirectModelClient.supportedReasoningEfforts(baseURL: connection.endpoint), id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red).padding(.horizontal).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do { try save(connection); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }.padding()
        }.frame(width: 640, height: 580)
    }
}
