# Research findings and limits

## What the sources establish

**Native host feasibility:** Ghostty's architecture already uses a Swift/AppKit/SwiftUI macOS frontend with the engine's C interface. That supports the proposed technology boundary, not an assertion that embedding will be maintenance-free. [S01](../research/SOURCES.md#s01)

**Engine scope matters:** the full embedding header and the extracted VT-library concept serve different levels of functionality. The first build must prove which artifact provides rendering, process integration and native input. [S03](../research/SOURCES.md#s03)[S05](../research/SOURCES.md#s05)

**macOS 27 is not speculative in this packet:** Apple has current developer material for the platform and App Intents changes. The actual installed build and API availability remain an implementation check. [S06](../research/SOURCES.md#s06)[S08](../research/SOURCES.md#s08)

**Codex has a supported integration path:** its official app-server documentation covers richer clients and account flows, while official plugin packaging covers memory-compatible extension mechanisms. These are distinct from silently scraping a running terminal. [S11](../research/SOURCES.md#s11)[S13](../research/SOURCES.md#s13)

**Subscription authentication is not generic API billing:** keep the documented ChatGPT sign-in route separate from API-key usage and do not invent an unrestricted subscription-backed model proxy. [S12](../research/SOURCES.md#s12)

**OpenCode supports an explicit TUI/backend relationship:** use documented attachment/session interfaces when choosing a managed-server architecture. Bind and authenticate according to this app's threat model rather than blindly copying an example. [S15](../research/SOURCES.md#s15)[S16](../research/SOURCES.md#s16)

**Pi supports both interactive extensibility and RPC:** choose the mode that owns the actual session. An independently launched RPC process is not evidence of the state of another interactive process. [S19](../research/SOURCES.md#s19)[S21](../research/SOURCES.md#s21)

**1Password need not become a custom key integration:** the documented SSH-agent path can work through the system SSH client. It does not require exporting the user's private key into Trellis. [S23](../research/SOURCES.md#s23)[S25](../research/SOURCES.md#s25)

**Remote continuity needs a remote owner:** tmux attachment is a viable mechanism while the remote session survives; reboot/history recovery needs separate product semantics. [S26](../research/SOURCES.md#s26)

**The LLM Wiki idea is a pattern:** use it as inspiration for linked, curated Markdown, then implement explicit provenance, review and recovery policies. [S27](../research/SOURCES.md#s27)

## What was not established here

No exact Ghostty/Xcode combination was built. No agent plugin was installed. No account entitlement, model capability, SSH connection, biometric prompt or Siri action was tested. No performance, learning effectiveness or memory-quality benchmark was run. Any document describing those behaviours is an implementation requirement, not observed evidence.

The current code/header and documentation references are mutable. The coding agent must create a source/artifact/version lock and compatibility report on the actual Mac. The desired architecture is feasible enough to justify that spike, but its result must be reported honestly.
