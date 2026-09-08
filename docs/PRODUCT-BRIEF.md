# Product brief

## One concept

**A project-centred terminal that remembers what matters and helps its user become more capable.**

Trellis is not an IDE with a terminal added at the bottom. Its primary working surface is a terminal. Codex, OpenCode, Pi and an ordinary shell are first-class sessions within a project. The application contributes continuity, navigation, trustworthy context, review and optional teaching around the agent's own interface.

The organising loop is:

**Open a project → work in a real session → capture useful observations → review what becomes memory → bring the right memory into the next session.**

Dreaming is a maintenance stage of this same loop. Learning mode explains the work happening in it. Neither is a separate product bolted onto the terminal.

## User and starting assumptions

The initial target is a personal developer workflow. Build for Apple Silicon and macOS 27 using the appropriate Xcode 27 toolchain. Intel support, earlier operating systems, team administration and App Store distribution are not initial requirements.

macOS 27 is a real documented target. Apple's current developer page points to Xcode 27 and macOS 27 beta resources. Record the actual installed OS, SDK and Xcode build before coding rather than assuming final-release availability. [S06](../research/SOURCES.md#s06)

The native requirement means no Electron, Tauri, browser-based application shell or WebView terminal. It does not mean replacing the requested Ghostty engine with Swift, or rewriting the supported external agents. Small upstream-required plugin bridges may use TypeScript inside OpenCode or Pi; the app, shared memory engine and host-side services remain Swift.

## Core jobs

### Start and resume work

Select a project and open Codex, OpenCode, Pi or a shell in its working directory. Reopen the same project later and see the session identities, whether their processes are still alive, and which recovery actions are actually possible.

A tab represents a **session**, not an agent installation. Multiple Codex tabs are valid. Each has its own session ID, title, working directory, agent history identifier and optional worktree.

### Carry useful knowledge between agents

Preserve decisions, constraints, explanations, references and lessons in readable Markdown. Supply a bounded selection relevant to the current project and task. Show what was supplied, by which mechanism, and whether it was merely available or actually inserted into context.

The goal is shared project knowledge, not merging incompatible private agent state. An OpenCode conversation does not become a Codex conversation just because they can read the same wiki.

### Learn without losing the terminal

Advanced and Learning modes share projects, sessions, permissions and files. Learning adds a contextual inspector that explains selected output, a proposed command, a diff or an unfamiliar concept. It does not replace real tools with a toy interface or make permanent claims about the user's competence.

### Maintain memory deliberately

When explicitly enabled, the app can consolidate approved daily inputs during a configurable overnight window while the Mac is awake and the app is running. The user chooses an eligible model, scope, cost allowance and whether research is permitted. The next morning shows evidence-backed proposals rather than a claim that the app has trained itself.

### Work remotely

Use existing OpenSSH configuration and optionally the 1Password SSH agent. Persistent terminal processes live on the remote machine under tmux. The app remembers their identities and reattaches after a connection loss. Remote server reboot and agent-history resume are separate cases, not guaranteed process survival.

## Product boundaries

| Included in the planned product | Not an initial commitment |
| --- | --- |
| Native multiwindow shell and agent sessions | General-purpose IDE, compiler frontend or file editor replacement |
| Project launcher and explicit session restoration | Automatic migration of every third-party terminal preference |
| Cross-agent Markdown memory and review | Invisible self-modification or autonomous trust escalation |
| Configurable nightly proposal generation | Guaranteed execution while the Mac is asleep or the app is closed |
| Contextual learning and shell suggestions | Keystroke surveillance or automatically executed model suggestions |
| SSH/tmux reattachment and 1Password compatibility | Reimplementing SSH cryptography or storing private keys in the app |
| Supported Codex subscription sign-in | Turning a ChatGPT subscription into unrestricted API credits |
| OpenCode Go/Zen access through supported paths | A frozen, hard-coded provider/model catalogue |
| Useful, limited App Intents | Siri executing arbitrary shell commands without review |
| Development by a root agent and sub-agents | A new autonomous multi-agent runtime required to open a terminal |

## Priority order

**Foundation:** a good terminal, predictable session ownership, correct paths, native focus and reliable reopening.

**Daily usefulness:** agent launch profiles, shared memory, explicit context status, session history and review.

**Continuity and guidance:** remote persistence, contextual explanations, safe suggestions and supported model authentication.

**Adaptation:** dreaming, learning preferences, limited system integration and polish.

The first runnable deliverable must contain a real shell. A polished mock dashboard with fake terminal output does not satisfy the foundation.

## Success criteria

Success is observable behaviour, not a feature count. The app should launch the requested agent in the correct project without shell-quoting surprises, keep terminal input responsive while indexing, preserve a remote session identity across reconnection, and let the user inspect and undo every applied memory change.

For learning, success means a user can explain a change and its verification after completing it. For memory, success means a later agent can retrieve a relevant approved decision with provenance. Claims of improved productivity or capability require real usage evidence.
