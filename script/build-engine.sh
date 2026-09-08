#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ZIG="${TRELLIS_ZIG:-$(command -v zig || true)}"
if [[ ! -x "$ZIG" ]]; then
  echo 'Install the pinned toolchain with mise install, then run mise run build.' >&2
  exit 1
fi
[[ "$("$ZIG" version)" == 0.15.2 ]] || { echo 'Ghostty pin requires Zig 0.15.2' >&2; exit 1; }
SOURCE="$ROOT/.build-support/ghostty"
PIN=332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28
if [[ ! -d "$SOURCE" ]]; then
  mkdir -p "$ROOT/.build-support"
  git clone --depth 1 --branch v1.3.1 https://github.com/ghostty-org/ghostty.git "$SOURCE"
fi
[[ "$(git -C "$SOURCE" rev-parse HEAD)" == "$PIN" ]] || { echo 'Ghostty revision differs from pin' >&2; exit 1; }
[[ -z "$(git -C "$SOURCE" status --porcelain --untracked-files=no)" ]] || { echo 'Ghostty source has local changes' >&2; exit 1; }
export TRELLIS_ENGINE_SDK="${TRELLIS_ENGINE_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
[[ -d "$TRELLIS_ENGINE_SDK" ]] || { echo "Engine compatibility SDK missing: $TRELLIS_ENGINE_SDK" >&2; exit 1; }
[[ "$(/usr/bin/plutil -extract Version raw "$TRELLIS_ENGINE_SDK/SDKSettings.plist")" == 26.* ]] || { echo "Engine requires a macOS 26 compatibility SDK" >&2; exit 1; }
export PATH="$ROOT/script/engine-toolchain:$PATH"
cd "$SOURCE"
"$ZIG" build --cache-dir .zig-cache-trellis -Doptimize=ReleaseFast -Dsentry=false -Demit-xcframework=true -Demit-macos-app=false -Dxcframework-target=native
