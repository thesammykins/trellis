# Implementation plan

## Delivery rule

Build dependency-ordered vertical slices. Every milestone ends with a working behaviour, a small amount of evidence and a hand-off. Do not implement all UI screens before proving the real terminal. Do not build an orchestration framework merely to coordinate this project.

The root coding agent owns integration and architectural decisions. Sub-agents receive bounded file ownership and acceptance criteria. The root remains responsible for checking their results in the compiled app.

## M0 · Prove the platform and engine

**Outcome:** one native window containing a real interactive Ghostty-backed shell.

Record macOS, Xcode, SDK, Swift and Zig versions; select and pin a compatible Ghostty revision. Confirm the full macOS embedding path, its licence, build inputs, resources and C header. Build the artifact on the actual Mac and document the reproducible command.

Implement the smallest app and AppKit bridge. Prove shell input/output, resize, display scale, selection/copy/paste, command interruption, focus, native text composition and surface teardown. Validate the fixed launcher helper with a directory and argument containing spaces and quotes. Record exactly which object owns the PTY.

Create `script/build_and_run.sh` and `.codex/environments/environment.toml` using the available macOS build skill's current canonical action format. The Run action must launch the actual `.app`, not a raw SwiftPM executable. Use a dedicated development profile so rebuilds cannot kill unrelated work.

**Gate:** real shell works after repeated open/close and resize. The app can be rebuilt from a clean checkout. A screenshot and commands support the claim. If the selected full engine cannot be embedded, report the exact blocker and preserve the spike. Do not silently switch to xterm.js, a web terminal, a VT-only package or a fake text view.

**Owners:** root plus terminal specialist. Keep parallelism low until the C boundary is proven.

## M1 · Project and session foundation

**Outcome:** projects can open and manage multiple shell/agent terminal sessions.

Add native project selection, stable session IDs, tab ordering, close behaviour and working-directory launch profiles. Support more than one session of the same agent. Persist project references, window state and session metadata. Reopening restores the workspace and accurately labels processes that cannot survive local app exit.

Add installed-agent discovery without automatic installation. Launch Codex, OpenCode and Pi as ordinary CLI processes before introducing rich integration. Include a normal shell path and meaningful missing-executable errors.

**Gate:** selected project and argv survive spaces, quotes and Unicode. Closing one tab does not stop another. View recomposition does not duplicate processes. Local session restoration never claims to resurrect a dead process. Build and focus smoke checks pass.

**Owners:** workspace specialist and runtime specialist, with root ownership of shared domain types.

## M2 · Agent-aware integrations and accounts

**Outcome:** each agent has an explicit, version-checked capability set and a working memory connection path.

Implement a Codex integration using supported plugin/MCP interfaces for TUI sessions, plus a separately owned app-server route where required for native tasks and supported sign-in. Implement OpenCode with its documented server/attach path where it improves shared event visibility. Implement a Pi extension for its TUI and a separate RPC adapter only for separately owned jobs.

Do not assume a headless process observes an independent TUI. Add capability/version diagnostics and an integration handshake. Verify account flows, event identity, interruption and session history mappings with each installed binary.

Add ChatGPT sign-in through Codex's supported authentication owner. Add OpenCode Go and Zen in the OpenCode connection flow. Do not duplicate or scrape credential stores.

**Gate:** one supported version of each agent can use the shared memory read/propose path, or its exact missing capability is visible. An event is associated with the right project/session. Disabling a plugin leaves the terminal operational. Unsupported hooks do not produce fake activity badges.

**Owners:** one agent-integration specialist per adapter only after the root freezes the shared contracts.

## M3 · Shared Markdown memory and review

**Outcome:** one agent can propose a useful project note and another can retrieve the approved note.

Build the canonical Markdown repository, page metadata, explicit project/personal scope, local search index and provenance. Add proposal generation and a review UI with base hashes, diffs and apply/rollback records. Reconcile external edits and rebuild the index from files.

Install a small, reviewed memory instruction block and portable skill in a fixture project. Do not automatically write global instructions. Add bounded retrieval and a context-delivery receipt that distinguishes availability from insertion.

**Gate:** Codex-to-OpenCode or Pi-to-Codex round trip works against the same approved page. A stale proposal cannot overwrite a newer file. An interrupted multi-file apply is recoverable. Index deletion does not delete knowledge. Search cannot cross project scope without authorisation.

