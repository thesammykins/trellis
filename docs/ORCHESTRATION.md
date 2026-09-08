# Root-agent orchestration

## Separate development orchestration from product runtime

The user requested a root agent coordinating sub-agents to build the app. That does not require Trellis itself to place a root LLM between every user input and terminal session. Build-time orchestration is the default scope; the product's session coordinator is ordinary Swift code.

## Root responsibilities

Own the requirement interpretation, shared contracts, project/package changes, dependency pins, security boundaries, integration and final evidence. Keep the task graph small and dependency-aware. Reconcile conflicting sub-agent findings explicitly rather than accepting the most confident claim.

The root is responsible for the actual application working. A sub-agent's “done” message is evidence to inspect, not proof of integration.

## Bounded delegation

Each work packet identifies a task ID, outcome, prerequisites, allowed files, interfaces, acceptance behaviours, evidence format and actions requiring approval. Prefer independent worktrees or nonoverlapping file ownership. A worktree isolates edits, not permissions or credentials.

Initial roles: terminal embedding, native workspace, session/remote runtime, agent adapters, memory/review and native UX validation. Add a focused security reviewer for memory apply and unattended execution. One person/agent may cover several roles sequentially.

Do not run all roles from day one. M0 needs a small team because the engine contract is the dependency for most other work.

## File ownership

The root owns Xcode project metadata, Package.swift, dependency locks and shared domain contracts. A sub-agent can propose edits to these but should not concurrently rewrite them. Assign narrow directories for adapters and features after the shared interfaces exist.

Before integrating, inspect the diff, dependency changes and any generated or downloaded artifacts. Do not accept bundled binaries without provenance or a giant architectural rewrite in a task meant to add one view.

## Task ledger

Create a simple Markdown ledger with task ID, milestone, owner, status, blockers and evidence location. States: planned, active, blocked, ready for integration, accepted. Do not equate a committed branch with accepted behaviour.

A rejected or blocked task leaves a useful note: what was attempted, what evidence failed, and what should be tried next. Avoid parallel agents repeating the same failed hypothesis because no decision was recorded.

## Integration rhythm

Freeze a small contract, delegate independent slices, inspect returned changes, integrate one at a time and run the relevant acceptance checks. Prefer small mergeable increments over a week of disconnected scaffolds. Keep each milestone's real app runnable once it has reached that state.

Use a fixture project and test account/host where possible. Agents are not authorised to modify the user's actual SSH configuration, global AGENTS.md, credentials or remote hosts merely because a development task mentions those features.

## Handoff content

Every final implementation response includes the changed behaviour, evidence actually observed, build/tool versions when relevant, skipped checks, unresolved decisions and the next task. Put the continuation prompt in a file, not just a chat message. Do not make the next agent recover intent from an unstructured transcript.

See [../prompts/SUBAGENT.md](../prompts/SUBAGENT.md) for the reusable delegation template.
