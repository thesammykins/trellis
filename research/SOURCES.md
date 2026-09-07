# Primary-source register

Checked on **7 September 2026**. These are research references, not bundled copies of third-party documentation. Mutable pages and main branches may change. No current dependency has been compiled or exercised in this packet.

Each S-number is used at the point where a document relies on an external fact. Proposed architecture, safeguards and milestone choices are our design recommendations, not claims that the sources prescribe this application.

<a id="s01"></a>

## S01 · Ghostty: About

Source: [Ghostty: About](https://ghostty.org/docs/about)

Official architecture description. Supports a native Swift/AppKit/SwiftUI host around the Ghostty C interface; does not validate this proposed app.

<a id="s02"></a>

## S02 · Ghostty upstream repository

Source: [Ghostty upstream repository](https://github.com/ghostty-org/ghostty)

Primary source and project entry point. Inspect the pinned source and licence rather than relying on a mutable main branch.

<a id="s03"></a>

## S03 · Ghostty full embedding C header

Source: [Ghostty full embedding C header](https://github.com/ghostty-org/ghostty/blob/main/include/ghostty.h)

Inspected full surface interface, including working_directory and a command string. Header shape and ABI must be pinned together with the artifact.

<a id="s04"></a>

## S04 · Ghostty source build instructions

Source: [Ghostty source build instructions](https://ghostty.org/docs/install/build)

Documents release-specific Zig requirements and macOS build prerequisites. The inspected table associates Ghostty 1.3.x with Zig 0.15.2; that is a research observation, not this project's selected lock.

<a id="s05"></a>

## S05 · Libghostty Is Coming

Source: [Libghostty Is Coming](https://mitchellh.com/writing/libghostty-is-coming)

Maintainer's September 2025 explanation of the separately extracted VT core. Historical explanation of the distinction, not a current package availability guarantee.

<a id="s06"></a>

## S06 · Apple: What is new in macOS 27

Source: [Apple: What is new in macOS 27](https://developer.apple.com/macos/whats-new/)

Current macOS 27 technology overview. At inspection it points to Xcode 27 and macOS 27 beta resources; validate the actual local SDK.

<a id="s07"></a>

## S07 · Apple: App Intents

Source: [Apple: App Intents](https://developer.apple.com/documentation/appintents)

Official framework entry point for actions and content discovery. Individual APIs require availability verification.

<a id="s08"></a>

## S08 · Apple WWDC26: Advanced App Intents for Siri and Apple Intelligence

Source: [Apple WWDC26: Advanced App Intents for Siri and Apple Intelligence](https://developer.apple.com/videos/play/wwdc2026/343/)

Primary session on richer Siri integration, content discovery and on-screen context. Does not establish that this app has been integrated or tested.

<a id="s09"></a>

## S09 · Apple: Adopting Liquid Glass

Source: [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)

Official design/technology reference. Some documentation uses JavaScript rendering; use the live documentation and installed SDK while implementing.

<a id="s10"></a>

## S10 · Apple: GlassEffectContainer

Source: [Apple: GlassEffectContainer](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)

Official custom-glass grouping API reference. Prefer normal system controls where they already express the interaction.

<a id="s11"></a>

## S11 · OpenAI: Codex App Server

Source: [OpenAI: Codex App Server](https://learn.chatgpt.com/docs/app-server)

Official integration, protocol and account-flow reference, reached from developers.openai.com/codex/app-server. Supports version-specific schema generation; keep transport and experimental feature distinctions.

<a id="s12"></a>

## S12 · OpenAI: Codex authentication

Source: [OpenAI: Codex authentication](https://learn.chatgpt.com/docs/auth)

Official distinction between ChatGPT sign-in and API-key access, reached from developers.openai.com/codex/auth. Does not establish a general-purpose subscription-to-API bridge.

<a id="s13"></a>

## S13 · OpenAI: Package your plugin

Source: [OpenAI: Package your plugin](https://developers.openai.com/plugins/build/plugins)

Official plugin packaging reference including skills, MCP servers and lifecycle hooks. Recheck installed-release hooks and manifest format.

<a id="s14"></a>

## S14 · OpenCode: Plugins

Source: [OpenCode: Plugins](https://opencode.ai/docs/plugins/)

Official plugin and event reference. Supports an agent-native bridge, with actual hook behaviour to be demonstrated at the pinned version.

<a id="s15"></a>

## S15 · OpenCode: Server

Source: [OpenCode: Server](https://opencode.ai/docs/server/)

Official backend API reference. The plan adds its own loopback, credential and lifecycle policy; documentation alone is not evidence of deployment security.

<a id="s16"></a>

## S16 · OpenCode: CLI

Source: [OpenCode: CLI](https://opencode.ai/docs/cli/)

Official commands including TUI attachment to a running backend, explicit session selection and model discovery. Do not copy its network-binding examples blindly.

<a id="s17"></a>

## S17 · OpenCode: Zen

Source: [OpenCode: Zen](https://opencode.ai/docs/zen/)

Official curated model-service reference. Model inventory, availability and prices are mutable and deliberately not frozen in this packet.

<a id="s18"></a>

## S18 · OpenCode: Go

Source: [OpenCode: Go](https://opencode.ai/docs/go/)

Official subscription reference. Eligibility and catalogue must be discovered through the user's actual account.

<a id="s19"></a>

## S19 · Pi: project site

Source: [Pi: project site](https://pi.dev/)

Primary project overview describing interactive, print/JSON, RPC and SDK modes and extensibility.

<a id="s20"></a>

## S20 · Pi coding-agent README

Source: [Pi coding-agent README](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/README.md)

Current repository result for the coding-agent overview. Older badlogic/pi-mono links also surfaced; resolve the actual installed upstream rather than guessing package identity.

<a id="s21"></a>

## S21 · Pi: RPC documentation

Source: [Pi: RPC documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md)

Primary line-delimited JSON command/event and extension-UI reference. RPC is a mode owned by a particular process, not automatic observation of a different TUI.

<a id="s22"></a>

## S22 · Pi: extension examples

Source: [Pi: extension examples](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/examples/extensions/README.md)

Upstream example index found during research. Exact current extension hooks must be obtained from the installed/pinned version; not treated as a frozen API.

<a id="s23"></a>

## S23 · 1Password: SSH agent

Source: [1Password: SSH agent](https://www.1password.dev/ssh/agent)

Official SSH-agent integration. Use normal key authorisation without exporting private key material.

<a id="s24"></a>

## S24 · 1Password: SSH agent configuration

Source: [1Password: SSH agent configuration](https://www.1password.dev/ssh/agent/config)

Official configuration reference. Preserve user-owned configuration and distinguish use of an agent from forwarding it remotely.

<a id="s25"></a>

## S25 · OpenSSH: ssh_config manual

Source: [OpenSSH: ssh_config manual](https://man.openbsd.org/ssh_config)

Primary configuration reference for IdentityAgent, host checks, forwarding and connection configuration. Check the local Apple-shipped OpenSSH version too.

<a id="s26"></a>

## S26 · tmux: Getting Started

Source: [tmux: Getting Started](https://github.com/tmux/tmux/wiki/Getting-Started)

Maintainer documentation on sessions and attachment. Persistent remote process claims still require an actual reconnect exercise.

<a id="s27"></a>

## S27 · Andrej Karpathy: LLM Wiki idea file

Source: [Andrej Karpathy: LLM Wiki idea file](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)

Original knowledge-base pattern and inspiration. This packet's approval, isolation and transaction design are proposed additions, not claims made by that idea file.

<a id="s28"></a>

## S28 · Official Swift MCP SDK

Source: [Official Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk)

Primary Swift SDK source. Inspect the supported protocol at the pinned version and negotiate capabilities explicitly.

<a id="s29"></a>

## S29 · MCP: SDK documentation

Source: [MCP: SDK documentation](https://modelcontextprotocol.io/docs/2026-07-28/sdk)

Current protocol SDK overview surfaced during research. A newer documentation revision does not mean every SDK implements it.

<a id="s30"></a>

## S30 · GRDB.swift

Source: [GRDB.swift](https://github.com/groue/GRDB.swift)

Upstream Swift/SQLite toolkit. Recommended for registry, migrations and index, subject to selected-version review.

<a id="s31"></a>

## S31 · swift-markdown

Source: [swift-markdown](https://github.com/swiftlang/swift-markdown)

Upstream Markdown parser and syntax-tree package. Proposed for document analysis, not a WebView-based UI.

<a id="s32"></a>

## S32 · Yams

Source: [Yams](https://github.com/jpsim/Yams)

Upstream YAML parser. Proposed for constrained front matter decoding rather than inventing a partial YAML parser.

<a id="s33"></a>

## S33 · Apple: Schedule Background Activity

Source: [Apple: Schedule Background Activity](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/SchedulingBackgroundActivity.html)

Primary archived explanation of discretionary background scheduling. Useful for the scheduling model; validate actual APIs against the current SDK.
