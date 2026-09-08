# Terminal and session engineering

## Preserve the real terminal

A shell, Codex TUI, OpenCode TUI and Pi TUI all run against a real PTY and terminal emulator. Native memory/learning UI stays outside that grid. Do not process the transcript as HTML, replace terminal redraws with chat messages or intercept input to manufacture an agent experience.

The selected path is the full Ghostty macOS embedding interface. A VT parser alone does not supply the complete embedding solution. Upstream's full C header and its Swift application are the integration references; pin the actual revision before choosing API calls. [S01](../research/SOURCES.md#s01)[S03](../research/SOURCES.md#s03)[S05](../research/SOURCES.md#s05)

## Required host responsibilities

The host must bridge native keyboard events, modifier semantics, IME composition, marked text, clipboard operations, mouse selection, scrolling, drag/drop, focus, resize and display-scale changes. It must service runtime callbacks and render scheduling according to the selected Ghostty revision. Do not invent a second Metal renderer unless the M0 decision explicitly changes scope.

Treat the C ABI as an ownership boundary. Document which calls are main-thread-only, how callback user data stays alive, and when configuration strings may be released. Free surfaces exactly once after callbacks cannot reach released objects. Keep opaque pointers out of general application state and SwiftUI models.

A GPU surface is not automatically a complete accessible terminal. Verify selection and text navigation with VoiceOver, including long scrollback and alternate screen behaviour. Native UI accessibility alone does not establish terminal accessibility.

## Launch envelope

Use the conceptual structure `executable + argv + cwd + environment + session identity`. The host resolves an installed binary using configured paths and a controlled environment. It must not assume a GUI app inherits the user's interactive shell PATH.

Allow an explicit executable selection. A one-time shell environment probe may be offered, but explain that starting a login shell executes user configuration; cache and time-bound it. Do not run shell startup files on every keystroke or trust repository-local scripts merely because a directory was selected.

The Ghostty surface command field is a string in the inspected header. Use the fixed Swift launcher described in the architecture to avoid interpolating data into this field. Validate quotes, spaces, Unicode and signal forwarding with the actual parser. [S03](../research/SOURCES.md#s03)

Credentials do not belong in a launch envelope persisted to disk. Pass only scoped references or let the upstream agent own authentication. Environment values inherited by an agent are visible to that process and are not a security boundary.

## Session identities

Store these separately:

- `sessionID`: Trellis's stable identity.
- `agentSessionID`: upstream conversation/history identity, when known.
- `attachmentID`: a specific terminal/client attachment.
- `remoteSessionID`: tmux identity when persistence is remote.
- `projectID` and `worktreeID`: knowledge scope and working-copy scope.

A display title, PID, terminal title escape or “last session” command is not a stable identity.

## Lifecycle

```text
created → launching → active → exited
                    ↘ failed
active → detached                      only for a persistent backend
active → reconnecting → active         only after attach verification
reconnecting → sessionMissing          explicit user recovery required
```

Track agent work state separately: unknown, idle, working or awaiting approval, with an evidence source. A shell process can be active while the agent is idle. A transport can be disconnected while the remote agent is working.

Never infer successful completion merely because output stopped arriving. When no structured event is available, say “Activity unavailable” or “Process running,” not “Agent finished.”

## Restoration classes

**UI restoration:** projects, retained windows, tabs, pane arrangement and the selected page are restored from local state.

**Agent history resume:** a new process continues an upstream conversation from a stored ID. This is not the same as restoring the original terminal process.

**Remote process reattachment:** connect to an existing tmux-managed process. This is genuine process continuity while that remote process survives.

**Local process persistence:** local tmux sessions can be reattached while that backend survives. Ordinary child processes hosted by a destroyed terminal surface are not promised to survive application exit.

Display the relevant class. Never make “Restore session” a vague claim that covers all four.

## Home and reopening

Home shows retained sessions across all open Trellis windows, with separate open
and saved sections, search, session grid/list layouts and SSH favorites. Opening a session
from Home selects it in its owning window; it does not create another terminal or
restart a stopped one. “Running” describes the local process, “SSH process open”
does not prove remote authentication, and “Disconnected” does not establish
whether a tmux workload is still alive. Active native chats show working or
approval state separately from terminal process state.

The workspace archive saves window/session identities, the last active window,
project and pane selection, tab order, the split tree (up to eight panes per tab), maximization, Home/terminal
or project-page selection, sidebar visibility and inspector section/visibility.
It also retains session names, favorites, last-known titles, last-used ordering
and captured launch settings. AppKit saves each window's frame. Terminal divider
proportions use bounded local preferences keyed by window and split identity;
they are captured after a divider drag or explicit Balance and restored within
the native pane size limits.

A fresh window starts on Home without a shell. Reopening reconstructs saved
terminal tabs in a stopped state. **Start Again** launches a new local process;
**Connect** opens a new ordinary SSH login; **Reconnect** attaches to the saved
tmux identity without creating a replacement. Asking the built-in agent explicitly
creates a local shell if no session is selected. These actions are separate from
restoration and from any user-enabled automation schedules.

Closing a tab or pane removes its saved entry. Closing one of several windows
removes that window from restoration; closing the last retains its final saved
tabs for the next launch. Quitting with several windows open retains all of them;
the previously active window is brought to the front after they are recreated.
Home is not an unlimited history of closed sessions. Its display/order settings
and stopped-session visibility are shared app preferences.

Restoration does not recover terminal scrollback, terminal search/selection,
unsent chat drafts, Direct API conversation history, or previous window minimized
and full-screen state. Native Codex conversations retain only their
backend thread ID in the workspace archive; displaying their inspector can load
upstream history, but does not submit a turn. Missing executables, folders or
upstream history still require recovery. Invalid workspace data is reported and
left unchanged rather than replaced by an empty archive. Legacy records without
the newer presentation fields retain their identities and open in terminal view.
Archives without an active-window identity keep the default window activation order.

`WorkspaceArchiveCheck` covers migration, eight-pane/window presentation and saved
Codex identities. `NativePaneSplitCheck` covers isolated preference restoration,
bounds, stable hosting controllers and Balance. Its hidden native windows do not
prove physical dragging, Ghostty focus or real relaunch behavior; those require
the integrated app checks recorded in [STATUS.md](STATUS.md).

## Performance and health

Bound scrollback and decoded event queues. Coalesce nonterminal inspector updates. Keep disk indexing, syntax analysis and model requests away from the render/input path. Measure launch time, typing responsiveness, idle CPU, resize and memory growth on the user's Mac. Initial measurements establish a baseline; do not invent benchmark results in the UI or README.

Exercise a fast-output command, Unicode/emoji/CJK text, multiline paste, an agent TUI, an editor, repeated tab switching and external monitor changes. Verify Ctrl+C reaches the right foreground work and that stopping a headless job does not terminate a terminal session.

## Clipboard and escape-sequence policy

Treat terminal-originated clipboard requests, links and file references as untrusted input. Confirm sensitive clipboard writes/reads according to explicit preferences. Only allow approved URL schemes, and require clear intent before opening local files or executing anything. An OSC sequence cannot grant access to memory, account credentials or application automation.

See [LEARNING-AND-SUGGESTIONS.md](LEARNING-AND-SUGGESTIONS.md) for shell-state-aware input assistance and [VERIFICATION.md](VERIFICATION.md) for the small set of relevant automated checks.
