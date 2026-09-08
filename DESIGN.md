# DESIGN.md · Trellis

**Status:** design guidance for the native app. See [current behavior and limits](docs/STATUS.md).

## Design thesis

A calm native workspace around a precise terminal. The terminal is where work happens; the surrounding app helps the user know where they are, what context is available, what needs attention and what will persist.

The single organising hierarchy is **project → session → context and review**. Memory, learning and dreaming are views over the same project and activity, not separate dashboards with competing navigation systems.

## Visual direction

Keep a narrow project source list, a dominant central terminal, restrained session
tabs and a contextual inspector. The [Home](assets/screenshots/home.jpg) and
[workspace](assets/screenshots/workspace.jpg) screenshots show the running app
with disposable example projects.

Use one semantic design system that adapts to light and dark appearance.

The terminal renders actual shell and agent output. Do not insert simulated chat
cards into the terminal grid. The native side chat uses distinct conversation
turns, rich text and one stable composer beside the retained terminal.

**Precedence:** accessibility and actual Apple controls override decorative details.

## Native composition

Use a SwiftUI `WindowGroup` for project workspaces, a separate `Settings` scene and explicit auxiliary windows only where a task benefits from them. A split layout holds the source list, session area and optional inspector. Use native toolbars, menus, contextual menus, selection states and focus routing.

The terminal is an AppKit `NSView` hosted by a narrow representable. That is a native bridge, not a concession to a web application. Other screens remain SwiftUI except where the native text system is needed for high-quality editing or a large diff.

