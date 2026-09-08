import Foundation

// Shared by Settings search and direct links from the agent pane.
enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance, terminal, workspace, agent, team, accounts, shells, automations, learning, updates
    static let openAgentNotification = Notification.Name("TrellisOpenAgentSettings")
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .terminal: "Terminal"
        case .workspace: "Workspace"
        case .agent: "Trellis Agent"
        case .team: "Agent Team"
        case .accounts: "Accounts & Agents"
        case .shells: "Shells"
        case .automations: "Automations"
        case .learning: "Learning & Dreaming"
        case .updates: "Updates"
        }
    }
    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .terminal: "terminal"
        case .workspace: "sidebar.left"
        case .agent: "sparkles"
        case .team: "person.3"
        case .accounts: "person.crop.circle"
        case .shells: "apple.terminal"
        case .automations: "clock.arrow.circlepath"
        case .learning: "moon"
        case .updates: "arrow.down.circle"
        }
    }
    private var keywords: String {
        switch self {
        case .appearance: "theme color light dark system import ghostty"
        case .terminal: "font size keyboard keybinding shortcut option alt google download"
        case .workspace: "tabs vertical horizontal collapsed sidebar layout density inspector presets"
        case .agent: "native chat direct api endpoint url key credentials model reasoning name connection responses completions"
        case .team: "subagents delegate escalate routing model cache tokens budget context specialist coding explore writing review"
        case .accounts: "codex chatgpt opencode go zen pi claude gemini login sign in installation executable model default"
        case .shells: "shell executable arguments login zsh bash fish"
        case .automations: "schedule cron timer interval daily command task background"
        case .learning: "learning dreaming model route overnight schedule proposals automation"
        case .updates: "sparkle version update upgrade automatic github release"
        }
    }
    func matches(_ query: String) -> Bool {
        let text = title + " " + keywords
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedStandardContains($0) }
    }
}
