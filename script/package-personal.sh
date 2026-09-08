#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/.build/Build/Products/Debug/TrellisM0.app"
DEST="$ROOT/dist/Trellis.app"
PLIST="$DEST/Contents/Info.plist"

artifact_is_running() {
  local pid executable
  while IFS= read -r pid; do
    executable="$(/bin/ps -p "$pid" -o comm= 2>/dev/null | /usr/bin/sed 's/^[[:space:]]*//' || true)"
    [[ "$executable" == "$DEST/Contents/MacOS/Trellis" ]] && return 0
  done < <(/usr/bin/pgrep -x Trellis || true)
  return 1
}

if artifact_is_running; then
  echo "Refusing to replace the running personal artifact: $DEST" >&2
  exit 1
fi

TRELLIS_BUILD_CONFIGURATION=Debug "$ROOT/script/build_and_run.sh" --build-only
[[ -d "$SOURCE" ]] || { echo "Missing build artifact: $SOURCE" >&2; exit 1; }

if artifact_is_running; then
  echo "Refusing to replace the running personal artifact: $DEST" >&2
  exit 1
fi
if [[ -L "$DEST" ]]; then
  echo "Refusing to replace a symlinked artifact: $DEST" >&2
  exit 1
fi

mkdir -p "$(dirname "$DEST")"
[[ ! -e "$DEST" ]] || rm -rf "$DEST"
ditto "$SOURCE" "$DEST"
mv "$DEST/Contents/MacOS/TrellisM0" "$DEST/Contents/MacOS/Trellis"

python3 - "$PLIST" <<'PLIST_UPDATE'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
with path.open('rb') as handle:
    metadata = plistlib.load(handle)
metadata.update(CFBundleExecutable='Trellis', CFBundleIdentifier='in.sammyk.trellis',
                CFBundleDisplayName='Trellis', CFBundleName='Trellis')
with path.open('wb') as handle:
    plistlib.dump(metadata, handle)
PLIST_UPDATE

"$ROOT/script/sign-app.sh" "$DEST" local

echo "Packaged local Apple Silicon macOS 27 personal-testing artifact: $DEST"
