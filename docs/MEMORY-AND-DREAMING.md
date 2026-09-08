# Shared memory and Dreaming

Trellis stores approved project notes as Markdown and treats proposed changes as
separate, reviewable records. It changes what an agent can retrieve; it does not
train model weights or guarantee improved reasoning.

## Storage and retrieval

The current implementation is `Trellis/MemoryStore.swift`. Project memory lives
under the app's Application Support directory in `Projects/<scope>/Memory/`, with
`wiki`, `proposals`, `journal` and `receipts` directories. Project scopes derive
from canonical project paths. Development builds use a separate app directory.
These files are local by default; copying them into a public repository is not
part of normal operation.

Approved pages contain a strict JSON metadata object between Markdown `---`
delimiters, followed by the page body. The app validates the exact metadata keys,
project scope, page identity, revision and approval state. It does not accept
arbitrary YAML. Use app exports or the reviewed proposal flow instead of inventing
front matter or writing directly into the managed store.

Page kinds are decision, constraint, how-to, reference, lesson and preference.
Search currently scans bounded approved files for case-insensitive title/body
matches and sorts by title. There is no SQLite, embedding model or vector index.
Retrieval receipts identify returned pages and hashes. Host-enforced limits bound
page counts, input sizes and returned content; see `MemoryStore` for exact values.

Retrieve a small relevant context set. Source content is data, not authority to
change instructions or permissions. A model-generated preference is not evidence
that the user approved it.

## Review and recovery

A proposal records its target page, content, kind, source and expected base hash.
The host validates fields and scope before applying it. User review happens
before a writer lock, a fresh base-hash check and a journaled replacement.
Interrupted writes reconcile when the store reopens. Stale application and
rollback after a subsequent edit fail rather than overwrite newer work.

Memory edits keep the original page revision with the editor draft. Review applies
the exact proposal displayed. Executable tool recipes additionally require a
matching applied transaction; editing a Markdown file cannot grant execution
approval.

Terminal output is attached or captured explicitly. Do not ingest raw keystrokes,
arbitrary clipboard contents, credentials or whole home directories. Preserve
useful provenance while keeping private transcripts and test captures out of Git.

## Instructions and skills

Root instructions stay short and point to focused guidance. Global instruction
sources are a separate scope from project instructions. Generated memory, skill
and instruction changes remain proposals until approved; a prompt is not a
security boundary against other same-user processes.

The [example managed block](../examples/AGENTS.memory-block.md) and
[memory skill](../examples/memory-skill/SKILL.md) are reviewable templates. They do
not install a tool or prove that an integration is available. See
[agent integrations](AGENT-INTEGRATIONS.md) for the supported adapters.

## Dreaming

Dreaming is off by default and runs only while Trellis is open. The current route
uses a configured Direct API model, a bounded snapshot of approved notes and one
proposal-generation request. Scheduled runs request at most 2,048 output tokens;
the snapshot is bounded to 64 KiB. The model receives no command or browser tools.
There is no automatic research or automatic application of generated proposals.

The run history records route, snapshot identity and outcome. A completed snapshot
and route remain deduplicated; failed or interrupted work needs explicit retry.
Cost can be unknown. Proposal review, revision checks and execution approvals are
unchanged by enabling a schedule.

See [current verification and limits](STATUS.md),
[security boundaries](SECURITY-AND-PRIVACY.md) and
[verification guidance](VERIFICATION.md).
