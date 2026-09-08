# Architecture

Trellis is one native Xcode application with SwiftUI presentation, a narrow
AppKit/C terminal bridge and two small Swift helpers. Sparkle is its only Swift
package dependency. See [dependency pins](DEPENDENCIES.md).

## Runtime paths

1. **Terminal:** a retained Ghostty surface owns rendering, input and its PTY.
   A validated launch envelope starts a shell, agent CLI or SSH/tmux attachment
   through `SessionLaunch`.
2. **Native Codex conversation:** `codex app-server` owns its tools, approvals,
   history, compaction and ChatGPT authentication. Trellis presents structured
   events and preserves the native thread identity.
3. **Direct API conversation:** Trellis owns the model transport, scoped tool
   executor, reviewed actions and specialist delegation. Provider credentials
   and billing are separate from native agent subscriptions.

Terminal output is not an authoritative protocol for completion or approvals.
A native side conversation is separate from a CLI running in a pane; do not
represent one as observing the other's internal state.

## Source map

| Area | Entry points |
| --- | --- |
| App composition and windows | `Trellis/TrellisApp.swift`, `Workspace.swift` |
| Home and saved workspaces | `WorkspaceHomeView.swift`, `WorkspaceArchive.swift` |
| Terminal ownership and input | `TerminalRuntime.swift`, `TerminalView.swift`, `TerminalState.swift` |
| Pane arrangement and launch | `PaneLayout.swift`, `LaunchProfile.swift`, `ShellConfiguration.swift` |
| Native Codex | `CodexSubscriptionClient.swift`, `CodexConversationRuntime.swift`, `CodexConversationView.swift` |
| Direct API harness | `NativeAgentRuntime.swift`, `NativeAgentTools.swift`, `DirectModelClient.swift`, `NativeAgentPanel.swift` |
| Specialists and model connections | `AgentTeam.swift`, `ModelConnections.swift`, `ModelCatalogCache.swift` |
| Memory and agent integration | `MemoryStore.swift`, `MemoryIntegration.swift`, `Integrations/` |
| Scheduling and shutdown | `AutomationScheduler.swift`, `DreamingScheduler.swift`, `ClosingWorkspaceCleanup.swift` |
| Helper executables | `Helpers/SessionLaunch.swift`, `Helpers/MemoryBridge.swift` |
| Focused verification | `Checks/`, `script/check-features.sh`, `script/check-host.sh` |

Paths without a directory prefix are under `Trellis/`. Keep related code together;
do not add a package, protocol or service layer without a concrete second use.

## State ownership

| State | Owner and persistence |
| --- | --- |
| Windows, tabs, selected panes and navigation | Window-scoped workspace; versioned `WorkspaceArchive` JSON |
| Terminal surface and PTY | Session retains the native view outside SwiftUI recomputation; live state is not serialized |
| Native Codex history | Codex owns history; Trellis saves its thread ID with the session |
| Direct chat and specialist transcripts | In-memory conversation state |
| Presentation, catalogues and connections | Bounded app-managed files and preferences; keys use Keychain |
| Approved project knowledge | Markdown, revision checks, proposal records and an apply/recovery journal |
| Scheduled work | App-owned scheduler and saved configuration; no system daemon or cron installation |

There is no SQLite registry in this version. Development and distributed apps use
separate Application Support directories. This does not isolate installed agent
accounts or access to the user's files.

A disappearing SwiftUI view does not end a session. Keep one owner for every
terminal surface, attach the existing view as presentation changes, and never
recreate a process because a view recomputed. A surface cannot have two native
hosts simultaneously.

Restoration recovers session identities and layout. Local processes remain
stopped; SSH/tmux reconnects only on request. Never infer process identity from a
saved PID or replace a missing remote workload silently.

## Execution and trust boundaries

Launch intent is an executable, literal argument array and working directory.
The fixed launcher reads a protected, validated envelope and performs exact
argument-based execution. Do not interpolate project names, prompts or remote
directories into shell code. Ghostty owns terminal PTYs; headless tools and native
agent transports have separate, explicit process ownership and cancellation.

Direct tools validate scope in host code. Approval binds to the displayed action;
terminal commands also bind to the originating pane and input state. Output
sharing is a separate decision. Native Codex retains its upstream approval
protocol. A prompt is not a security boundary.

Memory changes use proposal review, base-revision validation and journaled
recovery. Same-user terminal agents can still access files allowed by the OS;
the bridge alone is not a filesystem sandbox.

## Responsiveness and failure

Native view operations stay on the main actor. Model streams, bounded child
processes and disk work use explicit asynchronous ownership. Handle partial
frames, missing usage, cancellation and transport failure as normal inputs.
Terminal rendering must not wait for a model or a memory operation.

Canceling a request, stopping an owned process and detaching a tmux attachment
have different effects. The shared quit path awaits owned chat, automation and
Dreaming work before quitting or a Sparkle relaunch. Remote tmux workloads can
survive detachment.

Errors should identify the failed capability and the available recovery. Keep an
ordinary shell usable when a provider, account or optional plugin is unavailable.
Logs should omit credentials, terminal contents and full prompts by default.

See [security](docs/SECURITY-AND-PRIVACY.md), [agent contracts](contracts/PROTOCOLS.md),
[session behavior](docs/TERMINAL-AND-SESSIONS.md) and
[verification](docs/VERIFICATION.md) for detailed boundaries.
