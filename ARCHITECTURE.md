# Architecture

## Main decision

Build a native host around two distinct paths:

1. **Terminal path:** Ghostty surface → PTY → real shell or agent CLI.
2. **Structured integration path:** typed agent adapters and memory services → documented plugin/API interfaces.

Terminal bytes are for rendering. They are not a reliable authoritative event API for agent state. A tool's TUI can redraw, truncate, switch alternate screens or change output format. Do not infer approvals, completion or knowledge provenance by scraping coloured output.

Ghostty's own macOS application combines Swift, AppKit and SwiftUI with its C interface, which supports the feasibility of this host boundary. The full embedding interface and the separately extracted VT core are not interchangeable choices. [S01](research/SOURCES.md#s01)[S03](research/SOURCES.md#s03)[S05](research/SOURCES.md#s05)

## Application shape

Use one Xcode app project, a small local Swift package for shared targets, and explicit helper executable targets only when needed. Begin with the app, domain and terminal boundary. Add other targets as they gain real code rather than scaffolding a large empty framework tree.

```text
Trellis/
  App/                       App entry, scenes, composition root
  Features/
    Workspace/               Projects, session tabs, routing
    Memory/                  Library, review, evidence
    Learning/                Contextual explanation UI
    Connections/             Agents, accounts, SSH setup
    Settings/
  Platform/                  App Intents, Keychain, notifications
  Packages/TrellisKit/
    Sources/
      TrellisDomain/         IDs, values, policies, protocol contracts
      TerminalEngine/        Ghostty C bridge and AppKit view
      SessionRuntime/        Launch envelopes and local/remote lifecycle
      AgentRuntime/          Codex/OpenCode/Pi adapters, framed transports
      MemoryEngine/          Markdown, index, proposals, consolidation
  Helpers/
    SessionLaunch/           Exact argv/cwd launch from a validated envelope
    MemoryBridge/            Swift MCP/IPC frontend when required
  Integrations/              Minimal native-agent plugin shims
  Vendor/Ghostty/            Pinned source/artifact metadata and patches
  script/                    Build/run, pinning, useful smoke checks
  .codex/environments/       Run action, created with the runnable project
  docs/                      Decisions, evidence and hand-offs
```

This is a recommended future repository layout. The blueprint ZIP is not that already-built repository.

## Dependency direction

`TrellisDomain` imports no UI framework or agent SDK. All services depend on the domain. The app composes the services and their views. `TerminalEngine` does not import memory or provider code. `AgentRuntime` consumes a narrow memory-access protocol rather than importing a memory view. `MemoryEngine` asks a model client through an injected protocol and never reaches into a terminal.

`SessionRuntime` depends on terminal lifecycle contracts, not SwiftUI. `TerminalEngine` implements the surface operations. The composition root wires the two; do not let each service construct the other.

Avoid one giant `AppModel`, a universal event bus and a protocol for every class. Use explicit services and value types with the narrowest useful responsibilities.

## State ownership

| State | Owner | Persistence |
| --- | --- | --- |
| Window selection, inspector visibility, split sizes | Window-scoped observable store | Scene restoration/preferences |
| Projects, sessions and connection profiles | Registry actor | SQLite with migrations |
| Terminal parser, renderer and PTY process | Selected Ghostty full-engine surface | Live process state, not Codable |
| Session launch and stop policy | Session coordinator | Durable identity and lifecycle events |
| Agent-native thread/session identity | Agent adapter mapping | Registry; upstream owns its history |
| Approved knowledge and page provenance | Memory repository | Markdown and durable source records |
| Search index and backlinks | Indexer actor | Rebuildable SQLite tables |
| Pending proposals and apply journal | Review service | Durable files/database with reconciliation |
| Provider secrets | Appropriate credential owner | OS Keychain or upstream agent's supported store |
| Nightly job progress | Consolidation coordinator | Durable checkpoint and idempotency key |

A view disappearing is not a session-ending event. Do not put surface creation in repeatedly evaluated view code. Keep the surface alive for the actual session lifetime, and attach it to a view under an explicit ownership rule. One surface cannot be hosted by two windows simultaneously; transfer it or create a separate attachment when the backend supports that.

## Process topology

```text
Trellis.app (SwiftUI + native views)
  ├─ Ghostty surface(s): terminal rendering and PTY child ownership
  │    └─ fixed Trellis launcher → shell / agent CLI / ssh attachment
  ├─ typed adapter connections
  │    ├─ Codex supported local integration or separate app-server task
  │    ├─ OpenCode managed server with attached TUI where supported
  │    └─ Pi TUI extension or separate RPC task
  ├─ shared memory service (Swift actor)
  │    └─ authenticated local bridge for enabled agent plugins
  └─ optional proposal-generation job
       └─ bounded, explicitly authorised model route
```