Prefer platform-provided Liquid Glass in the control layer. Custom glass is reserved for a small number of controls that standard components cannot express. Do not stack arbitrary blur panels, add opaque fills behind system chrome or put translucent glass over terminal text. [S09](research/SOURCES.md#s09)[S10](research/SOURCES.md#s10)

## Layout contract

These dimensions are initial design targets in points, not fixed assumptions about future SDK measurements.

| Region | Preferred behaviour |
| --- | --- |
| Main window | Initial size around 1440 × 900; usable compact layout at 1000 × 680 |
| Source list | Initially 220–240 wide; resizable and collapsible |
| Inspector | Initially 300–340 wide; user-resizable and independently collapsible |
| Terminal | Receives remaining space; collapse inspector before making terminal unusably narrow |
| Toolbar | Standard macOS layout and control sizes; no custom simulated titlebar |
| Session strip | Compact, horizontally scrollable tabs with overflow navigation |
| Text | System UI font; installed monospaced terminal font selected independently |

No content view should depend on pixel positions copied from the artwork. Respect titlebar safe areas, full-screen changes, display scaling and text size preferences.

## Surface and colour rules

Use semantic roles for primary text, secondary text, separators, selections and
backgrounds. Whole-app themes can coordinate those roles while leaving terminal
appearance independent. A user may choose a dark terminal inside a light app.
The default terminal background is opaque enough for long reading sessions.

A muted green/teal accent can identify the active session and selected project. Respect the user's accent colour where normal controls do. Warning, error and active-work states must also have a label or distinct icon. Never make colour the only indication of approval, connection state or progress.

Use SF Symbols where appropriate and verify symbol availability in the installed SDK. Do not invent an icon package or redistribute Apple font files. Agent names are sufficient when licensed agent logos are unavailable.

Prefer simple surfaces and thin semantic dividers. Avoid the appearance of a dashboard made of floating cards. A source-list row has an icon, a name and at most one secondary line. More metadata belongs in the inspector.

## Screen 1 · Project workspace

**Purpose:** get into the correct project and agent immediately.

The source list groups Projects and Knowledge. Projects show a folder name and, when necessary, a small remote indicator. Knowledge exposes Project memory, Review and Activity. Dreaming appears as a quiet status/action near the bottom, not a permanently animated widget.

The toolbar contains project identity, New Session, workspace search and inspector visibility. A mode control is available but need not consume a large segmented control permanently. In a compact window, move it to an accessible menu. The selected mode is always discoverable.

The central area contains sessions for the selected project. A tab shows a session title, its agent or Shell label, a close affordance and a small state indicator. Sessions retain identity while changing titles. Opening the same agent again creates another session unless the user explicitly chooses an existing one.

The inspector follows the active session. Its primary tabs are Context and Activity in Advanced mode, with Learn available in Learning mode. Show supplied memory, outstanding approvals and connection details without exposing a constant stream of distracting event noise.

Closing a busy local session offers the real consequence: stop its process, cancel, or detach if the backend genuinely supports detachment. Closing a remote attachment must not imply stopping the remote workload. A local nonpersistent session must never offer a fake Detach option.

## Screen 2 · New session

**Purpose:** launch the right tool with visible scope and no command-line wrestling.

Use a native sheet or popover with Agent, Project, Location and Start/Resume choices. Offer Shell alongside installed agents. Show the detected executable path and version in secondary details. Missing agents have a setup action, not a silently executed installation script.

A launch preview shows the working directory, local/remote host, account/provider and whether the session will share an existing worktree. Advanced options expose arguments and environment variable names, not secrets. Values that contain credentials are never shown in a general preview.

Resume chooses an exact stored agent session ID. “Most recent session” may be a user-facing action, but it must first resolve to an explicit identity rather than being used as the app's internal restore mechanism.

## Screen 3 · Memory library

**Purpose:** make durable knowledge inspectable and portable.

Keep project navigation in place. Replace the central terminal area with a native list-and-document view. The list supports Decisions, Constraints, How-to, References and Lessons, plus search. These are metadata filters, not mandatory duplicate directory structures.

The document pane shows Markdown, sources, revision, scope and review status. The inspector shows backlinks, conflicting claims, last verification and context-delivery history. Stale knowledge is labelled, not quietly treated as current.

Provide Open in Finder, Export, Reveal source and Edit. An external edit is recognised through the same reconciliation path as an in-app edit. Broken metadata or malformed Markdown produces an actionable issue rather than deletion of the page.

Empty state: “No project memory yet. Keep a decision from this session, or add a note.” Do not fabricate seeded project facts.

## Screen 4 · Review proposals

**Purpose:** make learning and overnight changes visible before they become guidance.

Use a split view with proposal list, change detail and evidence. Each proposal shows its authoring run, model/provider, target path, base revision and reason. Group related file changes into a transaction, but allow rejection or deferral of a group.

Show before/after text or a native diff. The decision controls are Approve and apply, Reject, and Edit proposal. Applying is unavailable when the current base hash differs. Offer Regenerate against current content rather than force-overwriting the user's edits.

A change to `AGENTS.md` or a skill is explicitly labelled “Changes agent instructions.” Changes to global guidance are separate from project-local changes and always require explicit approval. A large green Accept All button must not hide these differences.

Application state must say Proposed, Applying, Applied, Rejected, Stale or Failed. “Approved” and “Applied” are not interchangeable. A recoverable journal owns the actual transaction.

## Screen 5 · Learning mode

**Purpose:** teach in the context of real work without replacing it.

The terminal and session stay unchanged. The Learn inspector offers Explain selection, Explain proposed command and Review this change. It can show a short explanation, the relevant concept, what may change, and how to verify the result.

Start small: one useful explanation and one next action. Longer detail is expandable. Avoid unsolicited essays or a second agent constantly watching all input. A user can ask a follow-up in an explicit native explanation surface; that is a distinct side task, not a second active terminal prompt.

A suggestion displays its source and scope. Accepting it inserts text into an eligible shell editor; it does not execute it. In an agent TUI, full-screen editor or password prompt, shell suggestions are disabled. Unknown terminal state is not a safe state.

Switching modes preserves focus, scroll position and process state. It cannot alter permissions, install packages or enable cloud transmission.

## Screen 6 · Remote session

**Purpose:** distinguish transport from workload survival.

Use labels such as Connected to lab, Reconnecting, Detached, Remote session missing and Host identity changed. Show host alias, remote directory and session ID in details. Avoid a global “Ready” badge that masks a disconnected active tab.

During disconnection, retained output is visibly stale and input is disabled. Reconnecting attaches to the recorded session. If it is absent, explain the choices: investigate, resume agent history as a new process, or start fresh. Never make replacement work look like successful reattachment.

A changed host key blocks connection with a clear explanation. The UI can reveal OpenSSH diagnostics but must not encourage disabling host verification.

## Screen 7 · Dreaming settings and report

**Purpose:** keep automation deliberate and understandable.

Settings include enabled projects, local time window, eligible model/account, maximum work/cost, battery policy, research permission and retention. Default state is Off. Enabling it does not grant permission to rewrite instructions.

The last-run report shows inputs considered, inputs excluded, proposals created, contradictions, cost or unavailable cost information, model identity and any skipped work. “No useful changes found” is a successful possible outcome.

The standard badge says “Proposals only.” If a future user-approved auto-apply policy is enabled for low-risk page types, show its exact scope. Never visually equate it with permission to alter skills or root instructions.

## Screen 8 · Connections and model accounts

Group Accounts, Agent installations, SSH and Memory transport separately. A ChatGPT-connected Codex account is not shown as an OpenAI API key. OpenCode Go and Zen are distinct options, even when they share a provider ecosystem.

Every assistant action should make its route discoverable: for example, “Codex · ChatGPT account” or “Direct API · selected provider.” Do not silently substitute a paid API when a subscription limit is reached.

## Keyboard and focus

Provide standard menu equivalents for New Window, New Session, Close Session,
Find, Copy, Paste and Settings. Use Cmd+T for New Session, Cmd+W for the active
close action and Cmd+P for session search. Use conventional tab navigation
shortcuts with remapping.

Focus enters the terminal when a session opens. Clicking the inspector moves focus intentionally. Closing the inspector restores the previous terminal focus. Text input and IME composition go through the native terminal input bridge, not ad hoc SwiftUI key handlers.

Do not steal Ctrl+C, Ctrl+D, Escape, Option combinations or terminal-specific shortcuts through a global event monitor. Command routing must check the focused responder and registered shortcut policy.

## Accessibility and reduced effects

Validate VoiceOver navigation for projects, tabs, memory pages, review controls and connection state. Expose a meaningful terminal accessibility surface; do not label a custom GPU view accessible without testing text navigation and selection.

Respect Reduce Transparency and Reduce Motion. Do not animate a glass shimmer during token streaming. Maintain visible focus indicators and readable contrast in active and inactive windows. Support font scaling and full keyboard operation. Notifications should avoid speaking every streamed token or exposing sensitive prompt content on the lock screen.

## Visual acceptance

Review light and dark appearance, compact and wide windows, high-density and
standard displays, full-screen mode, inactive windows and accessibility settings.
Capture real screenshots from the compiled app; assess hierarchy and usability.

A screenshot containing fabricated “live” sessions does not count as implementation evidence. Preview fixtures may exist, but must be marked as preview data and excluded from normal runtime.

## Session identity and themes

Use named semantic app roles with optional terminal independence. Native controls,
readable contrast and truthful states take precedence. Keep UUIDs internal,
user nicknames distinct from process titles, and destructive session termination
separate from detaching or forgetting attachments.
