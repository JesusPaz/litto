# Releasing Litto

Versions are explicit tags: `vX.Y.Z-rc.N` for previews (GitHub prerelease), `vX.Y.Z` for stable. Build numbers come from the current minute (`scripts/release/build-number.py`), so every upload is unique.

Artifacts per release: notarized universal `Litto-<tag>-macOS.zip` (and `.dmg` from CI), `SHA256SUMS`, and an iPhone build on TestFlight (internal testers).

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

The App Store Connect record for `com.jesuspaz.litto.ios` must exist before the first TestFlight upload; Apple's API cannot create it.
