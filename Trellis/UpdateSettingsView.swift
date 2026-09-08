import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater

    var body: some View {
        Section("Software Updates") {
            LabeledContent("Installed Version", value: installedVersion)
            Text(updater.statusMessage).foregroundStyle(updater.isConfigured ? .secondary : .primary)
                .textSelection(.enabled)
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: updater.setAutomaticallyChecksForUpdates))
                .disabled(!updater.isConfigured)
            if let date = updater.lastUpdateCheckDate {
                let value = date.formatted(date: .abbreviated, time: .shortened)
                LabeledContent("Last Checked", value: value)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Last Checked").accessibilityValue(value).id(value)
            }
            Button("Check for Updates…", action: updater.checkForUpdates)
                .disabled(!updater.canCheckForUpdates)
        }
        Section {
            Text("Installing an update restarts Trellis. Local processes and Trellis tasks stop; persistent tmux workloads keep running. Scheduled automations run only while Trellis is open.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var installedVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!updater.canCheckForUpdates)
    }
}
