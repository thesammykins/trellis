# Trellis implementation guidance

Maintain the native macOS agent terminal described in PRODUCT-BRIEF.md. It is a personal app, not a web application or a general IDE.

## Read before changing code

Read `PRODUCT-BRIEF.md`, `ARCHITECTURE.md`, `DESIGN.md` and `docs/STATUS.md`; consult the original milestones in `IMPLEMENTATION-PLAN.md`. Consult focused documents for the area being changed. Verify external APIs against the installed versions; research citations are not a dependency lock.

## Working rules

- The root agent orchestrates and integrates. Delegate bounded tasks with file ownership and acceptance evidence; do not let sub-agents independently redesign shared contracts.
- Preserve the M0 foundation: a real Ghostty-backed shell in a native window. Do not substitute simulated output, a web terminal or a VT-only library without an explicit documented scope decision.
- Use Swift/SwiftUI for the app and shared services, with a narrow AppKit/C bridge. Small agent-native plugin shims may use their required language.
- Keep terminal lifecycle, agent protocol, memory and UI responsibilities separate. Do not recreate sessions because a view is recomputed.
- Use exact requested scope. No unsolicited rewrites, unrelated abstractions or large dependency additions.
- Do not modify user credentials, global agent rules, SSH configuration, real projects or remote machines without explicit authorisation. Use fixture projects for development evidence.
- Memory and skill changes are proposals before approval. A prompt is not a security boundary.
- Use targeted validation for real risks. No blanket coverage target or test-first programme; do not omit checks that prevent data loss, scope leaks or duplicate execution.
- Preserve normal terminal operation when optional agent features fail. Report unknown state as unknown.

## Completion contract

State what changed, which behaviour was actually exercised, exact relevant commands, evidence paths, blockers and the next bounded task. Update docs/STATUS.md for product changes; keep machine-specific handoffs and evidence in ignored local files. Do not claim a Mac build, successful login, live remote recovery or Siri behaviour without having observed it.

See `docs/ORCHESTRATION.md` for ownership and integration workflow. Local orchestration state and dogfood records are intentionally excluded from Git.
