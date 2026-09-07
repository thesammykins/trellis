# Proposed application contracts

These names are **Trellis design contracts**, not claims of existing upstream APIs. The implementing agent should turn them into small Swift types after inspecting actual agent and Ghostty interfaces.

## Domain identity

Use stable opaque IDs for project, worktree, session, attachment, page, proposal and run. Paths and titles are mutable attributes. Bind every event/request to an authorised scope and originating session; a caller's supplied display name is not authorisation.

## Agent adapter responsibilities

An adapter can probe an installation, report capabilities, produce a launch plan, attach to an owned supported session, map events, request interruption and resolve an explicit history resume target. Capabilities are separate flags for terminal launch, live events, context insertion, memory tools, approval events, history resume and headless jobs.

An unavailable capability is not an error for ordinary terminal use. Unknown approval semantics fail closed. All actual wire/protocol types stay inside the adapter.

## Memory operations

| Proposed tool | Input | Result | Authority |
| --- | --- | --- | --- |
| trellis_memory_search | Query, bounded limit, optional kind filter | Approved page IDs/excerpts and hashes | Session-bound scope only |
| trellis_memory_read | Page ID and optional expected revision | Content and provenance | Approved readable page |
| trellis_memory_propose | Candidate change, source references, expected base | Staged proposal ID or validation error | Propose, not apply |
| trellis_memory_observe | User-authorised bounded observation and provenance | Candidate observation ID | Private candidate store |

Do not expose `memory_apply`, arbitrary filesystem reads or a “change scope” tool to the agent. Applying proposals is a separate user-authorised host service. Do not let a model-generated parameter select a new root directory.

## Event envelope

Fields: schemaVersion, eventID, sessionID, projectID, origin, kind, observedAt and payload. The host deduplicates by eventID and preserves the origin. An event claiming user approval is not itself an approval credential. Context receipts include exact page hashes and delivery method.

The event schema included here establishes the envelope only. Implement kind-specific payload validation and trust handling in the adapter. Unknown new event kinds can be safely ignored/logged; unknown write or approval semantics cannot be accepted by default.

## Proposal contract

See [proposal.schema.json](proposal.schema.json). Each proposed change uses a relative path, target kind, operation, complete proposed text, source IDs and a base condition. `create` means absent; `replace` means the current content hash must match. Initial model proposals cannot delete files.

Schema validity is necessary but insufficient. The host also checks current scope, target allowlist, path resolution, symlink conditions, source existence, current base, permissions, size and instruction-change review requirements.

## Storage transaction contract

One authorised applier per scope. Recheck all base conditions, stage files, record the operation, apply recoverable changes and reconcile registry/index state. On restart, identify incomplete operations and finish or reverse them safely. Rollback against subsequently edited content becomes another proposal.

## Transport contract

Prefer stdio for an owned process and a private authenticated local bridge for separately running plugins. Line-oriented streams need bounded incremental parsing, request IDs, deadlines and cancellation. Do not assume one read call is one message.

Network exposure requires authentication, loopback/tunnel policy, origin validation where applicable and credential lifecycle. Stdio and Unix sockets do not remove the need to validate the content of a request.
