# Sub-agent task template

## Task

Task ID: <root-assigned identifier>
Milestone: <current milestone>
Outcome: <one concrete behaviour or integration boundary>

## Context

Read the root AGENTS.md and these focused documents: <paths>. The parent agent owns shared contracts and integration. Do not expand product scope.

## Ownership

Allowed files/directories: <explicit list>
Shared interfaces to consume: <types/contracts and revision>
Files you may propose but not edit: <project metadata, shared domain, etc.>

## Acceptance

The work is accepted only when <specific observed behaviour>. Provide the exact build/check commands and the smallest useful evidence. State what you could not run.

## Boundaries

Do not modify credentials, global configuration, real user projects, remote hosts or dependencies without the parent's explicit authorisation. Do not substitute fake terminal output for a real integration. Do not assume a same-user process is sandboxed.

## Return format

Summarise changed behaviour, changed files, verified results, limitations, required parent integration and remaining risks. Call out any contract change before implementing it. Leave a concise hand-off note and avoid unrelated formatting/refactors.
