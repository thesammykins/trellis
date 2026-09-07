# Personal trial status · 0.2.0

Trellis includes a full Ghostty-backed native terminal, shell and agent launchers,
split panes, independent windows, saved sessions, local/SSH tmux attachment,
Markdown memory review, theme import/export, Ghostty settings import and onboarding.
Workspace customization adds ordered tab details, category shortcuts, session
icons, sidebar layout and portable presentation presets.

The native side chat now keeps a separate conversation and draft for each terminal
session, streams Responses and Chat Completions replies, renders headings/lists/links
and copyable fenced code, and places reviewed tool receipts beside their originating
turn. Execution and edited-output release remain separate approvals. Chat history
is in-memory; a conversation keeps its original tool scope after the shell changes
folder. Terminal context is attached explicitly.

The native Files outline follows the active local terminal folder, with a labelled
launch-folder fallback, lazy folders, Refresh, Finder/default-app actions and path
copy/drag. Remote browsing is unavailable. Narrow layouts compact navigation;
terminal panes and selected tabs expose meaningful accessibility identity. Theme
editing diagnoses app-text contrast and offers an explicit correction.
It uses Direct API settings. ChatGPT subscription authentication is available
through the Codex terminal harness, not through the native side chat.

## Verification

The UX10 development build and feature checks passed. Native localhost testing
exercised streaming rich replies, exact code copying, terminal focus during
completion, independent session drafts, live folder changes with shell PID
continuity, and output-review draft retention across inspector switching.
The existing 0.2.0 personal app and DMG below predate UX10.


The 0.2.0 macOS build, focused feature checks, Apple Development signing and DMG
validation passed. Native UI checks exercised session search/category assignment,
preset export/reset/import, custom symbols, vertical-tab collapse and menu-driven
pane moves preserving live shell identities. A localhost Responses fixture
exercised command approval, output review and continued chat history.

```sh
./script/check-features.sh
./script/build_and_run.sh --build-only
./script/package-personal.sh
./script/build-dmg.sh
```

Detailed run records and screenshots are local development artifacts, excluded
from the repository. Fixture success is not evidence of a live cloud-provider run.

## Known limits and next checks

- Drag sources were observed, but native automation did not complete target/drop
  delivery. Tab, pane and sidebar drag gestures still need a manual trial.
  Equivalent menu and layout controls remain available.
- Pi, Claude Code and Gemini CLI launches have not been exercised on the
  development machine. SSH checks covered only an authorized fixture host.
- VoiceOver, other input methods, external displays, Shortcuts and Siri have not
  been revalidated in the latest pass.
- Identity overrides are per session. Layout exports contain presentation only;
  they exclude commands, credentials, private paths and instruction trust.
- This is an Apple Silicon/macOS 27 personal build. Public distribution requires
  a source-license decision and a Developer ID/hardened-runtime/notarization route.

Next work should follow user trial results, beginning with native drag gestures.
