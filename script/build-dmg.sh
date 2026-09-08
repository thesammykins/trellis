#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="${TRELLIS_DMG_APP:-$ROOT/dist/Trellis.app}"
DMG="${TRELLIS_DMG_OUTPUT:-$ROOT/dist/Trellis.dmg}"
ASSETS="$ROOT/assets/dmg"
VENV="$ROOT/.build-support/dmg-tools"
PYTHON="$VENV/bin/python"
DMGBUILD="$VENV/bin/dmgbuild"
MOUNT="$(mktemp -d /private/tmp/trellis-dmg.XXXXXX)"
FONT_REGULAR="/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
ATTACHED=0

cleanup() {
  if [[ "$ATTACHED" == 1 ]]; then
    /usr/bin/hdiutil detach "$MOUNT" -quiet || true
  fi
  /bin/rmdir "$MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

[[ -d "$APP" ]] || { echo "Missing built app: $APP. Run ./script/package-personal.sh first." >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"

if ! /usr/bin/command -v magick >/dev/null; then
  echo "ImageMagick is required. Run mise install, then mise exec -- ./script/build-dmg.sh." >&2
  exit 1
fi
[[ -f "$FONT_REGULAR" && -f "$FONT_BOLD" ]] || { echo "Required macOS system fonts are unavailable." >&2; exit 1; }

mkdir -p "$ASSETS" "$ROOT/dist" "$ROOT/.build-support"
if [[ ! -x "$PYTHON" ]]; then
  python3 -c 'import sys; sys.exit("dmgbuild needs Python 3.10 or later on PATH") if sys.version_info < (3, 10) else None'
  python3 -m venv "$VENV"
fi
"$PYTHON" -m pip install --disable-pip-version-check --quiet \
  "dmgbuild==1.6.7" "ds_store==1.3.3" "mac_alias==2.2.3"
[[ "$("$PYTHON" -c 'import dmgbuild; print(dmgbuild.__version__)')" == "1.6.7" ]] || {
  echo "Expected dmgbuild 1.6.7 from PyPI." >&2
  exit 1
}

# 2x source for Finder's 720 x 440 point window. The arrow stays above labels.
magick -size 1440x880 xc:'#e6ece4' \
  -fill '#d7e2d7' -draw 'rectangle 0,0 1439,879' \
  -fill '#1d3531' -font "$FONT_BOLD" -pointsize 58 -gravity NorthWest -annotate +96+72 'Trellis' \
  -fill '#49645d' -font "$FONT_REGULAR" -pointsize 24 -gravity NorthWest -annotate +98+144 'Install the native agent terminal' \
  -stroke '#168b79' -strokewidth 5 -fill none -draw 'line 560,420 878,420' \
  -fill '#168b79' -stroke none -draw 'polygon 878,420 842,398 842,442' \
  -fill '#49645d' -font "$FONT_REGULAR" -pointsize 20 -gravity NorthWest -annotate +96+660 'Drag Trellis to Applications' \
  -units PixelsPerInch -density 144 \
  "$ASSETS/background.png"

rm -f "$DMG"
"$DMGBUILD" -s "$ROOT/script/dmg-settings.py" -D app="$APP" Trellis "$DMG"
/usr/bin/hdiutil verify "$DMG"

/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG" >/dev/null
ATTACHED=1
[[ -d "$MOUNT/Trellis.app" ]] || { echo "DMG is missing Trellis.app." >&2; exit 1; }
# Verify the requested payload, not just the disk image layout. A stale local
# bundle can still be internally signed while being the wrong release.
python3 "$ROOT/script/verify-app-payload.py" "$APP" "$MOUNT/Trellis.app"
/usr/bin/codesign --verify --deep --strict "$MOUNT/Trellis.app"
[[ -L "$MOUNT/Applications" && "$(readlink "$MOUNT/Applications")" == "/Applications" ]] || {
  echo "DMG Applications link is invalid." >&2
  exit 1
}
[[ -f "$MOUNT/.background.png" ]] || { echo "DMG background is missing." >&2; exit 1; }

"$PYTHON" - "$MOUNT/.DS_Store" <<'PY'
import sys
from ds_store import DSStore

with DSStore.open(sys.argv[1], "r") as store:
    app = tuple(store["Trellis.app"]["Iloc"])
    applications = tuple(store["Applications"]["Iloc"])
    view = store["."]["icvp"]
    assert app == (180, 210), app
    assert applications == (540, 210), applications
    assert view["backgroundType"] == 2, view
    assert view["backgroundImageAlias"], view
    assert view["iconSize"] == 112.0, view
    assert view["labelOnBottom"] is True, view
    print(f"Finder layout: Trellis.app={app}, Applications={applications}, "
          f"iconSize={view['iconSize']}, labels=bottom, backgroundType={view['backgroundType']}")
PY

echo "Built and verified: $DMG"
