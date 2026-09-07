# Private builds and installer

Repository: https://github.com/thesammykins/trellis (private).

The manual **Build signed personal DMG** Actions workflow builds only `main` on
GitHub's `xcode-27` Apple Silicon runner. It installs the pinned Ghostty/Zig
engine toolchain, signs with the selected Apple Development identity and uploads
`Trellis-AppleSilicon-personal` as a 14-day Actions artifact. This is a macOS 27
personal testing build, not a notarized public release. The hosted runner builds
against the macOS 27 SDK but currently runs macOS 26; UI dogfood remains local.

Signing material is held in repository secrets `APPLE_DEVELOPMENT_P12_BASE64`
and `APPLE_DEVELOPMENT_P12_PASSWORD`. Only the selected development identity was
exported from the local Keychain. Temporary export files were removed after
upload. Each job imports it into a temporary keychain and deletes that keychain
on completion. Signing never runs for pull requests. Set repository variable `TRELLIS_SIGN_IDENTITY` to the imported certificate
fingerprint. Rotate the secrets and update that variable when the certificate
expires or changes.

Local builds need the Ghostty/Xcode toolchain described in DEPENDENCIES.md,
ImageMagick and Python 3.10 or later on PATH. The workflow installs Python 3.13
and explicitly downloads Apple's Metal compiler component.

Local build:

```sh
TRELLIS_SIGN_IDENTITY="<certificate fingerprint>" ./script/package-personal.sh
./script/build-dmg.sh
```

Quit the personal Trellis app before replacing its bundle. The DMG script uses
ImageMagick and an isolated, pinned dmgbuild environment, then verifies the image,
payload, Applications symlink and Finder icon positions. The 720×440 point window
uses a 2× background; icons are at (180,210) and (540,210), with labels below.

Before making the repository public: choose a source license, review tracked content for personal information and review third-party notices.
Local evidence and historical handoff files are excluded from Git.
Public app distribution additionally needs Developer ID signing, hardened runtime
and notarization; the current development certificate is not that release route.
