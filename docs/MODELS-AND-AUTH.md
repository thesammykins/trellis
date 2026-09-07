# Model routes and authentication

## Separate three concepts

**Agent:** the CLI/harness running the task. **Provider:** the service serving a model. **Account route:** the subscription or API credential paying for and authorising that request.

A model picker must not collapse these into an interchangeable list. The same model name may be available through different accounts, with different limits and supported functionality.

## Initial routes

| Route | Intended use | Credential owner | Behaviour |
| --- | --- | --- | --- |
| Codex + ChatGPT sign-in | Interactive Codex and supported separately owned Codex tasks | Codex's supported auth flow | Show account/limit state; do not export tokens |
| Codex + API key | User-selected alternative Codex route | Codex or explicitly configured supported store | Separate usage-based route, never a silent fallback |
| OpenCode Go | Supported OpenCode model access | OpenCode/provider flow | Discover actual entitled models |
| OpenCode Zen | Supported OpenCode model access | OpenCode/provider flow | Separate from Go and its limits |
| Native direct API | Explicit learning/suggestion/consolidation requests | Trellis Keychain entry | No-tools calls and bounded context by default |
| Local model endpoint | Optional later native assistant route | User-configured local service | Verify protocol and tool/stream support; no cloud fallback |

OpenAI documents ChatGPT sign-in and API-key access as distinct Codex authentication routes. This does not establish unrestricted general-purpose API entitlement through a ChatGPT subscription. Use the supported Codex integration rather than reverse-engineering subscription tokens. [S12](../research/SOURCES.md#s12)

OpenCode documents Go as a subscription offering and Zen as a curated model service. The current model inventory and entitlements should be obtained through supported provider/agent discovery, not frozen into the application. Avoid making billing or pricing promises in a build plan. [S17](../research/SOURCES.md#s17)[S18](../research/SOURCES.md#s18)

## Native assistant features

Learning, suggestions and dreaming each choose an eligible route. Do not assume any account can serve any feature. In particular, unattended consolidation requires demonstrated tool and filesystem restrictions, while interactive Codex sessions can remain fully functional before that gate is complete.

The UI must say why a route is unavailable: sign-in required, no entitlement, unsupported structured output, unavailable endpoint or insufficient execution restrictions. A disabled option is more honest than a hidden unofficial token bridge.

Start with minimal provider adapters implemented over Foundation networking. Do not add an all-provider SDK or local inference engine until a concrete capability requires it. Keep wire formats and model-specific options behind a typed interface.

## Authentication behaviour

Use the provider or agent's documented login flow. Validate browser destinations against the actual supported auth flow; do not open arbitrary URLs supplied by terminal output. Keep secrets out of command arguments, environment dumps, wiki content, logs and diagnostic bundles.

Store Trellis-owned API keys using Keychain, scoped by provider and account. Upstream-owned credentials remain upstream-owned. Logout should clearly state which account/store it affects and should not delete unrelated credentials.

Remote agents need authentication on the remote host or another explicitly supported method. Do not automatically copy local OAuth stores or forward general account credentials over SSH.

## Model catalogue

Record provider ID, model ID, account route, observed capabilities, context limits when reported, discovery time and freshness. Label open-weight versus source-available versus proprietary according to actual model licensing rather than treating all non-Western models as “open source.” Origin and hosting region are separate from licence and privacy terms.

Refresh intentionally and cache for offline display. If a model disappears, preserve the user's selection as unavailable and ask for a replacement. Do not silently downgrade capability, switch provider, change data residency or incur new charges.

## Failures and usage

Handle token expiry, rate limits, account cancellation, model removal, malformed streaming events and cancelled requests. A retry must distinguish idempotent reads from a submitted agent turn. Show cost only when supported by actual metering, otherwise label the estimate or say unavailable.

Users explicitly opt into sending selected project content to a cloud route. The app should show the scope being sent rather than hiding it behind a generic “AI enabled” toggle.
