# Verification that earns its maintenance cost

## Approach

Do not build a test-first programme, a coverage target or a large snapshot suite. Build the feature, exercise the actual behaviour and automate the invariants whose failure is expensive, subtle or dangerous.

A focused test is an executable acceptance rule for people and agents. Process
ownership, path safety and interrupted writes need observable checks.

Use a small set of focused checks, real integration runs and native UI review. Avoid mocking the entire app into a green result.

## High-value automated invariants

| Check | Why it matters | Add with |
| --- | --- | --- |
| Launch envelope preserves arguments and cwd | Prevent command injection and wrong-project work | M0/M1 |
| Surface teardown occurs once | Avoid crashes and duplicate process lifetime | M0 |
| View updates do not create a new session | SwiftUI recomposition must not duplicate work | M1 |
| Session restore never silently creates remote work | Prevent duplicate/destructive execution | M4 |
| Stream decoder handles partial UTF-8/frames | Real transports do not align with messages | M2 |
| Context retrieval enforces scope before ranking | Prevent cross-project leaks | M3 |
| Proposal paths stay under authorised roots | Prevent arbitrary writes | M3 |
| Stale base hashes reject apply | Protect user edits | M3 |
| Interrupted apply recovers consistently | Prevent corrupt guidance | M3 |
| Duplicate run IDs do not apply twice | Make restarts/catch-up safe | M6 |
| Suggestion response matches current buffer revision | Prevent stale text insertion | M5 |
| Accepting a suggestion never sends Return | Preserve execution control | M5 |

These are behaviours, not a requirement to create exactly twelve test functions. Merge or split tests where it improves clarity. Use Swift Testing or XCTest as appropriate to the actual code and SDK, not a new custom framework.

## Real integration evidence

For Ghostty: a native window with actual shell output, resize/input/focus checks and repeated lifecycle exercise. For each agent: installed version, launch identity, plugin handshake and a real memory read/propose round trip. For SSH: remote process/session identity before and after network disconnection. For 1Password: actual user-authorised key use without copying private material. For App Intents: actual system invocation, not just compiler success.

Do not use live provider requests in every unit-test run. Keep explicit opt-in integration checks for credentials and paid APIs, with spending limits and a fixture project.

## Native UI review

Exercise keyboard-only navigation, IME composition, clipboard/selection, multiple windows, tabs, external displays, light/dark mode, compact width, Reduce Transparency, Reduce Motion and VoiceOver. Validate error and empty states as carefully as the populated concept screen.

Use real screenshots and concise observations. Avoid a screenshot test suite sensitive to every font-rendering difference unless a concrete regression justifies it.

## CI minimum

On an appropriate macOS runner: compile the chosen configurations, run the small invariant suite and verify pinned dependencies/resources. Use formatting and basic static checks if they reduce noise. Do not require a complex CI matrix before there is a runnable app.

A hosted runner may not provide the intended beta SDK or a usable GUI session. Record those limits and perform GUI/Metal checks on the actual development Mac rather than silently treating skipped checks as passes.

## Evidence format

Each milestone report includes the revision, toolchain, commands, observed result, relevant screenshot/log path, skipped checks and limitations. Credentials and user project data are redacted or excluded.

A build failure must be classified accurately: compiler, linker, ABI mismatch, missing SDK, resource packaging, signing or runtime. Never claim “tests pass” when only documentation or static fixtures were checked.

## Runnable checks

Run `mise run check` for the native build, focused behavior and host checks.
`mise run build` builds without launching; `mise run package` also verifies the
local app bundle and DMG. Individual scripts can run with `mise exec --`.
Keep local logs and screenshots under the ignored `docs/evidence/` or
`.build-support/` directories; publish a concise, non-personal status in STATUS.md.
