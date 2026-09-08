#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE="${1:-$ROOT/.build/SourcePackages/artifacts/sparkle/Sparkle}"
FRAMEWORK="$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
BIN="$SPARKLE/bin"
[[ -d "$FRAMEWORK" && -x "$BIN/generate_appcast" && -x "$BIN/sign_update" ]] || {
  echo 'Resolve the pinned Sparkle package first, or pass its artifact directory.' >&2; exit 1;
}
FIXTURE="$(mktemp -d /private/tmp/trellis-update-check.XXXXXX)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/Trellis.app/Contents/MacOS" "$FIXTURE/Trellis.app/Contents/Frameworks" "$FIXTURE/archives"
xcrun swiftc -swift-version 6 -parse-as-library "$ROOT/Checks/UpdateSigningFixture.swift" -o "$FIXTURE/create-fixture"
"$FIXTURE/create-fixture" "$FIXTURE"
cp /usr/bin/true "$FIXTURE/Trellis.app/Contents/MacOS/Trellis"
ditto "$FRAMEWORK" "$FIXTURE/Trellis.app/Contents/Frameworks/Sparkle.framework"
TRELLIS_SIGN_IDENTITY=- "$ROOT/script/sign-app.sh" "$FIXTURE/Trellis.app" local
ditto -c -k --sequesterRsrc --keepParent "$FIXTURE/Trellis.app" "$FIXTURE/archives/Trellis.zip"
"$BIN/generate_appcast" --ed-key-file "$FIXTURE/fixture-private-key" --maximum-deltas 0 \
  --download-url-prefix https://example.com/fixture/ -o "$FIXTURE/archives/appcast.xml" "$FIXTURE/archives"
"$BIN/sign_update" --verify --ed-key-file "$FIXTURE/fixture-private-key" "$FIXTURE/archives/appcast.xml"
SIGNATURE="$(python3 - "$FIXTURE/archives/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
enclosure = root.find('./channel/item/enclosure')
assert enclosure is not None
print(enclosure.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'])
PY
)"
"$BIN/sign_update" --verify --ed-key-file "$FIXTURE/fixture-private-key" "$FIXTURE/archives/Trellis.zip" "$SIGNATURE"
python3 - "$FIXTURE/archives" <<'PY'
import pathlib, sys
folder = pathlib.Path(sys.argv[1])
feed = folder / 'appcast.xml'
original = feed.read_bytes()
changed = original.replace(b'Trellis', b'Tampered', 1)
assert original != changed
feed.write_bytes(changed)
with (folder / 'Trellis.zip').open('ab') as handle: handle.write(b'tampered')
PY
if "$BIN/sign_update" --verify --ed-key-file "$FIXTURE/fixture-private-key" "$FIXTURE/archives/appcast.xml" >/dev/null 2>&1; then
  echo 'FAIL: modified feed signature was accepted.' >&2; exit 1
fi
if "$BIN/sign_update" --verify --ed-key-file "$FIXTURE/fixture-private-key" "$FIXTURE/archives/Trellis.zip" "$SIGNATURE" >/dev/null 2>&1; then
  echo 'FAIL: modified archive signature was accepted.' >&2; exit 1
fi
echo 'PASS update signing: nested app signatures, generated signed feed/archive, tampered feed/archive rejected; disposable fixture removed.'
