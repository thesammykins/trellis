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

**UI restoration:** projects, tab order and selected page can be restored from local state.

**Agent history resume:** a new process continues an upstream conversation from a stored ID. This is not the same as restoring the original terminal process.

**Remote process reattachment:** connect to an existing tmux-managed process. This is genuine process continuity while that remote process survives.

**Local process persistence:** optional later work requiring a real supervisor or local tmux. Ordinary child processes hosted by a destroyed terminal surface are not promised to survive application exit.

Display the relevant class. Never make “Restore session” a vague claim that covers all four.

## Performance and health

Bound scrollback and decoded event queues. Coalesce nonterminal inspector updates. Keep disk indexing, syntax analysis and model requests away from the render/input path. Measure launch time, typing responsiveness, idle CPU, resize and memory growth on the user's Mac. Initial measurements establish a baseline; do not invent benchmark results in the UI or README.

Exercise a fast-output command, Unicode/emoji/CJK text, multiline paste, an agent TUI, an editor, repeated tab switching and external monitor changes. Verify Ctrl+C reaches the right foreground work and that stopping a headless job does not terminate a terminal session.

## Clipboard and escape-sequence policy

Treat terminal-originated clipboard requests, links and file references as untrusted input. Confirm sensitive clipboard writes/reads according to explicit preferences. Only allow approved URL schemes, and require clear intent before opening local files or executing anything. An OSC sequence cannot grant access to memory, account credentials or application automation.

See [LEARNING-AND-SUGGESTIONS.md](LEARNING-AND-SUGGESTIONS.md) for shell-state-aware input assistance and [VERIFICATION.md](VERIFICATION.md) for the small set of relevant automated checks.
