import AppKit
import SwiftUI

struct AutomationsView: View {
    @ObservedObject var scheduler: AutomationScheduler
    @State private var editing: AutomationSchedule?
    @State private var confirmation: Confirmation?
    @State private var error: String?

    private struct Confirmation: Identifiable {
        enum Action { case resume, run, delete }
        let schedule: AutomationSchedule
        let action: Action
        var id: UUID { schedule.id }
        var title: String {
            switch action {
            case .resume: "Resume Automatic Execution"
            case .run: "Run Command Now"
            case .delete: "Delete Automation"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top) {
                    Text("Runs while Trellis is open and your Mac is awake. Missed runs are skipped.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("New Automation", systemImage: "plus") { editing = AutomationSchedule() }
                        .disabled(scheduler.storageError != nil)
                }
                Text("Commands run in the background with Trellis’s environment and your user permissions. Each attempt has a 30-second limit. Output stays on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let storageError = scheduler.storageError {
                Section { Label(storageError, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            if scheduler.schedules.isEmpty && scheduler.storageError == nil {
                Section {
                    ContentUnavailableView("No Automations", systemImage: "clock.arrow.circlepath",
                        description: Text("Schedule an exact command in a chosen folder, then review and enable it."))
                }
            }
            ForEach(scheduler.schedules) { schedule in
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(schedule.name).font(.headline)
                            Text(schedule.frequency).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if scheduler.runningIDs.contains(schedule.id) {
                            ProgressView().controlSize(.small).accessibilityLabel("Running \(schedule.name)")
                            Button("Stop") { scheduler.cancel(schedule.id) }
                        } else {
                            Text(schedule.enabled ? "Enabled" : "Paused").foregroundStyle(.secondary)
                            Button("Run Now") { confirmation = .init(schedule: schedule, action: .run) }
                                .disabled(scheduler.storageError != nil)
                        }
                        Menu {
                            Button("Edit…") { editing = schedule }
                                .disabled(scheduler.runningIDs.contains(schedule.id))
                            if schedule.enabled {
                                Button("Pause Future Runs") { perform { try scheduler.setEnabled(schedule.id, enabled: false) } }
                            } else {
                                Button("Resume…") { confirmation = .init(schedule: schedule, action: .resume) }
                            }
                            Divider()
                            Button("Delete…", role: .destructive) { confirmation = .init(schedule: schedule, action: .delete) }
                                .disabled(scheduler.runningIDs.contains(schedule.id))
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("Actions for \(schedule.name)")
                        .disabled(scheduler.storageError != nil)
                    }
                    if schedule.enabled, let next = schedule.nextRun {
                        let date = next.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                        LabeledContent("Next Run") { Text(date) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Next Run")
                            .accessibilityValue(date)
                            .id(date)
                    }
                    if let run = schedule.lastRun {
                        let date = run.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                        let status = run.outcome.rawValue.capitalized + (run.exitCode.map { " · Exit \($0)" } ?? "")
                        LabeledContent("Last Attempt") {
                            Text(status)
                            Text(date).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Last Attempt")
                        .accessibilityValue("\(status), \(date)")
                        .id("\(status), \(date)")
                    }
                    DisclosureGroup("Command and Output") {
                        Text(schedule.commandReview).font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        if let run = schedule.lastRun, !run.output.isEmpty {
                            Divider()
                            ScrollView {
                                Text(run.output).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxHeight: 180)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { schedule in
            AutomationEditor(schedule: schedule) { value, authorized in
                try scheduler.save(value, authorized: authorized)
            }
        }
        .sheet(item: $confirmation) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text(item.title).font(.title2.bold())
                Text(item.schedule.name).font(.headline)
                ScrollView {
                    Text(item.schedule.commandReview).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 220)
                if item.action == .resume {
                    Text(item.schedule.frequency)
                    Text("Allow this exact command to run automatically while Trellis is open. It has your user permissions and can change files or access the network.")
                        .foregroundStyle(.secondary)
                } else if item.action == .run {
                    Text("Runs once in the background with your user permissions. This does not enable the schedule.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("The schedule and its retained output will be removed.").foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { confirmation = nil }.keyboardShortcut(.cancelAction)
                    Button(item.action == .resume ? "Allow and Resume" : item.action == .run ? "Run Command" : "Delete",
                           role: item.action == .delete ? .destructive : nil) {
                        perform {
                            switch item.action {
                            case .resume: try scheduler.setEnabled(item.schedule.id, enabled: true, authorized: true)
                            case .run: try scheduler.runNow(item.schedule.id, authorized: true)
                            case .delete: try scheduler.remove(item.schedule.id)
                            }
                        }
                        confirmation = nil
                    }
                }
            }.padding(24).frame(width: 560)
        }
        .alert("Automation Could Not Be Updated", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
}

private struct AutomationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var schedule: AutomationSchedule
    let save: (AutomationSchedule, Bool) throws -> Void
    @State private var authorized = false
    @State private var error: String?

    private var reviewed: AutomationSchedule? { try? schedule.validated() }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Command") {
                    TextField("Name", text: $schedule.name)
                    HStack {
                        TextField("Executable", text: $schedule.executable, prompt: Text("/usr/bin/…"))
                        Button("Choose…") { choose(directory: false) }
                            .accessibilityLabel("Choose Executable")
                    }
                    ForEach(schedule.arguments.indices, id: \.self) { index in
                        HStack {
                            TextField("Argument \(index + 1)", text: argumentBinding(index))
                            Button("Remove Argument \(index + 1)", systemImage: "minus.circle") {
                                if schedule.arguments.indices.contains(index) { schedule.arguments.remove(at: index) }
                            }.labelStyle(.iconOnly).buttonStyle(.borderless)
                        }
                    }
                    Button("Add Argument", systemImage: "plus") { schedule.arguments.append("") }
                        .disabled(schedule.arguments.count >= NativeAgentTools.maximumCommandArguments)
                    Text("Each argument is passed exactly as entered, including spaces. No shell expansion or quoting is applied.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        TextField("Working Folder", text: $schedule.directory, prompt: Text("Absolute local folder"))
                        Button("Choose…") { choose(directory: true) }
                            .accessibilityLabel("Choose Working Folder")
                    }
                }
                Section("Schedule") {
                    Picker("Repeat", selection: $schedule.cadence) {
                        Text("Every Interval").tag(AutomationSchedule.Cadence.interval)
                        Text("Daily").tag(AutomationSchedule.Cadence.daily)
                    }
                    if schedule.cadence == .interval {
                        HStack {
                            TextField("Minutes", value: $schedule.intervalMinutes, format: .number)
                            Stepper("Minutes", value: $schedule.intervalMinutes, in: 1...10_080)
                                .labelsHidden().fixedSize()
                        }
                        HStack {
                            ForEach([5, 15, 60, 1_440], id: \.self) { minutes in
                                Button(minutes < 60 ? "\(minutes) min" : minutes == 60 ? "1 hour" : "24 hours") {
                                    schedule.intervalMinutes = minutes
                                }.buttonStyle(.bordered)
                            }
                        }
                    } else {
                        HStack {
                            Picker("Hour", selection: $schedule.hour) {
                                ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }
                            Picker("Minute", selection: $schedule.minute) {
                                ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                            }
                        }
                        TextField("Time Zone", text: $schedule.timeZoneID)
                    }
                    Toggle("Enable Schedule", isOn: $schedule.enabled)
                    Text("Missed runs are skipped. Daily times use the selected time zone; intervals restart from the latest attempt. Up to four commands can run at once.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Review") {
                    Text(reviewed?.commandReview ?? schedule.commandReview)
                        .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Text("This command runs in the background with Trellis’s environment and your user permissions. The folder is a starting location, not a sandbox. Commands may change files or access the network. Each run stops after 30 seconds.")
                        .font(.callout).foregroundStyle(.secondary)
                    if schedule.enabled {
                        Toggle("Allow this command to run automatically", isOn: $authorized)
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(schedule.enabled ? "Save and Enable" : "Save Paused") {
                    do {
                        try save(try schedule.validated(), authorized)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(schedule.enabled && !authorized)
            }.padding(16)
        }
        .frame(width: 660, height: 720)
        .onChange(of: schedule) { _, _ in authorized = false; error = nil }
    }

    private func argumentBinding(_ index: Int) -> Binding<String> {
        Binding(get: { schedule.arguments.indices.contains(index) ? schedule.arguments[index] : "" },
                set: { if schedule.arguments.indices.contains(index) { schedule.arguments[index] = $0 } })
    }

    private func choose(directory: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = directory
        panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        if directory { schedule.directory = path } else { schedule.executable = path }
    }
}
