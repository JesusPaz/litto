# Releasing Litto

Versions are explicit tags: `vX.Y.Z-rc.N` for previews (GitHub prerelease), `vX.Y.Z` for stable. Build numbers come from the current minute (`scripts/release/build-number.py`), so every upload is unique.

Artifacts per release: notarized universal `Litto-<tag>-macOS.zip` (and `.dmg` from CI), `SHA256SUMS`, a Mac App Store build and an iPhone build in App Store Connect. Previews (`-rc.N`) upload the iPhone build for internal TestFlight testers only; stable tags upload one that can be submitted to App Review.

## From CI (same path as AFK)

`Release` (GitHub Actions, manual, on `main`) → CI → EAS workflow `.eas/workflows/apple.yml` on a macOS builder → signed, notarized Mac app and DMG + TestFlight upload → GitHub release. `TestFlight internal` uploads only the iPhone build.

One-time setup:

- GitHub: environment `release` with secret `EXPO_TOKEN`.
- EAS project `@jesuspazs-team/litto`, environment `production`: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_BASE64`, `MAC_CERTIFICATE_P12_BASE64` + `MAC_CERTIFICATE_PASSWORD` (Developer ID Application), `IOS_CERTIFICATE_P12_BASE64` + `IOS_CERTIFICATE_PASSWORD` (Apple Distribution). Same certificates as AFK.
- Signing is automatic through the App Store Connect key, which must be allowed to manage profiles: the apps use iCloud (`iCloud.com.jesuspaz.litto`), so Xcode needs iCloud-enabled Developer ID and App Store profiles.

## From a Mac signed into Xcode

```sh
scripts/release/local.sh v0.1.0-rc.1        # mac, ios or all (default)
```

Xcode notarizes the Mac app and uploads the iPhone build with the signed-in account; no API key on disk. The Mac part tags the commit and publishes the GitHub release with the ZIP and checksums. The DMG is CI-only because notarizing it needs `notarytool` credentials.

After publishing, `local.sh` runs `scripts/release/homebrew.sh <tag>`, which opens a PR in [JesusPaz/homebrew-tap](https://github.com/JesusPaz/homebrew-tap) with the cask generated from the published ZIP (`litto@preview` for `-rc.N`, `litto` for stable; they conflict on purpose). Review and merge it by hand. To retry only that step, run the script again with the same tag.

The App Store Connect records for `com.jesuspaz.litto.ios` and `com.jesuspaz.litto.mac` must exist before the first upload; Apple's API cannot create them. `local.sh` exports the Mac archive twice: Developer ID (notarized, for GitHub and Homebrew) and Mac App Store (uploaded). CI (`apple.sh`) still builds only the Developer ID app and internal TestFlight builds.

Store listing, screenshots, privacy policy and review notes: [docs/app-store](app-store/README.md).

## Sandbox

Both Mac executables are sandboxed (the Mac App Store requires it) and share the app group `Y76K9N6M4R.com.jesuspaz.litto`, whose container holds the decks, images, progress and the SwiftData store. The first sandboxed launch of a Release build moves `~/Library/Application Support/Litto` into the app container (`macOS/Migration/container-migration.plist`, which Debug builds leave out so a local run cannot take the data of an installed copy), and `Store.moveLegacyData` moves it on into the group container.

## CloudKit schema

Release builds talk to the CloudKit **Production** environment, which never creates record types by itself: until the schema is deployed there, each device keeps its data and nothing syncs. Whenever a `@Model` changes (and once for a new container):

```sh
scripts/release/cloudkit-schema.sh
```

It pushes the schema to **Development** from a throwaway store (your real data is not touched). Then, in the [CloudKit Console](https://icloud.developer.apple.com), open `iCloud.com.jesuspaz.litto` → Development → **Deploy Schema Changes**. Deployed changes can only add fields and types, never remove them.

