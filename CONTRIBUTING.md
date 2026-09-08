# Contributing to Trellis

Trellis is a native macOS terminal. Contributions should preserve normal shell
operation, session ownership and explicit control over agent actions. Start with
[current status](docs/STATUS.md), [architecture](docs/ARCHITECTURE.md) and
[design](DESIGN.md) before changing a feature.

## Bootstrap

You need an Apple Silicon Mac running macOS 27, Xcode 27 with its command-line
tools selected, [mise](https://mise.jdx.dev/installing-mise.html) 2026.8.3 or newer,
and a macOS 26 compatibility SDK for the pinned Ghostty
engine. Install Xcode and accept its license first. Confirm the selection with
`xcode-select -p` and `xcodebuild -version`.

```sh
git clone https://github.com/thesammykins/trellis.git
cd trellis
mise trust
mise install
xcodebuild -downloadComponent MetalToolchain
mise run build
open .build/Build/Products/Debug/TrellisM0.app
```

`mise.toml` pins Zig, LLVM tools, Python, tmux and ImageMagick. `mise.lock` records
their macOS ARM64 packages and checksums, including conda dependencies. No Homebrew
or separate conda install is required. Apple supplies Xcode, the SDK and Metal.

The build fetches and verifies the Ghostty source pin, builds the engine and
helpers, resolves Sparkle, then packages an ad-hoc signed development app. You do
not need an Apple signing certificate, a provider account or release secrets.
The first engine build takes longer than subsequent builds.

If the compatibility SDK is elsewhere, set `TRELLIS_ENGINE_SDK` to its absolute
path before building. `TRELLIS_ZIG` can select Zig 0.15.2. See
[dependencies](docs/DEPENDENCIES.md) for exact versions and
[engine notes](Vendor/Ghostty/README.md) for the toolchain boundary. Do not upgrade
Zig independently of Ghostty.

Development builds use `~/Library/Application Support/Trellis Development`;
distributed builds use `~/Library/Application Support/Trellis`. Test changes with
disposable project folders. Installed agent tools retain their own accounts and
configuration, even when launched by a development build.

`mise run build` uses `--build-only`, leaving running apps alone. Open the bundle
explicitly. The script's other convenience run modes currently stop processes
named `TrellisM0`, including other worktrees.

## Make a change

1. Open an issue for a substantial feature or a change to persistence, security,
   dependencies or product scope. Small fixes can go straight to a pull request.
2. Branch from `main`, for example `feat/session-search` or `fix/window-restore`.
3. Trace the existing call path and reuse its types and controls. Keep terminal
   lifecycle, provider transport, memory and presentation responsibilities separate.
4. Exercise the changed behavior in the actual app. Include a focused regression
   check when a failure could lose data, leak scope, duplicate execution or break
   process ownership. Avoid tests that merely repeat the implementation.
5. Update the relevant guide and `docs/STATUS.md` when behavior or limits change.
   Add user-facing changes under `Unreleased` in `CHANGELOG.md`.

Source lives in `Trellis/`, launch and memory executables in `Helpers/`, agent
bridges in `Integrations/`, focused checks in `Checks/`, and build/release commands
in `script/`. Keep generated engine source, apps and evidence out of Git.

## Verify

```sh
mise run check
```

This builds the app first, then runs both existing check scripts.
`check-features.sh` covers portable domain and transport behavior, including
persistence, approvals and memory safeguards. `check-host.sh` additionally links
the native engine, so build it first. Neither replaces a live terminal/UI trial.
Use a fixture folder, record the observable result and identify skipped checks.
Provider, SSH and paid integration checks require deliberately configured test
accounts; do not make them an implicit part of ordinary tests.

For packaging changes, also run:

```sh
mise run package
```

These create local, ad-hoc signed outputs under `dist/`. The packaging script
refuses to overwrite a running `dist/Trellis.app`. Public signing, notarization
and Sparkle delivery are maintained separately in the restricted release
environment; see [release setup](docs/GITHUB-RELEASE.md).

## Commits and pull requests

Use Conventional Commits: `type(optional-scope): concise description`.

```text
feat(home): add session filters
fix(terminal): preserve focus after closing a split
docs: clarify the engine bootstrap
test(memory): reject stale proposal application
refactor(settings): share connection validation
```

Use `chore`, `build` or `ci` for maintenance, build tooling or workflow changes.
Mark incompatible changes with `!` and explain the migration. Keep commits
focused; avoid mixing formatting churn with behavior changes. Use a GitHub
noreply author address if you do not want to publish your email address.

A pull request should explain the concrete before/after behavior, why it changes,
the exact checks run and any remaining limits. For UI changes, include a screenshot
from the running app with example data. Do not include credentials, account
details, personal paths, private project names or unreviewed terminal output.

## Working with coding agents

[AGENTS.md](AGENTS.md) is the shared entry point. Give each delegated task a bounded
outcome, file ownership and an observable acceptance rule. One integrator owns
shared contracts and project metadata, reviews every diff and runs the combined
checks. A subagent's completion message alone is not verification.

Keep task ledgers, handoffs, exploratory plans and raw dogfood captures in ignored
`docs/local-history/`, `docs/orchestration/` or `docs/evidence/`. Commit reusable
guidance, relevant skills and product documentation. The example memory skill in
`examples/memory-skill/` is intentionally public.

Contributions are licensed under the repository's [MIT license](LICENSE).
Preserve third-party licenses and refresh notices when changing dependency pins.