The CLI session and a headless adapter session are not automatically the same agent process. A second `codex app-server` or `pi --mode rpc` must never be claimed to be observing an already-running independent TUI. Prefer actual plugin events for those TUIs; otherwise expose the reduced capability honestly. OpenCode's documented attach flow provides an explicit server/TUI relationship, subject to a tested version. [S11](research/SOURCES.md#s11)[S16](research/SOURCES.md#s16)[S21](research/SOURCES.md#s21)

## Terminal engine selection

Use the full upstream macOS embedding path that includes the renderer and normal terminal lifecycle, isolated behind `TerminalEngine`. A VT-only package is appropriate for parsing terminal state but would leave rendering, PTY integration and native input work to this application. That is a materially larger project and is not the default fallback.

The first spike must establish the exact Ghostty revision, header, build options, artifact, resources and lifetime requirements. Pin source and binary together. Upstream documents a Zig-version dependency for each Ghostty release; do not choose the newest Zig independently. [S04](research/SOURCES.md#s04)

Do not maintain two competing PTY owners. Under the selected full-engine path, the engine owns the terminal PTY; the host owns launch policy, identity and the embedding surface's lifetime. Headless API processes can use a separate Foundation/POSIX process supervisor because they are not terminal surfaces.

## Launch safety

Represent launch intent as an executable, argument array, environment map and working directory. Resolve executable paths before launch and record them. Never build a shell command by interpolating a project name, user prompt or remote directory.

The inspected Ghostty header exposes a command string rather than a public argument array in its surface configuration. That is an important integration gap, not an excuse to concatenate untrusted data. Use a fixed, correctly encoded helper invocation. Deliver the actual launch envelope through a private channel or protected manifest; the Swift helper validates it, changes directory and performs an exact argv-based exec. The feasibility spike must verify the engine's command parsing and signal behaviour. [S03](research/SOURCES.md#s03)

Start with a private per-user runtime directory, random one-use envelope identity and restrictive permissions. Never put account tokens, SSH keys or prompt text into an executable command string or process title. Reject unsupported path encodings and embedded NULs with a clear error.

## Concurrency and responsiveness

Use Swift's strict concurrency checking. Views and native surface operations that require main-thread access stay on the main actor. Indexing, disk reconciliation, model streaming and transport decoding run off the UI actor under explicit ownership.

Stream decoding is incremental. Partial UTF-8, split lines, unknown event types, oversized messages and backpressure are normal conditions to handle. Coalesce high-frequency UI updates rather than repainting the entire workspace for every token. Terminal rendering must not wait for memory indexing or model responses.

Cancellation has a named effect: cancel request, interrupt agent turn, detach attachment or stop owned process. These are not synonyms. A remote disconnect changes attachment state without declaring the remote job failed.

## Persistence and identity

Use random stable project and session IDs. A working directory is a location, not an identity. Store canonical directory references and macOS bookmarks where useful; resolve moves or stale bookmarks through user-visible recovery. A project with several worktrees has a shared project identity and separate worktree/session scopes.

Use a transactional local registry, but keep the wiki portable. Disk files and database rows do not become atomic together just because each has an atomic write. Use an operation journal and restart reconciliation for file-changing transactions.

Do not restore OS process state from a saved PID alone. PIDs are recyclable. Combine launch/attachment identity with backend-specific liveness checks; after an app crash, represent uncertainty until checked.

## Error model

Distinguish unavailable dependency, authentication required, unsupported capability, transport disconnected, remote session absent, host key failure, stale proposal, storage failure and user cancellation. Expose actionable recovery without silently retrying writes or re-running agent work.

The ordinary shell must remain usable when memory, a model provider or a plugin is unavailable. Capability failures remove only the affected feature, not the entire workspace.

## Observability

Use structured OS logging with categories for terminal lifecycle, session restore, adapters, memory, review and scheduling. Default logs contain IDs, timing and error classes, not terminal contents, credentials or full prompts. Exported diagnostic bundles require a preview and explicit inclusion of sensitive details.

See [docs/SECURITY-AND-PRIVACY.md](docs/SECURITY-AND-PRIVACY.md), [contracts/PROTOCOLS.md](contracts/PROTOCOLS.md) and [docs/VERIFICATION.md](docs/VERIFICATION.md) for enforcement and proof requirements.
