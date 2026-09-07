# Agent integrations

## Two capability levels, no pretending

Every installed supported CLI should work as a terminal process. Rich integration is a separate capability established by a versioned adapter and handshake. Failure of a plugin must not prevent basic CLI use.

The shared memory engine is Swift. An agent-specific plugin is a small compatibility layer that translates the agent's hooks/tools to the same read/propose interface. Do not build three independent knowledge stores.

## Capability matrix

| Agent | Terminal session | Rich path | Memory package | Important boundary |
| --- | --- | --- | --- | --- |
| Codex | Real CLI in Ghostty | Documented local app-server for tasks it actually owns; plugin events for independent TUI sessions | Supported plugin containing skills/MCP and verified lifecycle hooks | A second server does not automatically observe the first CLI |
| OpenCode | Real TUI; optionally attached to managed backend | Documented HTTP API/events and explicit TUI attach | OpenCode plugin using supported events/tools | Server ownership, auth and exact session ID must be explicit |
| Pi | Real interactive TUI | TUI extension; RPC for a separately owned headless session | Thin TypeScript extension calling Swift bridge | RPC is another mode, not a wiretap on a running TUI |
| Shell | Real configured shell | Shell integration for limited prompt/editor state | Explicit memory CLI action, not hidden injection | Shell input state cannot be guessed safely |

OpenAI documents plugin bundles with skills, MCP servers and lifecycle hooks. OpenCode documents plugins, a server API and terminal attachment. Pi documents interactive and RPC modes and extensibility. Verify exact event names and installation formats against the selected versions rather than treating this table as an executable API specification. [S13](../research/SOURCES.md#s13)[S14](../research/SOURCES.md#s14)[S15](../research/SOURCES.md#s15)[S16](../research/SOURCES.md#s16)[S19](../research/SOURCES.md#s19)[S20](../research/SOURCES.md#s20)[S21](../research/SOURCES.md#s21)

## Shared lifecycle

At installation, ask the user to enable a project or user-scoped integration. Show the exact configuration changes and back up edited configuration. Preserve unrelated plugins. Upgrades compare the installed version and managed content hash; do not overwrite user modifications silently.

At launch, the host creates session-scoped connection metadata. The adapter handshakes with project ID, session ID, version and declared capabilities. The memory service authorises the actual requested scope. A plugin cannot expand scope by sending a different project name.

At request time, retrieval returns a bounded set of approved pages and provenance. Recording an observation creates a candidate; it does not approve the claim. At session end or checkpoint, the adapter can submit a structured summary proposal if supported and authorised.

On timeout or disconnect, the plugin fails gracefully. Do not block the user's terminal indefinitely because the memory service is unavailable. Announce that memory is unavailable and allow normal agent work to continue.

## Codex approach

Use the supported plugin package format rather than a fabricated extension API. Resolve the applicable hooks from the installed release, then demonstrate that each fires in the TUI before using it to drive native status. If automatic recall cannot be confirmed, provide a clear explicit recall action and label memory as available rather than supplied. [S13](../research/SOURCES.md#s13)

For native account handling or a separately owned assistant job, use app-server over its documented local transport, preferably stdio for the initial adapter. Initialise it, correlate request IDs and preserve its thread identity. Generate protocol schemas from the installed binary when supported. Keep raw transport types inside the adapter. [S11](../research/SOURCES.md#s11)

Codex remains the credential and harness owner. Do not scrape conversation SQLite/files while another process writes them. Do not reuse internal implementation databases as a stable public API. A stored history ID can support an explicit resume action after the original process exits.

## OpenCode approach

Where the selected version permits it, the app owns one authenticated loopback backend per chosen isolation boundary, and the terminal attaches to that backend. This gives the native app a documented relationship between visible TUI and structured events. Bind only to loopback by default; allocate a free port and a per-instance credential. [S15](../research/SOURCES.md#s15)[S16](../research/SOURCES.md#s16)

The OpenCode plugin translates supported events to Trellis's event envelope. Record supplied context and candidate observations through the Swift bridge. Avoid experimental hooks for essential correctness unless pinned, demonstrated and treated as a compatibility risk.

Do not expose a backend on all interfaces for convenience. Remote use requires an authenticated tunnel and explicit server configuration. Reconnecting an event stream must not send the last prompt again.

## Pi approach

Use an extension to add memory access in Pi's interactive mode. Keep the extension small and native to Pi's documented extension system. Locate the current upstream documentation through the installed package/repository; some older `badlogic/pi-mono` references now lead to a different repository location. Pin the actual source used by the installation instead of guessing a package name. [S19](../research/SOURCES.md#s19)[S20](../research/SOURCES.md#s20)

For a separate assistant job, RPC provides line-delimited JSON commands and events. Support request correlation, cancellation and extension UI requests. Do not mix the RPC stream into a terminal or start an interactive mode and pretend its text is RPC. [S21](../research/SOURCES.md#s21)

Do not assume Pi has built-in MCP support merely because the other agents do. Its native extension can call the Swift bridge directly, or use an explicitly selected compatibility package after review.

## Context receipts

Represent context states precisely:

| State | Meaning |
| --- | --- |
| Indexed | Page is searchable locally |
| Available | Agent has a way to request it |
| Returned | Memory service returned it to the adapter/tool |
| Inserted | A verified hook/API inserted it into agent context |
| Referenced | A later agent response explicitly cited it |

None of these proves the model understood or followed the page. The UI should not claim “used” merely because a file exists on disk. Receipts include page ID, revision/hash, transport path, session and timestamp.

## Compatibility strategy

Pin an initially supported version of each agent and record probes in a local compatibility report. Unknown versions may retain terminal-only support. Rich capabilities remain disabled until a handshake or explicit compatibility rule validates them.

Unknown event fields are preserved or ignored safely; unknown security/approval semantics fail closed. Keep provider-native payloads behind the adapter, expose typed domain events and never construct a universal lowest-common-denominator agent that hides important distinctions.
