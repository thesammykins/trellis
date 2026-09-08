# Build dependencies

Trellis targets Apple Silicon and macOS 27. The Xcode project uses Swift, SwiftUI,
AppKit, Foundation, Security and App Intents. Sparkle 2.9.6 is the single Swift
package dependency, pinned exactly in the Xcode project and Package.resolved.
It provides native signed updates; see [release setup](docs/GITHUB-RELEASE.md).

## Terminal engine

[Vendor/Ghostty/pin.json](Vendor/Ghostty/pin.json) is the build pin:
Ghostty v1.3.1 at `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`, Zig 0.15.2,
full native GhosttyKit embedding API. The source and engine build outputs live in
ignored `.build-support/ghostty`; binaries are not checked into Git.

```sh
brew install zig@0.15 llvm@20
xcodebuild -downloadComponent MetalToolchain
./script/build-engine.sh
```

The engine currently needs an installed macOS 26.5 compatibility SDK. Set
`TRELLIS_ENGINE_SDK` if it is not at the default Command Line Tools path.
Engine-only wrappers select that SDK and LLVM 20's Darwin archiver; the app uses
Xcode 27. Remove those wrappers only after a newly pinned toolchain passes without
them. Upstream Ghostty source is unmodified. `TRELLIS_ZIG` can select the required
Zig executable. See [engine notes](Vendor/Ghostty/README.md).

## Installer

`script/build-dmg.sh` requires ImageMagick, Python 3.10 or later, and macOS system
fonts. It creates an isolated environment with dmgbuild 1.6.7, ds_store 1.3.3 and
mac_alias 2.2.3. The script generates the installer background and validates Finder
icon positions; neither that generated image nor the resulting DMG is tracked.

## Optional tools

Agent harnesses (Codex, OpenCode, Pi, Claude Code and Gemini CLI) are separately
installed tools. System OpenSSH supplies SSH transport; persistent sessions require
tmux. Trellis detects optional tools and keeps ordinary terminal use available
when they are absent. Markdown memory uses Foundation and app-managed files.

The original architecture discusses possible future dependencies; GRDB, Yams,
swift-markdown and an MCP SDK are not installed dependencies of this build.
The packaged app includes Trellis, Ghostty and Sparkle licenses and
[engine dependency notices](Vendor/Ghostty/THIRD-PARTY-NOTICES.txt), including
embedded fonts and links to the unmodified MPL-covered z2d source. Refresh these
notices when updating the engine pin. This software is based in part on the work
of the FreeType Project.
