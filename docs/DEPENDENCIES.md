# Build dependencies

Trellis targets Apple Silicon and macOS 27. The app uses Swift, SwiftUI, AppKit,
Foundation, Security and App Intents. Sparkle 2.9.6 is its only Swift package,
pinned exactly in the Xcode project and Package.resolved.

## Development tools

Install [mise](https://mise.jdx.dev/installing-mise.html) 2026.8.3 or newer, then
run `mise trust` and `mise install` in the repository. The root `mise.toml` pins:

| Tool | Version | Distribution |
| --- | --- | --- |
| Zig | 0.15.2 | conda-forge |
| LLVM tools | 20.1.8 | conda-forge |
| Python | 3.13.13 | mise Python backend |
| tmux | 3.6b | upstream tmux builds through Aqua |
| ImageMagick | 7.1.2-31 | conda-forge |

The committed `mise.lock` records macOS ARM64 packages and checksums, including
transitive conda dependencies. No Homebrew or separate conda installation is needed.
Use `mise run build`, `mise run check` and `mise run package`, or prefix an existing
script with `mise exec --`. See [contributing](../CONTRIBUTING.md) for bootstrap.

CI uses `mise install --locked` with global mise configuration disabled, so only
repository tools participate. Local `mise install` honors the project lockfile
while allowing separately configured global tools. To update pins deliberately,
edit `mise.toml`, run `mise lock --platform macos-arm64`, then rebuild and verify.
The lockfile supports the app's macOS ARM64 target, not a cross-platform build.

## Apple toolchain and terminal engine

Xcode 27, a macOS 26.5 compatibility SDK and Apple's Metal toolchain are system
prerequisites. mise does not install Apple SDKs or accept their licenses.

```sh
xcodebuild -downloadComponent MetalToolchain
mise exec -- ./script/build-engine.sh
```

[The engine pin](../Vendor/Ghostty/pin.json) selects Ghostty v1.3.1 at
`332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28` with the full native embedding API.
Source and build outputs live in ignored `.build-support/ghostty`.

Use mise's conda-forge Zig build. The upstream Zig 0.15.2 tarball fails a native
libc-link probe against the current SDK stubs; the maintained conda-forge build
passes without modifying Apple's SDK or maintaining a local compiler patch.
`TRELLIS_ZIG` can explicitly select another compatible Zig 0.15.2 executable.

Set `TRELLIS_ENGINE_SDK` if the compatibility SDK is not at the default Command
Line Tools path. Engine-only wrappers select that SDK and LLVM's Darwin archiver;
the app uses Xcode 27. Upstream Ghostty source is unmodified. Remove the wrappers
only after a newly pinned toolchain builds and verifies without them. See
[engine notes](../Vendor/Ghostty/README.md).

## Installer and optional tools

`script/build-dmg.sh` uses mise's ImageMagick and Python, plus macOS system fonts.
It creates an isolated environment with dmgbuild 1.6.7, ds_store 1.3.3 and
mac_alias 2.2.3. Generated installer art and DMGs stay outside Git.

Agent harnesses are separately installed tools with their own accounts. System
OpenSSH provides SSH; persistent sessions require tmux. Ordinary terminal use
remains available when optional tools are absent. Markdown memory uses Foundation
and app-managed files; GRDB, Yams and an MCP SDK are not dependencies.

The app bundles Trellis, Ghostty and Sparkle licenses and
[engine dependency notices](../Vendor/Ghostty/THIRD-PARTY-NOTICES.txt), including
embedded fonts and the unmodified MPL-covered z2d source links. Refresh notices
when updating engine pins. This software is based in part on the work of the
FreeType Project. See [release setup](GITHUB-RELEASE.md) for signed distribution.
