#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="${1:-run}"
CONFIGURATION="${TRELLIS_BUILD_CONFIGURATION:-Debug}"
case "$CONFIGURATION" in Debug|Release) ;; *) echo 'TRELLIS_BUILD_CONFIGURATION must be Debug or Release.' >&2; exit 2 ;; esac
case "$MODE" in run|--build-only|--verify|--debug|--logs|--telemetry) ;; *) echo "usage: $0 [--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;; esac
# Dedicated development executable; production packaging uses a separate identity.
if [[ "$MODE" != --build-only ]] && pgrep -x TrellisM0 >/dev/null; then
  pkill -TERM -x TrellisM0
fi
./script/build-engine.sh
xcrun swiftc -swift-version 6 Helpers/SessionLaunch.swift -o .build-support/SessionLaunch
xcrun swiftc -swift-version 6 Trellis/MemoryStore.swift Helpers/MemoryBridge.swift -o .build-support/MemoryBridge
xcodebuild -project Trellis.xcodeproj -scheme TrellisM0 -configuration "$CONFIGURATION" \
  -derivedDataPath .build -arch arm64 CODE_SIGNING_ALLOWED=NO \
  "TRELLIS_UPDATE_FEED_URL=${TRELLIS_UPDATE_FEED_URL:-}" \
  "TRELLIS_UPDATE_PUBLIC_KEY=${TRELLIS_UPDATE_PUBLIC_KEY:-}" build
APP="$ROOT/.build/Build/Products/$CONFIGURATION/TrellisM0.app"
mkdir -p "$APP/Contents/Resources"
cp .build-support/SessionLaunch "$APP/Contents/MacOS/SessionLaunch"
cp .build-support/MemoryBridge "$APP/Contents/MacOS/MemoryBridge"
ditto assets/harnesses "$APP/Contents/Resources/harnesses"
cp Trellis/terminal.config "$APP/Contents/Resources/terminal.config"
ditto .build-support/ghostty/zig-out/share/ghostty "$APP/Contents/Resources/ghostty"
ditto .build-support/ghostty/zig-out/share/terminfo "$APP/Contents/Resources/terminfo"
./script/build-icon.sh
cp .build-support/icon/Trellis.icns "$APP/Contents/Resources/Trellis.icns"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile Trellis' "$APP/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string Trellis' "$APP/Contents/Info.plist"
cp Vendor/Ghostty/LICENSE "$APP/Contents/Resources/Ghostty-LICENSE"
cp LICENSE "$APP/Contents/Resources/Trellis-LICENSE"
cp .build/SourcePackages/checkouts/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE"
"$ROOT/script/sign-app.sh" "$APP" local
case "$MODE" in
  --build-only) echo "$APP" ;;
  --debug) lldb -- "$APP/Contents/MacOS/TrellisM0" ;;
  --logs|--telemetry)
    open -n "$APP"
    /usr/bin/log stream --info --style compact --predicate 'process == "TrellisM0"'
    ;;
  --verify)
    open -n "$APP"
    sleep 2
    pgrep -x TrellisM0
    ;;
  run) open -n "$APP" ;;
esac
