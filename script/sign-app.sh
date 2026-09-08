#!/bin/bash
set -euo pipefail

APP="${1:?usage: sign-app.sh /path/to/Trellis.app [local|release]}"
MODE="${2:-local}"
IDENTITY="${TRELLIS_SIGN_IDENTITY:--}"
FLAGS=(--force --sign "$IDENTITY")
case "$MODE" in
  local) FLAGS+=(--timestamp=none) ;;
  release)
    [[ "$IDENTITY" == 'Developer ID Application: '* ]] || {
      echo 'Release signing requires TRELLIS_SIGN_IDENTITY to name a Developer ID Application certificate.' >&2; exit 1;
    }
    FLAGS+=(--timestamp --options runtime)
    ;;
  *) echo 'Expected local or release signing mode.' >&2; exit 2 ;;
esac
[[ -d "$APP" && ! -L "$APP" ]] || { echo "Expected an app directory: $APP" >&2; exit 1; }

# Sparkle's helper code must be re-signed before the containing framework and app.
# CodeSignOnCopy alone does not re-sign these nested services.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$FRAMEWORK" ]]; then
  for component in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
    TARGET="$FRAMEWORK/Versions/B/$component"
    [[ -e "$TARGET" ]] || { echo "Missing Sparkle component: $component" >&2; exit 1; }
    if [[ "$component" == XPCServices/Downloader.xpc ]]; then
      /usr/bin/codesign "${FLAGS[@]}" --preserve-metadata=entitlements "$TARGET"
    else
      /usr/bin/codesign "${FLAGS[@]}" "$TARGET"
    fi
  done
  /usr/bin/codesign "${FLAGS[@]}" "$FRAMEWORK"
fi
for executable in "$APP/Contents/MacOS/"*; do
  [[ -f "$executable" && -x "$executable" ]] || continue
  /usr/bin/codesign "${FLAGS[@]}" "$executable"
done
/usr/bin/codesign "${FLAGS[@]}" "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