**Owners:** memory specialist, review UI specialist and root for integration.

## M4 · Remote persistence and SSH

**Outcome:** a remote agent continues under tmux while the local transport disconnects, then reconnects to the same remote identity.

Use system OpenSSH and existing host aliases. Add explicit remote setup/preflight, tmux detection, user-scoped session identities and attach-only restoration. Verify one target Linux host first. Add 1Password SSH-agent compatibility through OpenSSH configuration, keeping private keys out of the app.

Remote memory is separate work: transfer only an approved snapshot over SSH and retrieve proposals through a reviewed path, or install an explicitly authorised remote bridge. A disconnected laptop does not provide a live local memory service to a remote process.

**Gate:** disconnect/reconnect preserves remote workload identity and does not start a duplicate agent. Missing tmux session offers explicit recovery. A host-key mismatch blocks. A second client is not unexpectedly detached. Private keys and tokens are absent from logs and launch arguments.

**Owners:** remote/runtime specialist and root. Can start after M1 but must integrate with M2 identity contracts.

## M5 · Learning and suggestions

**Outcome:** the same workspace supports contextual explanations and safe shell-only suggestions.

Add Advanced/Learning presentation preferences without changing permissions. Explain selected terminal output or a proposed command using an explicitly selected account/model and reviewed context. Add deterministic history/path suggestions first, then optional model-assisted suggestions.

Implement shell integration for a named supported shell, initially zsh. Do not claim universal inline suggestions. Unknown input state, raw mode, alternate-screen applications and password entry disable injection. Accept inserts; Return executes.

**Gate:** entering a full-screen agent/editor never displays a shell suggestion. Learning mode does not replace the session or re-run a command. Cancellation cannot insert a stale result into a newer command line. Cloud transmission is opt-in and limited to the explained selection/context.

**Owners:** learning UI specialist and terminal/runtime specialist.

## M6 · Dreaming and skill proposals

**Outcome:** an opt-in scheduled run produces useful, attributable proposals without autonomous writes to active guidance.

Snapshot approved inputs and eligible observations, exclude secrets and unrelated projects, run a bounded consolidation task and validate its structured output. Separate optional research from consolidation. Implement budgets, cancellation, checkpoints and schedule deduplication across restarts and daylight-saving changes.

Enable only model routes for which tool/file restrictions can actually be enforced. A direct no-tools model call can be the initial route. A subscription-backed harness may be added when its enforced permissions and accessible context have been demonstrated; a prompt saying “read only” is not sufficient.

**Gate:** malicious input cannot authorise a write or new tool. Root guidance and skills are proposals requiring approval. A missed overnight window has an explicit skipped/catch-up policy. The same snapshot does not produce duplicate applied updates after restart.

**Owners:** memory/runtime specialist plus independent security reviewer.

## M7 · App Intents and native polish

**Outcome:** approved project and memory actions are discoverable through supported system integrations, with a coherent macOS experience.

Implement typed entities and bounded actions such as Open Project, Show Memory Page and Open Review. Add a drafting-only prompt action before considering side-effecting automation. Use the installed SDK's supported APIs for entity search and selected-content context. Validate Shortcuts first, then Siri on a supported device/account configuration.

Complete multiwindow focus, accessibility, reduced motion/transparency, light/dark appearance, notifications and performance measurements. Prepare Developer ID signing and notarisation only when distribution is desired. Never disable security settings just to make an unexplained build failure disappear.

**Gate:** intents cannot bypass review or gain access to undisclosed terminal text. VoiceOver and keyboard paths work. UI evidence comes from a real app. Secrets are absent from diagnostics. The first personal release has a documented install/build path and known limitations.

## Suggested task sizing

Each task should deliver one user-visible behaviour or one critical integration boundary. A task brief names allowed files, required interfaces, expected evidence and forbidden side effects. Keep shared Xcode project and package changes under one owner to reduce merge churn.

Do not assign dates or optimistic time estimates before M0 establishes the engine and toolchain. Integration complexity, especially terminal input and restore semantics, is a better planning signal than the number of SwiftUI screens.

## Definition of done for a milestone

The relevant code compiles on the recorded Mac, its acceptance behaviour was exercised, significant failures are recorded accurately, and the next hand-off identifies exactly what is complete, what is not and which commands reproduce the evidence. A green formatter or a static screenshot alone is not sufficient.
