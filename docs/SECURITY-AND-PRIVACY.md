# Security and privacy design

## Honest trust model

Trellis is a terminal application. Its ordinary user-launched processes can have the same filesystem and network access as the user. It is **not** automatically a sandbox for those agents. A memory policy, local socket token, worktree or working directory does not create OS-enforced isolation.

The app can strictly control its own memory API, proposal applier, native assistant requests and App Intents. It cannot promise that a separately running unsandboxed same-user process cannot read or modify the user's files by another route.

Unattended tasks require a stronger, demonstrated restriction boundary. Prefer no-tools model calls on selected snapshots initially. Do not rely on the model's obedience as a write barrier.

## Assets to protect

Credentials and SSH keys; private project contents; personal learning preferences; approved agent instructions; source provenance; remote session identities; user edits and working trees; money or subscription limits consumed by model calls.

## Boundaries and controls

| Threat | Required control |
| --- | --- |
| Terminal/source text asks the app to run a command | Treat content as data; only typed authorised actions can execute |
| Model proposal targets an arbitrary path | Relative allowlisted targets, scope resolution and host-side validation |
| Path traversal or symlink swaps during apply | Resolve beneath approved root, use safe file operations, reject symlink targets and revalidate at write time |
| New content overwrites a user's newer edit | Base hash check, writer coordination and stale-proposal rejection |
| Multiple files partially update | Durable operation journal and restart reconciliation |
| Plugin asks for another project's memory | Server-side scope binding, not caller-supplied project-name trust |
| Browser/local process calls a bridge | Prefer private Unix sockets/stdio; authenticate any network endpoint and protect against origin/DNS-rebinding issues |
| Secret appears in evidence | Minimise capture, exclude high-risk sources, redact defensively and preview exports |
| Remote SSH key changes | Preserve OpenSSH validation and block until user resolves identity |
| Reconnect repeats an agent action | Attach-only restore, stable IDs and no prompt replay |
| A night job escalates permissions | No self-authorising tools; separate run policy and mandatory instruction review |
| Siri or URL opens a hidden write path | Shared policy checks and visible confirmation |

## IPC design

Prefer a per-user runtime directory with restrictive permissions, a private local socket and a session-scoped handshake. Validate the peer where supported and bind credentials to exact allowed operations and scope. Never make the localhost listener a global unauthenticated memory API.

Tokens prevent accidental cross-session access and some local web attacks, not all same-user attacks. Do not store general account credentials in plugin configuration or put bridge tokens in public project files. Runtime credentials expire with their associated session/run and can be revoked.

## Prompt injection and memory poisoning

Sources, tool outputs, terminal text, research pages and observations are untrusted. They may contain instructions that try to overwrite rules, approve themselves, claim nonexistent evidence or request secrets. The consolidation prompt can describe these risks, but deterministic validation and absence of privileged tools are the actual controls.

Require provenance for proposed knowledge. Do not promote an assertion because the same model repeats it. Changes to instructions, skills, global preferences and executable resources have a higher review tier than ordinary explanatory notes.

## Process and network control

Use exact executable/argv boundaries where available. Audit remaining shell-serialisation boundaries, especially Ghostty's command string and SSH remote commands. Use timeout/cancellation and process identity checks. Do not terminate unrelated processes by name.

New remote hosts, installations, destructive commands, public server bindings and key forwarding require explicit user intent. A repository's README, AGENTS.md or a plugin's output cannot authorise those actions on the user's behalf.

## Privacy defaults

No cloud account required for a normal terminal. No automatic transcript upload, clipboard capture, analytics upload or cross-project personal memory sharing. Model requests disclose route and authorised context. Notifications and diagnostics omit sensitive content by default.

Provide retention settings for observations, snapshots and reports. A forget action must explain the limits of deleting material already retained by upstream agents/providers. Do not promise complete erasure of data outside the app's control.

## Distribution

Initial development is a personal local build. Plan for Developer ID signing, hardened runtime and notarisation when distributing outside the Mac App Store. Do not assume the App Sandbox will support every desired terminal workflow, and do not claim notarisation supplies process isolation.

Audit third-party licences, bundled helper binaries and artifact provenance before release. Avoid automatic dependency or plugin updates during a running agent session. Keep a reviewed upgrade path and a way to roll back the terminal engine/adapter bundle.
