# Project status · 0.4.0

Trellis 0.4.0 (build 7) is available as a Developer ID signed, Apple-notarized
[public release](https://github.com/thesammykins/trellis/releases/tag/v0.4.0).
The application targets Apple Silicon and macOS 27.

## Available behavior

- A real Ghostty terminal with independent windows, session tabs and up to eight
  panes per tab. Balancing and temporary maximization retain terminal surfaces.
  Files follows the active local folder with lazy loading and Refresh.
- Home with searchable grid/list views of open and saved sessions, plus SSH
  favorites for ordinary logins or tmux. Quit/reopen restores windows, navigation,
  tabs, pane proportions and the active window. Local processes stay stopped;
  remote attachments reconnect only on request.
- Native Codex conversations using the installed app-server and existing ChatGPT
  account. Codex owns tools, approvals, history, compaction and caching. Trellis
  retains native thread IDs and discovers model/reasoning choices.
- Direct API connections with provider presets, Keychain credentials and cached
  model discovery. Explicit @ session context, specialist assignment, editable
  delegation/escalation routes and shared task limits are available on this route.
- Approval cards show the action, reason and destination. Direct API scoped reads
  and sharing can be automatically approved; commands and terminal access remain
  reviewed. Approved visible-terminal submission does not imply completion.
- Reviewed Markdown memory, revision-checked edits and reusable tool proposals.
  Instructions and selected skills retain their originating project scope.
- Commands scheduled at an interval or daily while the app is open. Missed runs
  are skipped. Dreaming is optional, off by default, and produces proposals.
- Searchable settings for appearance, shell configuration, accounts, agent roles,
  workspace layout and updates. Sparkle offers explicit installation from the app
  menu or Settings; automatic checking is optional.

Native Codex uses its native command tools; reviewed submission into the visible
Ghostty terminal belongs to the Direct API harness. Direct chat and child
transcripts are currently in memory. Subscriptions are not converted into
unofficial API credentials or silently replaced with paid API requests.

Observed token/cache usage can be unavailable. Optional token allowances stop
further work when exhausted or usage is unknown, but one response/native turn may
overshoot the allowance. They are not prepaid or monetary caps. Specialist tasks
run sequentially with shared request, task and depth limits.

## Verification

The 0.4.0 pass exercised the compiled app with disposable projects:

- Home grid/list/search, SSH favorite save/reload without connecting, cross-window
  session reuse and passive restoration of stopped local sessions.
- A real ChatGPT-subscription Codex conversation, native command approval,
  model/reasoning discovery, token/cache reporting and restored native history.
- Public OpenRouter model discovery, saved connection selection and refresh.
- Real Ghostty shell execution, eight panes, physical divider resizing,
  maximize/restore without replacing the shell, and restored layout proportions.
- Agent Team editing and accessible route controls, Settings categories, Files,
  memory revision safeguards and reviewed app-open automation execution.

The native app build, 41 feature check groups and four host checks passed. Earlier
0.3.x dogfood covered Direct API streaming, @ assignment, reviewed terminal
submission/output sharing, tool proposals, child tasks and core VoiceOver flows.
These do not constitute validation of every input method or third-party harness.

The [tag-triggered release workflow](https://github.com/thesammykins/trellis/actions/runs/34179250493)
built, signed and notarized the app and DMG, then published the DMG, signed appcast
and checksums. Anonymous downloads passed checksum verification; the downloaded
DMG passed stapling and Gatekeeper checks.

A locally derived, signed and notarized build 6 was used solely as an upgrade
fixture. Sparkle offered the public build 7. Canceling the busy-work quit sheet
preserved its shell and child process. Installing stopped those processes,
replaced the app, relaunched build 7 and restored the stopped session. The
installed app passed signature, notarization and Gatekeeper verification and
subsequently reported that it was up to date.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for runnable checks. Raw captures, private
test state and historical milestone notes remain local; README screenshots use
disposable example projects and reviewed shell output.

## Known limits and next checks

- Physical divider dragging passed. Native automation did not complete
  agent-route drop delivery; tab, pane, sidebar and route drag/drop still need a
  manual trial. Equivalent route/menu/layout controls are available.
- Pi, Claude Code and Gemini CLI launches have not been exercised in this pass.
  SSH checks cover an authorized fixture host, not general remote recovery.
- Core VoiceOver flows were exercised previously. Braille, other input methods,
  external displays, every dialog, Shortcuts and Siri remain outside this pass.
- Clean-machine and offline-first-launch validation remain distribution checks.
  Signing and notarization alone do not prove those paths.
- The development run script can stop other worktrees' `TrellisM0` processes.
  Use `--build-only` and open the intended artifact while working in parallel.
  Dreaming's five-minute eligibility window needs a midnight boundary check.

The [changelog](../CHANGELOG.md) records released changes. Product guides describe
intended boundaries; this page identifies what was actually exercised.
