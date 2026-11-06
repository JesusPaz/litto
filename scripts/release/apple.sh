#!/bin/bash
set -euo pipefail
# CI release on an ephemeral macOS runner; never on a developer's login keychain.
# Signing is automatic through the App Store Connect API key, so Xcode fetches the
# iCloud-enabled Developer ID and App Store profiles itself.
mode=${1:?mac or ios}
[[ "$mode" == mac || "$mode" == ios ]] || exit 2
: "${RUNNER_TEMP:?}" "${APPLE_TEAM_ID:?}" "${P12_BASE64:?}" "${P12_PASSWORD:?}"
: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_BASE64:?}" "${RELEASE_TAG:?}" "${LITTO_BUILD_NUMBER:?}"
version=$(python3 scripts/release/version.py "$RELEASE_TAG" | sed -n 's/^version=//p')
build=$LITTO_BUILD_NUMBER
work=$(mktemp -d "$RUNNER_TEMP/litto-signing.XXXXXX")
keychain="$work/signing.keychain-db"
cleanup() {
    security delete-keychain "$keychain" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT
umask 077
export SIGNING_WORK="$work"
python3 - <<'PY'
import base64, os
from pathlib import Path
p = Path(os.environ['SIGNING_WORK'])
for name, variable in [('certificate.p12', 'P12_BASE64'), ('AuthKey.p8', 'ASC_KEY_BASE64')]:
    (p / name).write_bytes(base64.b64decode(os.environ[variable], validate=True))
PY
password=$(openssl rand -hex 24)
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$work/certificate.p12" -k "$keychain" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
auth=(-allowProvisioningUpdates -authenticationKeyPath "$work/AuthKey.p8" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
args=(-project apps/apple/Litto.xcodeproj -configuration Release -archivePath "$work/Litto.xcarchive"
    -derivedDataPath "$work/build" -skipPackagePluginValidation "${auth[@]}"
    "DEVELOPMENT_TEAM=$APPLE_TEAM_ID" "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build"
    "OTHER_CODE_SIGN_FLAGS=--keychain $keychain")
if [[ "$mode" == mac ]]; then
    xcodebuild "${args[@]}" -scheme LittoMac -destination 'generic/platform=macOS' 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive
    python3 scripts/release/export-options.py mac export "$work/ExportOptions.plist"
else
    xcodebuild "${args[@]}" -scheme LittoiOS -destination 'generic/platform=iOS' archive
    python3 scripts/release/export-options.py ios upload "$work/ExportOptions.plist"
fi
xcodebuild -exportArchive -archivePath "$work/Litto.xcarchive" -exportPath "$work/export" \
    -exportOptionsPlist "$work/ExportOptions.plist" "${auth[@]}"
[[ "$mode" == mac ]] || exit 0

app="$work/export/Litto.app"
codesign --verify --deep --strict "$app"
python3 -c 'import sys; assert set(sys.argv[1].split()) == {"arm64", "x86_64"}, "Mac archive must be universal"' "$(xcrun lipo -archs "$app/Contents/MacOS/Litto")"
notary=(--key "$work/AuthKey.p8" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait --output-format json)
ditto -c -k --keepParent "$app" "$work/notarize.zip"
xcrun notarytool submit "$work/notarize.zip" "${notary[@]}" > "$work/notary.json"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted", "Notarization rejected"' "$work/notary.json"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute "$app"
mkdir -p dist
ditto -c -k --keepParent "$app" "dist/Litto-$RELEASE_TAG-macOS.zip"
dmg="dist/Litto-$RELEASE_TAG-macOS.dmg"
bash scripts/release/dmg.sh "$app" "$dmg"
codesign --sign 'Developer ID Application' --keychain "$keychain" --timestamp "$dmg"
xcrun notarytool submit "$dmg" "${notary[@]}" > "$work/dmg-notary.json"
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "Accepted", "DMG notarization rejected"' "$work/dmg-notary.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
(cd dist && shasum -a 256 "Litto-$RELEASE_TAG-macOS.zip" "Litto-$RELEASE_TAG-macOS.dmg" > SHA256SUMS)
