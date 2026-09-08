# Releases and GitHub Actions

Public releases contain a notarized Apple Silicon DMG, a signed Sparkle appcast and
SHA256SUMS. The app targets macOS 27; source builds require Xcode 27. GitHub's
`xcode-27` runner builds the app; native UI dogfood is performed on macOS 27 locally.

## Publish a version

1. Update the Xcode marketing version and integer build number, plus CHANGELOG.md.
2. Run the relevant checks and dogfood the packaged app. Commit the result to main.
3. Push main, then a matching `vX.Y.Z` tag. The **Signed release** workflow verifies
   that the commit belongs to main, the version matches, and the build exceeds the
   latest published appcast. Existing releases/drafts are never overwritten.
4. The workflow builds, signs and notarizes the app and DMG, staples both, verifies
   signatures and checksums, and publishes all three assets together. The latest
   release's appcast becomes the update feed.

Manual dispatch on main can prepare artifacts and optionally create a draft before
publication. Inspect a failed run before retrying; delete or finish an existing
draft deliberately rather than rebuilding different bytes under the same version.
The first updater-enabled build requires a manual installation.

## Credentials

Use a GitHub environment named `release`, restricted to main and version tags.
Signing is never available to pull request jobs. Its secrets are:

- `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD`
- `SPARKLE_ED25519_PRIVATE_KEY`
- `ASC_NOTARY_KEY_ID`, `ASC_NOTARY_ISSUER_ID`, `ASC_NOTARY_PRIVATE_KEY_P8`

Use a dedicated Apple Developer ID Application identity and a dedicated Apple API
key. The API key's Developer role has team-wide Apple access; it is not limited to
notarization. Keep an offline backup and revoke/rotate the dedicated key if needed.
Do not reuse unrelated application credentials.

Repository variables provide public configuration:
`TRELLIS_RELEASE_SIGN_IDENTITY`, `TRELLIS_UPDATE_PUBLIC_KEY` and
`TRELLIS_UPDATE_FEED_URL`. Keep the Sparkle public key stable across releases.

The credential wrapper imports secrets into an isolated runner keychain, stores a
notarytool profile there, and removes the original secret environment before the
build. Private temporary files and the keychain are removed on exit. The publishing
job receives verified public assets and a write token; it receives no signing keys.
Never upload the staged app's notarization logs or private signing material.

The workflow installs `mise.lock` with a pinned mise action and an isolated config
directory. Contributors use the same `mise.toml` tools. Local `mise run package`
creates ad-hoc signed builds without release credentials. The former private
Apple Development workflow has been retired; public delivery uses this release
pipeline.

## Verify delivery

Download the DMG and appcast anonymously after publication. Verify SHA256SUMS,
Gatekeeper assessment and stapled tickets. Test a real Sparkle install/relaunch
from an older updater-enabled build, including cancellation while work is active
and restoration of stopped sessions. Keep earlier artifacts for manual recovery;
Sparkle does not normally downgrade build numbers.

[Automatic updates](AUTO-UPDATES.md) documents local release inputs, signature
checks, quit behavior and the staging checklist. [Dependencies](DEPENDENCIES.md)
documents build requirements. Generated artifacts and machine-specific evidence
are excluded from Git.
