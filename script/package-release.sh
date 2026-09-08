#!/bin/bash
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="${1:-build}"
case "$MODE" in build|--preflight) ;; *) echo "usage: $0 [--preflight]" >&2; exit 2 ;; esac

# No key generation, credential import, repository changes or publishing happen here.
for name in TRELLIS_SIGN_IDENTITY TRELLIS_NOTARY_PROFILE TRELLIS_UPDATE_FEED_URL TRELLIS_UPDATE_PUBLIC_KEY TRELLIS_UPDATE_PRIVATE_KEY_FILE TRELLIS_RELEASE_TAG TRELLIS_PREVIOUS_BUILD; do
  [[ -n "${!name:-}" ]] || { echo "Missing release input: $name. See docs/AUTO-UPDATES.md." >&2; exit 1; }
done
export TRELLIS_RELEASE_REPOSITORY="${TRELLIS_RELEASE_REPOSITORY:-thesammykins/trellis}"
python3 - "$ROOT" <<'PY'
import base64, os, pathlib, re, stat, sys, urllib.parse
root = pathlib.Path(sys.argv[1])
def require(value, message):
    if not value: raise SystemExit(message)
env = os.environ
repo = env['TRELLIS_RELEASE_REPOSITORY']
tag = env['TRELLIS_RELEASE_TAG']
require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo), 'Invalid release repository; expected owner/repository.')
require(re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?', tag), 'Invalid release tag; expected vX.Y.Z or vX.Y.Z-suffix.')
feed = env['TRELLIS_UPDATE_FEED_URL']
url = urllib.parse.urlsplit(feed)
require(len(feed.encode()) <= 2048 and url.scheme == 'https' and url.hostname and not url.username and not url.password and not url.query and not url.fragment and not any(c.isspace() for c in feed), 'The feed must be a public HTTPS URL without credentials, query, or fragment.')
try: key = base64.b64decode(env['TRELLIS_UPDATE_PUBLIC_KEY'], validate=True)
except ValueError: raise SystemExit('The public Ed25519 key is not valid base64.')
require(len(key) == 32 and base64.b64encode(key).decode() == env['TRELLIS_UPDATE_PUBLIC_KEY'], 'The public Ed25519 key must be canonical base64 encoding 32 bytes.')
secret = pathlib.Path(env['TRELLIS_UPDATE_PRIVATE_KEY_FILE'])
require(secret.is_absolute() and secret.exists() and not secret.is_symlink(), 'The private key must be an existing absolute regular file, not a symlink.')
info = secret.stat()
require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= 4096 and info.st_mode & 0o077 == 0, 'The private key must be a bounded regular file accessible only to its owner (chmod 600).')
require(not secret.resolve().is_relative_to(root.resolve()), 'Keep the private signing key outside the repository.')
project = (root / 'Trellis.xcodeproj/project.pbxproj').read_text()
versions = set(re.findall(r'MARKETING_VERSION = ([^;]+);', project))
builds = set(re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', project))
require(len(versions) == len(builds) == 1, 'Build configurations must share one release version/build.')
version, build = next(iter(versions)), next(iter(builds))
require(tag == 'v' + version or tag.startswith('v' + version + '-'), 'Release tag does not match the Xcode marketing version.')
require(build.isdigit() and env['TRELLIS_PREVIOUS_BUILD'].isdigit() and int(build) > int(env['TRELLIS_PREVIOUS_BUILD']), 'CFBundleVersion must exceed TRELLIS_PREVIOUS_BUILD, the last distributed build.')
require(env['TRELLIS_SIGN_IDENTITY'].startswith('Developer ID Application: '), 'Release signing requires a Developer ID Application certificate.')
require(not (root / 'dist/releases' / tag).exists(), 'This release staging directory already exists; choose a new build/tag or inspect and move it yourself.')
print('Release input format and monotonic build checks passed.')
PY
IDENTITIES="$(/usr/bin/security find-identity -p codesigning -v)"
[[ "$IDENTITIES" == *"\"$TRELLIS_SIGN_IDENTITY\""* ]] || {
  echo 'The configured Developer ID Application identity is not available in the local Keychain.' >&2; exit 1;
}
if [[ "$MODE" == --preflight ]]; then
  echo 'Preflight passed. Signing-key match and notarization are checked during preparation; public feed availability still requires staging verification.'
  exit 0
fi

TRELLIS_BUILD_CONFIGURATION=Release "$ROOT/script/build_and_run.sh" --build-only
STAGING="$ROOT/dist/releases/$TRELLIS_RELEASE_TAG"
mkdir -p "$STAGING"
APP="$STAGING/Trellis.app"
ditto "$ROOT/.build/Build/Products/Release/TrellisM0.app" "$APP"
mv "$APP/Contents/MacOS/TrellisM0" "$APP/Contents/MacOS/Trellis"
python3 - "$APP/Contents/Info.plist" <<'PY'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
with path.open('rb') as handle: info = plistlib.load(handle)
info.update(CFBundleExecutable='Trellis', CFBundleIdentifier='in.sammyk.trellis', CFBundleDisplayName='Trellis', CFBundleName='Trellis')
with path.open('wb') as handle: plistlib.dump(info, handle)
PY
"$ROOT/script/sign-app.sh" "$APP" release

notarize() {
  local artifact="$1" result="$2"
  local notary_args=(--keychain-profile "$TRELLIS_NOTARY_PROFILE")
  if [[ -n "${TRELLIS_NOTARY_KEYCHAIN:-}" ]]; then notary_args+=(--keychain "$TRELLIS_NOTARY_KEYCHAIN"); fi
  xcrun notarytool submit "$artifact" "${notary_args[@]}" --wait --output-format json > "$result"
  python3 - "$result" <<'PY'
import json, sys
with open(sys.argv[1]) as handle: result = json.load(handle)
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Inspect the local result and fetch the notarytool log before continuing.')
print('Notarization accepted.')
PY
}

# Staple the app first, then the final DMG. Never change either artifact after signing its feed entry.
ZIP="$STAGING/Trellis-notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
notarize "$ZIP" "$STAGING/app-notarization.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm "$ZIP"
DMG="$STAGING/Trellis-$TRELLIS_RELEASE_TAG-arm64.dmg"
TRELLIS_DMG_APP="$APP" TRELLIS_DMG_OUTPUT="$DMG" "$ROOT/script/build-dmg.sh"
codesign --force --sign "$TRELLIS_SIGN_IDENTITY" --timestamp "$DMG"
notarize "$DMG" "$STAGING/dmg-notarization.json"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=2 "$APP"

SPARKLE_BIN="$ROOT/.build/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || { echo 'The pinned Sparkle generate_appcast tool is missing from the resolved package.' >&2; exit 1; }
"$SPARKLE_BIN/generate_appcast" --ed-key-file "$TRELLIS_UPDATE_PRIVATE_KEY_FILE" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/$TRELLIS_RELEASE_REPOSITORY/releases/download/$TRELLIS_RELEASE_TAG/" \
  -o "$STAGING/appcast.xml" "$STAGING"
"$SPARKLE_BIN/sign_update" --verify --ed-key-file "$TRELLIS_UPDATE_PRIVATE_KEY_FILE" "$STAGING/appcast.xml"
python3 - "$STAGING/appcast.xml" "$DMG" <<'PY'
import pathlib, sys, xml.etree.ElementTree as ET
feed, dmg = map(pathlib.Path, sys.argv[1:])
root = ET.parse(feed).getroot()
items = root.findall('./channel/item')
if len(items) != 1: raise SystemExit('Expected exactly one full update in this release feed.')
enclosure = items[0].find('enclosure')
signature = '{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'
if enclosure is None or not enclosure.get(signature) or int(enclosure.get('length', '0')) != dmg.stat().st_size:
    raise SystemExit('The generated feed is missing a signed enclosure or has an incorrect archive length. Check signing-key match.')
print('Signed update enclosure verified.')
PY
(cd "$STAGING" && shasum -a 256 "$(basename "$DMG")" appcast.xml > SHA256SUMS)
echo "Release assets prepared in $STAGING. Nothing was published. Upload only the DMG, appcast.xml and SHA256SUMS after staging verification."
