# UX6 component reference index

Generated before implementation on 7 September 2026 with built-in image_gen. Prompts: [PROMPTS.md](PROMPTS.md). Original composition remains [02-trellis-dark-primary.png](../02-trellis-dark-primary.png).

| ID | Image / region | Implementation contract | Status |
| --- | --- | --- | --- |
| S1 | [Session board](01-session-components.png) A | 56pt expanded row, 8pt radius, 16pt source icon; nickname above context; no UUID as primary label | implemented; evidence in UX6 RESULTS |
| S2 | Session board B | 48pt collapsed rail, selected indicator, full accessible label/tooltip | implemented; evidence in UX6 RESULTS |
| S3 | Session board C | Rename, Favourite, Detach, Remove; separate confirmed End Session | implemented; evidence in UX6 RESULTS |
| T1 | [Appearance board](02-appearance-components.png) left | Searchable palette catalogue, miniature app/terminal previews | implemented; evidence in UX6 RESULTS |
| T2 | Appearance board right | Named semantic app colours, theme edit/import/export/apply | implemented; evidence in UX6 RESULTS |
| A1 | [Agent board](03-agent-components.png) left | User name; explicit instruction and skill source review | implemented; evidence in UX6 RESULTS |
| A2 | Agent board middle | Supplied source provenance and pending recipe proposal | implemented; evidence in UX6 RESULTS |
| A3 | Agent board right | Exact command/argv approval and separately reviewed output | functional approvals retained; native styling |

## Interpretation and corrections

Images specify hierarchy and shape, not literal production data. The first board uses invented source icons: use existing licensed harness icons in code. External activity must remain Unknown unless actually observed; the illustrated Working label does not create telemetry. User-selected nickname takes priority over OSC title. Light-mode text and focus must meet usable contrast; generated palette numbers are not authoritative theme values.

The appearance board accidentally shows three text lines in some rows; S1's two-line layout is authoritative. Graphite is an original neutral developer-tool-inspired palette, not a claim to ship an official Codex theme. Theme import accepts appearance fields only.

The agent board's token counts and Reviewed badges are illustrative. Show only measured counts and user-reviewed state. A skill is not necessarily built-in; use its actual declared/resolved path. Existing `~/.agents/AGENTS.md` may be a symlink: retain provenance and support an explicitly selected source. Do not automatically transmit the entire skill library. Permission checks remain code-enforced regardless of loaded instructions.

## Comparison checklist

For each implemented component record its S/T/A ID in docs/evidence/ux6/RESULTS.md and attach a running-app light/dark capture. Compare row height, icon/title/context order, selected focus, collapsed tooltip, destructive separation and absence of duplicate controls. Record deliberate native-control deviations. Never mark reference ready as implementation accepted.
