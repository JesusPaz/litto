#!/bin/bash
# Release from a Mac signed into Xcode with the Litto team, without API keys:
# Xcode notarizes the Mac app and uploads the iPhone build to TestFlight.
#   scripts/release/local.sh v0.1.0-rc.1 [mac|ios|all]
set -euo pipefail
tag=${1:?vX.Y.Z or vX.Y.Z-rc.N}
platform=${2:-all}
cd "$(dirname "$0")/../.."
version=$(python3 scripts/release/version.py "$tag" | sed -n 's/^version=//p')
build=$(python3 scripts/release/build-number.py)
test -z "$(git status --porcelain)" || { echo 'Release requires a clean tree' >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/litto-release.XXXXXX")
trap 'rm -rf "$work"' EXIT
common=(-project apps/apple/Litto.xcodeproj -configuration Release -derivedDataPath "$work/dd" -allowProvisioningUpdates
    "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build")
echo "Litto $tag, build $build, source $(git rev-parse HEAD)"

if [[ "$platform" != ios ]]; then
    xcodebuild "${common[@]}" -scheme LittoMac -destination 'generic/platform=macOS' -archivePath "$work/mac.xcarchive" \
        'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive -quiet
    python3 scripts/release/export-options.py mac upload "$work/mac.plist"
    xcodebuild -exportArchive -archivePath "$work/mac.xcarchive" -exportPath "$work/mac-upload" \
        -exportOptionsPlist "$work/mac.plist" -allowProvisioningUpdates -quiet
    echo 'Waiting for notarization…'
    for _ in $(seq 1 60); do
        if xcodebuild -exportNotarizedApp -archivePath "$work/mac.xcarchive" -exportPath "$work/mac" >/dev/null 2>&1; then break; fi
        sleep 30
    done
    app="$work/mac/Litto.app"
    xcrun stapler validate "$app"
    spctl --assess --type execute "$app"
    python3 -c 'import sys; assert set(sys.argv[1].split()) == {"arm64", "x86_64"}, "Mac app must be universal"' "$(xcrun lipo -archs "$app/Contents/MacOS/Litto")"
    rm -rf dist && mkdir -p dist
    ditto -c -k --keepParent "$app" "dist/Litto-$tag-macOS.zip"
    (cd dist && shasum -a 256 "Litto-$tag-macOS.zip" > SHA256SUMS)
fi

if [[ "$platform" != mac ]]; then
    xcodebuild "${common[@]}" -scheme LittoiOS -destination 'generic/platform=iOS' -archivePath "$work/ios.xcarchive" archive -quiet
    python3 scripts/release/export-options.py ios upload "$work/ios.plist"
    xcodebuild -exportArchive -archivePath "$work/ios.xcarchive" -exportPath "$work/ios-upload" \
        -exportOptionsPlist "$work/ios.plist" -allowProvisioningUpdates -quiet
    echo "Uploaded iPhone build $build to TestFlight."
fi

if [[ "$platform" != ios ]]; then
    commit=$(git rev-parse HEAD)
    git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1 || git tag -a "$tag" "$commit" -m "Litto $tag"
    git push origin "refs/tags/$tag"
    flags=(--latest)
    [[ "$tag" != *-rc.* ]] || flags=(--prerelease --latest=false)
    gh release create "$tag" --verify-tag --generate-notes --title "Litto $tag" "${flags[@]}" dist/*
fi
