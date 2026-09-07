# Decisions and risks

These are proposed defaults grounded in the brief. They are not claims that Samantha explicitly selected every implementation detail.

## Decision register

| ID | Default | Why | Revisit when |
| --- | --- | --- | --- |
| D01 | Full Ghostty macOS embedding | Reuse renderer/input-terminal core rather than building one around VT parsing | M0 finds a concrete blocker |
| D02 | SwiftUI host, narrow AppKit bridge | Native platform behaviour without forcing low-level terminal input into SwiftUI alone | A specific native capability needs a broader bridge |
| D03 | macOS 27, Apple Silicon first | Greenfield personal target matches the requested platform direction | Actual host lacks the SDK or the user requests broader support |
| D04 | Real CLI UI plus structured side integrations | Preserve agent tools without unreliable terminal scraping | Upstream adds a better documented shared-session API |
| D05 | Markdown canonical; SQLite for registry/index | Portability plus reliable local state/search | Measured scale or query needs justify change |
| D06 | Proposals before memory/instruction writes | Prevent silent drift and protect user edits | User explicitly enables limited low-risk auto-apply after evaluation |
| D07 | OpenSSH and remote tmux | Reuse mature existing mechanisms | A demonstrated feature cannot use the system client |
| D08 | Agent-owned subscription authentication | Avoid unofficial token reuse and hidden billing changes | A provider publishes a different supported integration |
| D09 | No-tools native dreaming route first | Clearer write/tool boundary | Harness restrictions have been enforced and demonstrated |
| D10 | Risk-based verification | Spend effort where failures matter | Actual defects identify missing checks |
| D11 | Separate learning presentation | Guide users without restricting the real terminal | User research identifies a better interaction |
| D12 | Development orchestration, not new runtime agent mesh | Avoid unnecessary product complexity | Samantha explicitly requests in-app orchestration |

## Risk register

| Risk | Impact | Mitigation / gate |
| --- | --- | --- |
| Ghostty ABI/build changes | Broken binary or subtle crashes | Pin source/header/artifact and re-run M0 checks on upgrade |
| Terminal input/IME/focus defects | App unusable despite attractive UI | Native input spike before extensive UI |
| Structured API unrelated to visible TUI | Incorrect state and duplicate sessions | Demonstrate actual ownership/attach relationship |
| Same-user agent access bypasses memory API | False security claims | Explain boundary; use actual isolation for unattended work |
| Generated memory reinforces errors | Persistent bad guidance | Provenance, conflict review, staleness and revert support |
| Multi-file apply interrupted | Corrupt instructions/knowledge | Journal and recovery checks |
| Remote reconnect creates new work | Duplicated actions and costs | Attach-only semantics; explicit replacement choice |
| GUI PATH differs from terminal | Agent not found or wrong executable | Visible resolved executable and controlled environment |
| Provider/model changes | Lost capability or billing surprise | Runtime discovery and explicit route fallback |
| macOS 27 API availability changes | Compile/runtime incompatibility | Record exact SDK and guard availability |
| Overengineering by many agents | Slow integration and incoherent code | Small milestones, ownership, no speculative platform |
| Too many tests or no useful tests | Maintenance drag or hidden regressions | Only targeted executable invariants plus real smoke evidence |

## Decisions intentionally deferred

Final name/icon; exact supported dependency versions; initial remote operating system beyond the first verified Linux host; model choice for unattended jobs; whether local session persistence beyond app lifetime is worth adding; distribution and update channel; wiki sharing/synchronisation across multiple Macs.

These do not block M0. Record choices as evidence arrives rather than asking the user to resolve speculative implementation details in advance.
