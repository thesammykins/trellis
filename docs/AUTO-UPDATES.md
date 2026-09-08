# Automatic updates for public releases

Research checked **8 September 2026**. Recommendation only: no updater dependency,
feed, signing key or publishing workflow was added.

## Recommendation

Use **Sparkle 2**, pinned through Xcode’s Swift Package Manager integration. Its
standard native updater fits Trellis’s SwiftUI/AppKit application and regular app
bundle. The official latest release checked was **2.9.6**, including installer
security fixes; recheck before implementation. Its package supplies a checksummed
binary framework. [Release](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6),
[package manifest](https://github.com/sparkle-project/Sparkle/blob/2.9.6/Package.swift).

The first implementation should automatically **check** when enabled, then let the
user install and restart deliberately. Use Sparkle’s standard permission prompt
and update window. Set `SUAllowsAutomaticUpdates = NO` initially so unattended
installation cannot surprise a terminal user. Leave system profiling off. Sparkle
owns scheduling; no Trellis cron, polling loop or custom installer is needed.
[Update behavior](https://sparkle-project.org/documentation/customization/).

## Current repository prerequisites

Source inspection found:

| Current state | Work required before public updates |
| --- | --- |
| Xcode declares **0.3.3 / build 6**; `package-personal.sh` now preserves those versions. | Keep `CFBundleVersion` increasing for every distributed build. The first updater-enabled version needs a normal manual installation. |
| `build_and_run.sh` builds Debug with `CODE_SIGNING_ALLOWED=NO`, then adds helpers/resources and signs afterward. | Establish an archive/export release path containing the real `in.sammyk.trellis` bundle, helpers and resources before final signing. |
| Personal packaging uses ad-hoc or Apple Development signing, `--timestamp=none`, and no hardened-runtime configuration. | Developer ID Application signing, secure timestamps, hardened runtime, notarization and stapling. |
| Signing loops cover `Contents/MacOS` and the outer app. | Include Sparkle’s nested framework/helper code in the release signing process. Outer-bundle verification alone is insufficient. |
| `.github/workflows/package.yml` uploads a 14-day Actions artifact. | Publish durable, anonymously downloadable release assets and a feed. No claim about current repository visibility is needed. |
| No Sparkle package, updater object, `SUFeedURL` or `SUPublicEDKey` exists. | Add these only after choosing the release identity/feed and signing-key custody. |

See [personal builds](PERSONAL-BUILD.md), [release boundaries](GITHUB-RELEASE.md),
[packaging script](../script/package-personal.sh) and
[Xcode configuration](../Trellis.xcodeproj/project.pbxproj). Source-license,
tracked-content and third-party-notice review remain public-release prerequisites.
Trellis currently targets Apple Silicon/macOS 27; the feed must preserve that
eligibility instead of implying support for older systems.

## Small native integration

Retain **one** `SPUStandardUpdaterController` for the app lifetime in the existing
`AppDelegate`, on the main actor. Initialize it with
`startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil`, then call
`startUpdater()` after launch setup. This uses Sparkle’s standard UI while allowing
the existing delegate to coordinate shutdown. Do not create an updater per window
or in recomputed view bodies.

Add **Check for Updates…** after `.appInfo` in SwiftUI Commands; invoke
`updater.checkForUpdates()`. Observe the KVO-compliant `canCheckForUpdates` to keep
the menu enabled state current. These are the current documented programmatic
APIs, not legacy `SUUpdater` calls. [SwiftUI/AppKit setup](https://sparkle-project.org/documentation/programmatic-setup/).

An Updates section in existing Settings needs the current version, Check for
Updates and **Automatically check for updates**. Bind changes to
`SPUUpdater.automaticallyChecksForUpdates`; Sparkle already persists this preference.
Do not maintain another defaults key or reset it at launch.
[Settings integration](https://sparkle-project.org/documentation/preferences-ui/).

Embed/sign the framework and set `SUFeedURL` plus `SUPublicEDKey` in the final
public bundle. Development builds must use a separate staging feed or leave the
updater stopped. Trellis is not sandboxed: do not enable Sparkle’s sandbox-only
XPC service flags or add their entitlement exceptions.
[Framework setup](https://sparkle-project.org/documentation/),
[sandbox applicability and nested signing](https://sparkle-project.org/documentation/sandboxing/).

## GitHub hosting and release sequence

The smallest hosting arrangement is a public GitHub distribution repository with
both the versioned DMG and `appcast.xml` attached to each Release. Proposed URL
shapes, **not deployed endpoints**:

```text
SUFeedURL:
https://github.com/<owner>/<distribution-repo>/releases/latest/download/appcast.xml

Versioned enclosure:
https://github.com/<owner>/<distribution-repo>/releases/download/<tag>/Trellis-<version>-arm64.dmg
```

GitHub documents the stable `latest/download/<asset>` route. Keep each enclosure
pinned to its release tag, not `latest`, so its bytes match its signature. Upload
all assets to a draft Release, verify them, then publish and mark the intended
stable release Latest. Every such release must contain `appcast.xml`. Keep staging
and beta feeds separate. No GitHub token belongs in the app.
[Release links](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases).

If independent feed updates or multiple channels later justify them, host the feed
at a stable HTTPS GitHub Pages URL and leave binaries in Releases. Pages is static
hosting; it is unnecessary for the first single-channel implementation.
[Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages).

Release order:

1. Build the final release app, sign nested code and the app, notarize and staple.
2. Create the DMG, sign/notarize/staple that final distribution as appropriate;
   retain the existing Applications-link/Finder checks. Archive the same app name
   and preserve framework symlinks.
3. Run the pinned Sparkle `generate_appcast` over a staging folder containing the
   final DMG and matching release notes. Use `--download-url-prefix` and
   `--release-notes-url-prefix` with the **versioned release URL**, and
   `--maximum-deltas 0` for the first pass. Inspect generated build/version,
   `minimumSystemVersion` (`27.0.0`), hardware (`arm64`), enclosure size and EdDSA
   signature. Keep previous signed appcast entries when preparing later releases.
4. Publish only after staging acceptance. Never change DMG bytes after signing the
   update archive; regenerate signatures after changing a signed feed or notes.

The generator supports these options and infers OS/hardware requirements from the
bundle. [Pinned generator source](https://github.com/sparkle-project/Sparkle/blob/2.9.6/generate_appcast/main.swift).
DMGs, version metadata and system/hardware eligibility are supported by Sparkle’s
[publication format](https://sparkle-project.org/documentation/publishing/).

## Signing and custody

Sparkle’s Ed25519 key authenticates update archives independently of Apple code
signing. Generate it once with Sparkle’s `generate_keys`; retain the private key
in the release operator’s Keychain and keep an encrypted recovery backup. Only
`SUPublicEDKey` belongs in the app/repository. A release-only CI environment can
supply the private key through a protected file or `--ed-key-file -` standard input;
never a command-line key value, log, artifact or pull-request job.
[Key setup/recovery](https://sparkle-project.org/documentation/),
[current signing input](https://github.com/sparkle-project/Sparkle/blob/2.9.6/generate_appcast/main.swift).

For the first public feed, recommend `SUVerifyUpdateBeforeExtraction = YES` and
`SURequireSignedFeed = YES`. The latter also signs/validates appcasts and notes.
Decide the documented signed-feed recovery policy before launch: failures expire
after 20 days by default; `SUSignedFeedFailureExpirationInterval = 0` disables that
fallback. Pre-extraction verification makes EdDSA-key rotation depend on a
Developer-ID-signed DMG. Do not rotate Apple and EdDSA identities together.
[Security settings](https://sparkle-project.org/documentation/customization/),
[key rotation](https://sparkle-project.org/documentation/#rotating-signing-keys).

Use Developer ID Application, not the current development identity. Apple requires
valid executable signatures, hardened runtime, secure timestamps and no enabled
`get-task-allow` for notarization. Prefer Xcode archive/export, which handles
Sparkle’s nested code; a custom signer must follow the framework’s explicit
inside-out process rather than `codesign --deep` signing. Use current `notarytool`
and `stapler`, inspect the notary log, and validate the delivered artifact.
[Apple requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[Sparkle signing](https://sparkle-project.org/documentation/sandboxing/#code-signing).

## Protect live work on installation

An app replacement/relaunch cannot preserve Trellis-owned Ghostty surfaces and
local PTYs. Local shells, foreground CLI agents and native agent tasks stop;
tmux-backed workloads can persist while attachments disconnect. Restored metadata
must not be presented as a restored live process.

The current `applicationShouldTerminate` consults workspace chat/Ghostty activity;
it does **not** include active Automations or Dreaming. `applicationWillTerminate`
cancels both schedulers and shuts down workspaces. Therefore, before wiring an
updater, extend the existing quit path to include all active work, persist state,
and let the user cancel installation without stopping anything. Reuse that path
for ordinary quit and updater-requested termination. Quiesce scheduler launches
while an approved shutdown is in progress; do not persistently pause schedules
merely because an update was found.
[App lifecycle](../Trellis/TrellisApp.swift),
[workspace ownership](../Trellis/Workspace.swift),
[automation recovery](../Trellis/AutomationScheduler.swift).

Sparkle documents
`updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)` for delaying
relaunch until cleanup finishes. It is **not called in every installation path**,
so it supplements rather than replaces the common quit gate. Release its handler
only after approved shutdown is ready. Do not infer that
`updaterShouldRelaunchApplication(_:)` cancels installation: it governs relaunch.
[Delegate contracts](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html).

## Minimum staging acceptance

Use two genuine signed/notarized builds with increasing build numbers, an isolated
staging app identity/feed and fixture projects. Do not rewrite the installed
personal bundle’s version or change its defaults to simulate this.

- Exercise automatic-check opt-in, manual check, no update, newer update, network
  failure, cancellation, download, installation and launch from `/Applications`.
- Reject a modified archive, invalid signature/feed, incompatible OS/architecture
  and wrong bundle identity. Keep a known-good previous installer for recovery.
- With live local shells, split panes, an agent awaiting approval and a running
  automation/Dreaming task, cancel installation and prove work continues. Then
  approve shutdown; verify cleanup, one relaunch, truthful stopped-session state
  and no schedule replay. Include a fixture tmux attachment.
- Check the downloaded bytes independently, verify nested signatures, stapling
  and Gatekeeper assessment, and inspect Sparkle Console logs. Test from a mounted
  DMG too: the app should guide installation into Applications, not imply an
  in-place update succeeded on a read-only image.

**Next bounded implementation:** approve release identity/feed and key-recovery
policy; build one updater-enabled staging app with the common quit gate and one
signed two-version upgrade proof. Public publishing remains a separate action.
