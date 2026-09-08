# Changelog

## Unreleased

- Add contributor bootstrap, verification and Conventional Commit guidance.
- Replace historical planning and private trial material with current architecture,
  memory and App Intents documentation, plus clean screenshots of the running app.
- Retire the private development-signing workflow; retain the public release pipeline.

## 0.4.0

- Home shows searchable grid or list views of open and saved sessions, plus SSH favorites.
- Restore windows, selected tabs and panes, split proportions and the active window after quitting. Shells remain stopped until started; SSH connects only on request.
- Use an existing ChatGPT sign-in in the native Codex conversation panel, with Codex tools, approvals, history, compaction and caching.
- Discover and cache models, select supported reasoning levels, and save API connections using provider presets.
- Configure specialist roles, delegation and escalation routes, and optional shared or per-agent token allowances.
- Show clearer permission requests with the action, reason and destination, plus observed usage in agent activity.
- Add signed Sparkle updates, native update settings and a Developer ID/notarization release pipeline.
- Fix stopped-pane sizing, active-window restoration, public OpenRouter model discovery, cleanup when the last workspace closes, and stale app selection in DMG packaging.

## 0.3.3

- Fix pasted @ specialist assignments and improve visible-terminal command review.
- Refine specialist task activity, permission handling and in-app scheduling.
- Verify the personal app bundle and drag-and-drop installer.

## Earlier development

The initial native terminal foundation, workspace customization, Markdown memory,
agent integrations and focused checks are recorded in [project status](docs/STATUS.md)
and the Git history.
