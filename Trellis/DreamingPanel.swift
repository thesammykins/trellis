import SwiftUI

struct DreamingPanel: View {
    let project: URL
    @ObservedObject var scheduler: DreamingScheduler
    @AppStorage("modelRoute") private var route = "codex"
    @AppStorage("apiModel") private var model = ""
    @AppStorage("apiBaseURL") private var endpoint = "https://api.openai.com/v1"
    @State private var enabled = false
    @State private var time = Calendar.current.date(from: DateComponents(hour: 2, minute: 0)) ?? Date()
    @State private var error: String?
    @State private var confirmsRetry = false
    private var projectPath: String { project.resolvingSymlinksInPath().standardizedFileURL.path }

    var body: some View {
        Form {
            Section("Proposals only") {
                Text("Review approved project notes and suggest up to three new notes. Every suggestion needs your approval.")
                Text("Direct API · \(model.isEmpty ? "No model selected" : model)").font(.caption)
                Text(endpoint).font(.caption).textSelection(.enabled)
                Text("One request, up to 64 KiB of approved notes and 2,048 output tokens. Provider charges may apply; monetary cost is unknown. No tools or research.").font(.caption).foregroundStyle(.secondary)
            }
            Section("While Trellis is open") {
                Toggle("Enable daily review", isOn: $enabled).disabled(route != "direct")
                DatePicker("Local time", selection: $time, displayedComponents: .hourAndMinute)
                Text(TimeZone.current.identifier).font(.caption)
                Text("Runs within five minutes of this time while the Mac is awake. Missed runs are skipped. Low Power Mode pauses reviews.").font(.caption).foregroundStyle(.secondary)
                Button("Save Schedule") {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                    do {
                        try scheduler.configure(project: project, enabled: enabled, hour: parts.hour ?? 2,
                                                minute: parts.minute ?? 0, timeZoneID: TimeZone.current.identifier)
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
            }
            Section("Review now") {
                if route != "direct" { Text(CodexModelClient.restrictionReason).font(.caption) }
                Button(scheduler.running ? "Reviewing…" : "Review Approved Notes") {
                    Task { await scheduler.runNow(project: project) }
                }.disabled(route != "direct" || model.isEmpty || scheduler.running)
                Button("Retry Failed Review…") { confirmsRetry = true }
                    .disabled(route != "direct" || model.isEmpty || scheduler.running)
                if scheduler.running { Button("Cancel Review") { scheduler.cancelRun() } }
                if let report = scheduler.reports[projectPath] ?? scheduler.reports[project.path] { Text(report).textSelection(.enabled) }
                if let report = scheduler.reports["storage"] { Text(report).foregroundStyle(.orange) }
                if let error { Text(error).foregroundStyle(.orange) }
            }
        }.formStyle(.grouped)
        .confirmationDialog("Retry the failed or interrupted snapshot?", isPresented: $confirmsRetry) {
            Button("Retry Review") { Task { await scheduler.runNow(project: project, retry: true) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The previous provider call may have completed and incurred a charge. A retry can create additional pending proposals. Successful snapshots are not repeated.")
        }
        .onAppear {
            if let schedule = scheduler.schedules.first(where: { $0.projectPath == projectPath }) {
                enabled = schedule.enabled
                var calendar = Calendar.current
                calendar.timeZone = TimeZone(identifier: schedule.timeZoneID) ?? .current
                time = calendar.date(from: DateComponents(hour: schedule.hour, minute: schedule.minute)) ?? time
            }
        }
    }
}
