# Personal trial status · 0.2.0

Trellis includes a full Ghostty-backed native terminal, shell and agent launchers,
split panes, independent windows, saved sessions, local/SSH tmux attachment,
Markdown memory review, theme import/export, Ghostty settings import and onboarding.
Workspace customization adds ordered tab details, category shortcuts, session
icons, sidebar layout and portable presentation presets.

The native side chat supports an explicitly attached terminal viewport, reviewed
background tools and follow-ups retaining prior messages and tool receipts.
It uses Direct API settings. ChatGPT subscription authentication is available
through the Codex terminal harness, not through the native side chat.

## Verification

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
