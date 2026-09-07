# Trellis

A native macOS terminal built with SwiftUI and libghostty, with agent harnesses,
project Markdown memory, and a configurable workspace.

## Build and run

Apple Silicon, macOS 27 and Xcode 27 are required. See
[dependencies](DEPENDENCIES.md) for the pinned Ghostty and Zig toolchain.

```sh
./script/build_and_run.sh --verify
./script/check-features.sh
```

For an app bundle and drag-and-drop installer:

```sh
./script/package-personal.sh
./script/build-dmg.sh
```

Outputs are in `dist/`. Local packaging defaults to ad-hoc signing; see
[signing and GitHub Actions](docs/GITHUB-RELEASE.md) for certificate-backed builds.
This is a personal trial, not a notarized public release.

## Using Trellis

- Open a shell in your home folder, or choose a project and agent harness.
- Split live terminals, search sessions with ⌘P, and organize them into categories.
- Configure tab details, icons, sidebar sections and reusable layout presets.
- Open Trellis Agent beside the terminal with ⇧⌘A. Attach an editable terminal
  snapshot and review commands and output before sharing them with a direct API.
- Use Codex with its ChatGPT sign-in through the terminal harness.
- Review and export project Markdown memory; enable Learning and Dreaming explicitly.

Read the [usage guide](docs/PERSONAL-BUILD.md) and
[current status and limitations](docs/STATUS.md) before testing.

## Project documentation

- [Product intent](PRODUCT-BRIEF.md), [architecture](ARCHITECTURE.md),
  [design contract](DESIGN.md), and [concept references](assets/concepts/README.md)
- [Agent integrations](docs/AGENT-INTEGRATIONS.md),
  [models and authentication](docs/MODELS-AND-AUTH.md),
  [terminal sessions](docs/TERMINAL-AND-SESSIONS.md), and [SSH](docs/REMOTE-AND-SSH.md)
- [Memory](docs/MEMORY-AND-DREAMING.md),
  [security](docs/SECURITY-AND-PRIVACY.md), and [verification](docs/VERIFICATION.md)

Source, runnable checks, build scripts, licensed assets and design references are
tracked. Generated apps, installers, local screenshots, run logs, orchestration
state and handoff notes stay local. Third-party license notices live beside their
assets and under `Vendor/`; a project source license is still to be selected before
public release.
