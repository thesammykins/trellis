# Personal trial

Trellis is a local Apple Silicon macOS 27 personal trial. It is not notarized
or a public distribution.

## Build and install

```sh
./script/package-personal.sh
./script/build-dmg.sh
open dist/Trellis.dmg
```

Drag **Trellis** onto **Applications** in the disk-image window, then eject the
image and open Trellis from Applications. The DMG build needs ImageMagick; the
script reports the Homebrew command if it is unavailable. It uses an isolated,
pinned `dmgbuild` environment and checks the image, its Applications symlink,
background and Finder layout.

`package-personal.sh` creates `dist/Trellis.app`, refuses to replace that app
while it is running, and strictly verifies its code signature. It uses ad-hoc
signing by default. Set `TRELLIS_SIGN_IDENTITY` to an available Apple Development
identity when you need a development-signed personal copy. Development builds
and the personal app keep separate Application Support folders.

For the private GitHub Actions artifact, development signing setup and release
boundaries, see [GitHub release](GITHUB-RELEASE.md).

## Start using Trellis

The first launch opens a home shell. Open a project when you want its folder,
sessions and approved Markdown memory to be scoped together. Help → Getting
Started with Trellis is available at any time.

- `⌘T` opens a shell and `⇧⌘T` opens an agent session. Use `⌘D` or `⇧⌘D` for a
  split, `⌘W` to close the focused session, and View → Tab Layout to change tab
  orientation.
- `⌘P` finds sessions by name, folder or harness. Create categories there and use
  their sidebar shortcuts. View → Customize Workspace controls ordered tab details,
  sidebar sections, inspector side and portable layout presets. Right-click a tab
  for its nickname, icon, accent and category. Split → Arrange Existing Panes
  reveals drag handles and drop targets; pane moves preserve the running shell.
- `⇧⌘A` opens the Trellis Agent side chat. Attach Terminal captures an editable
  viewport snapshot; sending it is explicit. The run keeps its initial folder
  even when you switch tabs. Commands and output sharing require review. This
  chat currently requires Direct API settings; File → Ask Codex in Terminal uses
  your ChatGPT sign-in instead.
- Accounts & Agents contains Codex and OpenCode setup. Their credentials remain
  with their owning tools. Direct API settings are separate from ChatGPT sign-in.
- Project Memory keeps approved notes reviewable. Context & Learn exposes
  context and learning beside the terminal. Dreaming remains off until enabled.
- Settings → Import Ghostty Settings previews supported font, Option-key,
  keybinding and theme settings before applying them. Commands, includes and
  unsupported lines are skipped; the source configuration is never changed.
- Sessions can refresh, attach to and explicitly end known local or SSH/tmux
  sessions. Existing OpenSSH configuration and host trust remain authoritative.

## Current limits

- This build is ad-hoc or Apple Development signed for personal testing, not
  Developer ID signed or notarized.
- SSH/tmux flows were exercised only against the development fixture. They do
  not establish general remote recovery or host compatibility.
- Pi, Claude Code and Gemini CLI are not installed on the development Mac, so
  their live launches are unverified.
- Dreaming uses a configured Direct API route only. Its cost can be unknown and
  it is bounded to one request, 64 KiB of approved notes and 2,048 output tokens.
- VoiceOver, other IMEs/keyboards, external displays, Shortcuts and Siri have
  not been revalidated in the final usability pass.

See [current status](STATUS.md) for the verified behavior and remaining checks.
Detailed screenshots and run records are kept locally, outside Git.
