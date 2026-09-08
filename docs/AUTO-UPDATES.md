# Automatic updates

Trellis integrates **Sparkle 2.9.6**, pinned in Xcode and `Package.resolved`. The
standard native updater is retained once by `AppDelegate`; it is never recreated
per window. This was the latest official release checked on 8 September 2026.
[Release](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6),
[checksummed package](https://github.com/sparkle-project/Sparkle/blob/2.9.6/Package.swift).

## App behavior

Settings → Updates shows the installed version, configuration status, last check,
manual **Check for Updates…**, and an automatic-check toggle. The same command is
in the app menu. Automatic checks default off; Sparkle owns their scheduling and
saved preference. Updates always require the user to choose installation.
System profiling is off. `SUAllowsAutomaticUpdates = NO` also prevents Sparkle
from offering unattended installation.
[Preferences](https://sparkle-project.org/documentation/preferences-ui/),
[behavior settings](https://sparkle-project.org/documentation/customization/).

`AppUpdater.start()` validates the final bundle before creating a controller, then
uses `SPUStandardUpdaterController(startingUpdater: false, …)` and the throwing
`controller.updater.start()`. KVO publishers drive menu/Settings availability.
Missing feed and key leave local builds visibly unconfigured, without starting
Sparkle. Partial or malformed configuration produces a visible error. The feed
must be HTTPS without embedded credentials, a query or a fragment; the public key
must be canonical base64 for 32 bytes.
[Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/),
[SPUUpdater API](https://sparkle-project.org/documentation/api-reference/Classes/SPUUpdater.html).

`Trellis/Info.plist` requires signed feeds and archive verification before
extraction. `SUSignedFeedFailureExpirationInterval = 0` keeps a failed feed
signature from becoming acceptable after a timeout. Losing the signing key can
therefore require a manually installed recovery build; keep an offline backup.
Do not edit a generated signed appcast or modify a stapled archive after its
signature is generated. Trellis is not sandboxed; Sparkle's sandbox-only XPC flags
and entitlement exceptions are intentionally absent.
[Security configuration](https://sparkle-project.org/documentation/customization/).

## Quit and restart

The common app termination path handles both ordinary Quit and Sparkle's restart.
It asks before stopping busy terminals, native agent work, running automations or
Dreaming. Cancelling leaves Trellis running. Approved termination saves workspace
identities, cancels and awaits owned agent/scheduler work, then stops terminal
surfaces before allowing the process to exit. Schedulers reject new launches once
shutdown starts. No separate install-on-quit scheduler or force-quit path exists.

Local PTY processes stop. Persistent tmux workloads remain on their host; an
attachment can be reconnected. Restored tabs retain identity and layout but do not
silently rerun commands, start shells or reconnect remote hosts. In-memory chat
content is not a durable terminal snapshot. Automations only run while Trellis is
open; missed runs are skipped rather than replayed. An interrupted saved attempt
is marked uncertain and paused on restart. Validate these behaviors with a real
staging update before public rollout; signature checks alone do not prove them.
Sparkle's optional relaunch-postponement callback is not used as the sole gate,
because it is not invoked for every installation path.
[Delegate lifecycle](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html).

## Release configuration

The Xcode source owns marketing version and build number; personal packaging
preserves both. Increment `CFBundleVersion` for every distributed build. The first
updater-enabled version needs a manual installation. Release builds are optimized
and target Apple Silicon/macOS 27; the generated appcast derives eligibility from
the actual app. Keep the public bundle name `Trellis.app` and identifier
`in.sammyk.trellis` stable.
[Publishing requirements](https://sparkle-project.org/documentation/publishing/).

`script/package-release.sh --preflight` validates input formats, a monotonic build,
private-key file boundaries and local Developer ID availability without building,
notarizing or publishing. Set these inputs in the operator's environment:

| Input | Required value |
| --- | --- |
| `TRELLIS_SIGN_IDENTITY` | Existing `Developer ID Application: …` certificate with private key; Apple Development and ad-hoc identities are rejected. |
| `TRELLIS_NOTARY_PROFILE` | Existing `notarytool` Keychain profile; credentials never appear in arguments. |
| `TRELLIS_UPDATE_FEED_URL` | Stable public HTTPS appcast URL. |
| `TRELLIS_UPDATE_PUBLIC_KEY` | Public Ed25519 key for the final bundle. |
| `TRELLIS_UPDATE_PRIVATE_KEY_FILE` | Matching private-key export, outside the repo, absolute regular file, owner-only permissions, at most 4 KiB. |
| `TRELLIS_RELEASE_TAG` | `vX.Y.Z` matching Xcode, optionally followed by a staging suffix. |
| `TRELLIS_PREVIOUS_BUILD` | Last distributed integer build; use `0` only for the first distribution. |
| `TRELLIS_RELEASE_REPOSITORY` | GitHub `owner/repository`; defaults to the existing remote path `thesammykins/trellis`. This does not establish public visibility. |

Production key creation/export and custody remain explicit operator setup. Use the
pinned Sparkle `generate_keys` tool for production and protect its Keychain/private
export; never commit or place private values in command arguments. The release
script reads the private file through `--ed-key-file`. It does not generate keys,
import credentials, change repository visibility or publish anything.
[Key setup](https://sparkle-project.org/documentation/).

Run `./script/package-release.sh` after configuring inputs. It builds Release into
`.build`, stages a new `dist/releases/<tag>/Trellis.app` without replacing the
running personal app, signs all nested Sparkle helpers/framework and Trellis
executables from the inside out with Developer ID, secure timestamps and hardened
runtime, then notarizes/staples the app and final DMG. It rejects notarization
results other than `Accepted`. Sparkle generates and verifies a signed appcast
with a full DMG and no delta updates; the script verifies a signed enclosure and
archive length, then writes `SHA256SUMS`. It refuses an existing release staging
directory. Inspect a failed directory before moving it aside and retrying.
[Manual nested signing](https://sparkle-project.org/documentation/sandboxing/#code-signing),
[Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

The existing `package-personal.sh` remains local Debug packaging. Shared
`sign-app.sh` now signs Sparkle's nested code as well. Neither the personal package
nor the existing Actions artifact workflow becomes a public notarized release by
virtue of including Sparkle.

## GitHub hosting and staging

A public distribution repository can host both the versioned DMG and `appcast.xml`
as Release assets. The production URL shapes are:

```text
https://github.com/thesammykins/trellis/releases/latest/download/appcast.xml
https://github.com/thesammykins/trellis/releases/download/<tag>/Trellis-<tag>-arm64.dmg
```

Use a separate explicit staging feed for prereleases. The tag workflow publishes the complete final DMG, `appcast.xml` and
`SHA256SUMS` after validation; manual dispatch can prepare a draft first. Keep app/notarization logs and private inputs out of Release assets. Fetch
both feed and archive anonymously after publication; no client token should be
needed. Repository visibility and artifact hosting must be verified independently.
[GitHub release links](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases).

Before enabling public updates:

1. Install signed staging build N normally, then offer N+1 from its staging feed.
   Check manual/automatic checking, no-update, offline and invalid-signature UI.
2. Run a local shell command, agent tool and a fixture automation. Cancel the quit
   prompt during installation and confirm all work remains. Retry, approve, and
   confirm cancellation completes before replacement/relaunch. Repeat from
   Settings and with several windows, a sheet open and a tmux attachment.
3. Confirm version N+1, restored stopped identities/layout, no duplicate or missed
   automation replay, and Keychain/preferences continuity. Validate Gatekeeper
   and stapled tickets on a clean machine, including offline first launch.
4. Preserve rollback assets; a lower build is not a normal Sparkle update. Ship a
   higher recovery build or use a deliberate manual reinstall.

Local checks: `script/check-updates.sh [resolved Sparkle artifact directory]` uses
disposable keys and a fixture app, verifies nested signing and generated feed/
archive signatures, and proves modified feed/archive bytes are rejected. It does
not touch the Keychain, app defaults or running app. `UpdateConfigurationCheck`
and `AutomationScheduleCheck` cover invalid configuration and awaited scheduler
shutdown. The current product status records which notarization, hosted delivery and
install/relaunch checks have actually been completed. See [release setup](GITHUB-RELEASE.md).
