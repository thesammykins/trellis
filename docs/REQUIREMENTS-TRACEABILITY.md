# Requirements traceability

| Original requirement | Coverage | Milestone / status |
| --- | --- | --- |
| Entirely native Swift/SwiftUI app | ARCHITECTURE.md, DESIGN.md | M0 onward; host native, engine/plugin-language exceptions explicit |
| libghostty foundation | TERMINAL-AND-SESSIONS.md, DEPENDENCIES.md | M0, full-engine feasibility gate |
| Agent tabs in project folders | PRODUCT-BRIEF.md, TERMINAL-AND-SESSIONS.md | M1 |
| Codex | AGENT-INTEGRATIONS.md | Terminal M1, rich integration M2 |
| OpenCode | AGENT-INTEGRATIONS.md | Terminal M1, rich integration M2 |
| Pi | AGENT-INTEGRATIONS.md | Terminal M1, rich integration M2 |
| Normal terminal window | PRODUCT-BRIEF.md, DESIGN.md | M0/M1, not removed by agent features |
| Unified concept art | assets/concepts/README.md, DESIGN.md | Two original PNGs preserved; one proposed primary |
| Detailed design.md | Root DESIGN.md | Included |
| Cross-agent plugins for memory | AGENT-INTEGRATIONS.md, contracts/PROTOCOLS.md | M2/M3 |
| Markdown / LLM Wiki memory | MEMORY-AND-DREAMING.md | M3 |
| Projects grow useful knowledge | MEMORY-AND-DREAMING.md | Reviewed knowledge with provenance, not model training |
| Overnight dreaming | MEMORY-AND-DREAMING.md, prompts/DREAMING.md | M6, app-open/awake conditions explicit |
| Choose dreaming model | MODELS-AND-AUTH.md | M6, enforced-eligibility gate |
| Update root AGENTS.md and skills | MEMORY-AND-DREAMING.md | M3/M6, reviewed proposals by default |
| New research during dreaming | MEMORY-AND-DREAMING.md | M6, separate explicit research permission |
| Advanced mode | DESIGN.md | Common workspace and permissions |
| Learning mode | LEARNING-AND-SUGGESTIONS.md | M5 |
| Remote persistent SSH sessions | REMOTE-AND-SSH.md | M4, remote tmux |
| Restore previous remote session | REMOTE-AND-SSH.md | M4, attach-only, no implicit replacement |
| 1Password SSH | REMOTE-AND-SSH.md | M4, supported agent path, no key extraction |
| Native suggestions | LEARNING-AND-SUGGESTIONS.md | M5, supported shell editing states only |
| ChatGPT subscription access | MODELS-AND-AUTH.md | M2, supported Codex route |
| OpenCode Go and Zen | MODELS-AND-AUTH.md | M2, account/model discovery |
| Mix of frontier and open models | MODELS-AND-AUTH.md | Capability-based routes, no fixed catalogue |
| macOS 27 / Liquid Glass / HIG | DESIGN.md, research/SOURCES.md | M0/M7, actual SDK verification |
| App Intents / Siri content and actions | APP-INTENTS.md | M7, scoped entities and actions |
| Greenfield, single personal user | PRODUCT-BRIEF.md | No migration/enterprise compatibility work |
| Root agent and sub-agents build app | ORCHESTRATION.md, ../AGENTS.md | Development workflow |
| Avoid excessive tests | VERIFICATION.md | No coverage quota; targeted meaningful checks |
| Build and installer | ../README.md, PERSONAL-BUILD.md | Native personal trial |

Paths in this table are navigation descriptions. Root documents are in the packet root; feature documents are in `docs/`; prompts, research and assets use their named folders.
