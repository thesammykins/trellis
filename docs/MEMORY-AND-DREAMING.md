# Shared memory and dreaming

## Knowledge, not invisible model training

The proposed memory system changes what agents can retrieve and which reviewed instructions they receive. It does not train model weights, guarantee better reasoning or prove that an agent has learned from every interaction.

The LLM Wiki idea is a pattern for using an LLM to maintain a linked knowledge base from source material. Trellis adopts the portable-source and curated-wiki idea, then adds project isolation, approval, provenance and transactional updates. It is inspiration, not a dependency or a complete security design. [S27](../research/SOURCES.md#s27)

## Canonical storage

Default location:

```text
~/Library/Application Support/Trellis/
  registry.sqlite
  Projects/<project-id>/
    Memory/
      wiki/                 Canonical approved Markdown
      sources/              User-approved retained source evidence
      observations/         Unapproved candidates, private by default
      proposals/            Structured changes and evidence
      journal/              Apply/rollback transaction records
    snapshots/              Bounded run inputs and manifests
  PersonalMemory/           Explicitly shared personal knowledge only
```

The user may instead choose a repository-local memory root. Exactly one root is canonical for a scope. Exporting or creating a snapshot does not create a second independently writable truth. A later location change is a migration with validation and rollback, not an implicit merge.

Keep private observations and transcripts out of Git by default. Sharing a wiki with a team is an explicit export/location choice and must distinguish shared project facts from personal learning preferences.

## Markdown format

Each approved page is normal Markdown with a small YAML front matter block. Required fields: schema version, stable page ID, title, project scope, kind, review status, revision, provenance references and last review time. Optional fields include verification due date, superseded page ID and tags.

Use a real YAML parser with constrained decoding rather than hand-parsing arbitrary YAML. Do not execute YAML tags or treat a source URL as an instruction. Markdown parsing and YAML decoding are separate steps. A content hash is calculated by the host and stored in its manifest; it is not a self-referential hash field inside the page.

Page kinds are decision, constraint, how-to, reference, lesson and preference. A model-generated claim starts as an observation or proposal. “User preference” requires something the user actually said or approved, not a model's inference from silence.

## Retrieval

Start with SQLite full-text search and deterministic filters. Filter by authorised scope and approval state before ranking. Rank exact task terms, referenced files, recent verified decisions and explicitly linked pages. Return bounded excerpts or pages with provenance and version information.

Use a configurable context budget, initially small enough to keep the terminal task prominent. Do not inject the entire wiki into every turn. A candidate budget such as 2,000–4,000 tokens is a design starting point, not a measured optimal value; the adapter must account for the selected model's actual limits.

Track retrieval receipts and user feedback. Add embeddings only after real queries demonstrate a retrieval gap. A vector database is not required to begin, and inferred semantic similarity does not override project isolation or a contradictory approved decision.

The search index and backlinks are rebuildable. Registry identities, review decisions and the apply journal are durable application state. Do not casually delete the whole database under the claim that “SQLite is only a cache.”

## Ingestion and sources

Ingest only material the user has authorised: a selected output, an explicit note, an agent-proposed observation, a reviewed diff or a saved research source. Raw keystrokes, arbitrary clipboard contents, `.env` files and whole-home-directory indexing are not default inputs.

Retain enough provenance to audit a claim: source identity, capture time, content hash, relevant excerpt and any explicit scope. Redaction is a defensive layer, not a guarantee that all secrets will be detected. Prefer not capturing sensitive material at all.

Links can expire. Keep a permitted excerpt and a source hash where useful, while respecting licence/retention constraints. Do not bundle full third-party articles as the default evidence mechanism.

## Contradictions and staleness

Do not silently overwrite an older approved decision because a newer model statement sounds more confident. A proposal can supersede a page, but must show conflicting evidence, what changed and whether the user made the new decision.

Separate stable decisions from time-sensitive reference facts. Label facts due for review. A source's retrieval date is not the same as the date its claim became true. An agent completion message is not independent proof that a change works.

## Proposal workflow

```text
observation → candidate proposal → validated proposal → user review
                                                   ↘ rejected/deferred
user approval → base-hash check → journalled apply → applied
                                  ↘ failure → recover/reconcile
```

Every proposal contains target path, base hash or create-if-absent condition, proposed content, rationale, source IDs, authoring run and model route. Treat the generated object as untrusted data. The host validates size, path allowlist, scope, schema, source references and prohibited targets before it reaches the review UI.

Application is not `writeFile` followed by “Done.” Acquire the scope's writer lock, re-read the current base, stage content, create a recoverable operation record and then replace files. For several files, record progress and reconcile after interruption. Never claim a set of filesystem renames and a database commit is one atomic transaction without an explicit recovery design.

Rollback is conditional. If the user has since edited an applied file, offer a reverse proposal against current content rather than restoring an old backup over new work.

## AGENTS.md and skills

Keep root instructions short: project intent, boundaries and where to find focused guidance. The wiki is not dumped into `AGENTS.md`. A small managed block can point to a memory skill or explicit retrieval action after user review.

The default target is the current project's root `AGENTS.md`, with exact filename casing. Global instructions are a separate setting and approval scope. Existing nested instruction files and precedence rules remain intact.

Skills are proposed as portable Markdown and supporting resources. A generated skill can influence future execution, so treat edits to skills as instruction changes. Validate trigger scope, assumptions, dependencies and any bundled executable code. Never install a generated script merely because it was placed next to a skill.

## Dreaming pipeline

1. **Eligibility:** app running, selected local-time window, eligible project, permitted model, acceptable power/thermal state and no conflicting writer.
2. **Snapshot:** choose the daily input interval, freeze approved/candidate inputs into a bounded manifest and hash it.
3. **Consolidation:** identify repeated observations, possible decisions, contradictions, stale references and useful lessons. Produce proposals only.
4. **Optional research:** a separate explicitly authorised step fetches selected sources within a budget. It cannot expand to unrelated projects or install tools.
5. **Validation:** host validates schema, scope, provenance and target conditions. Unsupported claims remain questions rather than facts.
6. **Report:** record proposals, skipped inputs, cost information, failures and run identity. Await review.

An empty proposal set is valid. Repetition alone is not evidence that a behaviour is correct or a user preference is permanent.

## Scheduling and budgets

Use a durable job record and a host-level scheduler; a low-priority maintenance API may assist with opportunistic execution. Apple's background activity scheduling is discretionary, not an exact alarm. [S33](../research/SOURCES.md#s33)

Default to no waking the machine, no keeping it awake and no background daemon after app exit. On sleep or app close, checkpoint/cancel safely. On reopening, show missed work and apply a user-configured catch-up policy. Deduplicate by project, input snapshot and job type, not just a wall-clock date that can repeat during daylight-saving changes.

Allow one consolidation run at a time initially. Store the timezone with the schedule and use calendar-aware date calculation. Configure maximum requests, input bytes/tokens and elapsed work. Where provider spend cannot be strictly capped locally, distinguish an estimated budget from a provider-enforced limit and stop before the next request when exhausted.

## Model permission boundary

The safest initial dreaming route is a native model request with **no tools** and only the selected snapshot in its input. The model returns a proposal object; Swift validates and stages it. It never receives a function capable of applying the proposal.

A subscription-backed coding harness is eligible only after its actual permissions have been demonstrated to prevent unwanted file access and tool execution. Merely setting the working directory or writing a “read-only” instruction is not sufficient. Until that gate passes, leave that route unavailable for unattended dreaming while still supporting it for interactive agent sessions.

An ordinary unsandboxed CLI runs as the user and can often access the user's files. Local IPC tokens and a proposal-only API constrain cooperative integrations, not a malicious same-user process. Stronger isolation requires OS-enforced restrictions and an independently verified execution design. Do not describe this app as an agent sandbox.

## Forgetting and export

Support export of selected approved pages with provenance, deletion of observations and snapshots, and explicit removal from future retrieval. Rebuild the index after deletion. Explain that upstream agent histories, already-sent provider requests and external backups may retain information outside Trellis's control.

See [../prompts/DREAMING.md](../prompts/DREAMING.md) and [../contracts/proposal.schema.json](../contracts/proposal.schema.json) for the proposed output contract.
