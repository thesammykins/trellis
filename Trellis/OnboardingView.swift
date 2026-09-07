import SwiftUI

struct GettingStartedView: View {
    private enum Step: Int, CaseIterable, Hashable {
        case terminal, agents, context, personalize

        var title: String {
            switch self {
            case .terminal: "Your terminal is ready"
            case .agents: "Choose how the agent runs"
            case .context: "You control what leaves the terminal"
            case .personalize: "Make the workspace comfortable"
            }
        }

        var symbol: String {
            switch self {
            case .terminal: "terminal"
            case .agents: "sparkles"
            case .context: "hand.raised"
            case .personalize: "paintbrush"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.terminal
    @AccessibilityFocusState private var focusedStep: Step?
    private let onStartShell: () -> Void
    private let onChooseAgent: () -> Void

    init(onStartShell: @escaping () -> Void = {}, onChooseAgent: @escaping () -> Void = {}) {
        self.onStartShell = onStartShell
        self.onChooseAgent = onChooseAgent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Getting Started").font(.headline)
                Spacer()
                Button("Skip for Now") { complete(with: nil) }.buttonStyle(.borderless)
            }
            .padding(.horizontal, 24).padding(.top, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(step.title, systemImage: step.symbol).font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focusedStep, equals: step)
                    stepContent
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            HStack {
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                Spacer()
                if step != .terminal { Button("Back", action: previous) }
                if step == .personalize {
                    Button("Choose an Agent") { complete(with: onChooseAgent) }
                    Button("Start in Home Shell") { complete(with: onStartShell) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue", action: next).buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 640,
               minHeight: 430, idealHeight: 470, maxHeight: 650)
        .onExitCommand { complete(with: nil) }
        .onAppear { focusedStep = step }
        .onChange(of: step) { focusedStep = step }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .terminal:
            Text("Home Shell is available immediately with no account, model, or project setup. Restored workspaces return to their existing sessions.")
                .font(.title3)
            feature("Open a project when directory scope matters", symbol: "folder")
            feature("Use ⌘T for another shell and ⌘P to switch sessions", symbol: "keyboard")

        case .agents:
            route("Agent in Terminal", detail: "Launches Codex, OpenCode, Pi, or another installed harness in a terminal session. That tool owns its sign-in and conversation.", symbol: "terminal.fill")
            route("Trellis Chat", detail: "A native side conversation using the Direct API model configured in Settings. API credentials are separate from a ChatGPT subscription.", symbol: "bubble.left.and.bubble.right")
            Text("Both routes stay attached to the selected terminal session, but they are separate conversations.")
                .font(.caption).foregroundStyle(.secondary)

        case .context:
            feature("Files follows the active local terminal folder. Browsing does not run cd or send a file.", symbol: "folder.badge.questionmark")
            feature("Attach Terminal creates an editable snapshot before it is sent to Chat.", symbol: "paperclip")
            feature("Tool execution and the output released to a model are reviewed separately.", symbol: "checkmark.shield")
            feature("Project Memory keeps approved Markdown notes. Proposed changes remain reviewable.", symbol: "books.vertical")

        case .personalize:
            Text("Your shell works with the defaults. Appearance, app theme, terminal theme, and terminal font are optional and can be changed later without resetting your sessions.")
                .font(.title3)
            SettingsLink { Label("Open Settings", systemImage: "gearshape") }
            Text("Start with the home shell, or choose an installed agent. You can reopen this guide from Help at any time.")
                .foregroundStyle(.secondary)
        }
    }

    private func feature(_ text: String, symbol: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("List item: " + text)
    }

    private func route(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func next() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func previous() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func complete(with action: (() -> Void)?) {
        UserDefaults.standard.set(true, forKey: "didReadGettingStarted")
        action?()
        dismiss()
    }
}
