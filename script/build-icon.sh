#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ICON=.build-support/icon
mkdir -p "$ICON/Trellis.iconset"
if [[ ! -f "$ICON/Trellis.icns" || assets/icon/TrellisIcon.svg -nt "$ICON/Trellis.icns" ]]; then
  qlmanage -t -s 1024 -o "$ICON" assets/icon/TrellisIcon.svg >/dev/null
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON/TrellisIcon.svg.png" --out "$ICON/Trellis.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON/TrellisIcon.svg.png" --out "$ICON/Trellis.iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICON/Trellis.iconset" -o "$ICON/Trellis.icns"
fi
