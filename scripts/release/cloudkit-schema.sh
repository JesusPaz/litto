#!/bin/bash
# Pushes the SwiftData model to the CloudKit Development environment.
# Run it whenever a @Model changes, then press "Deploy Schema Changes" in the CloudKit Console
# (iCloud.com.jesuspaz.litto) before releasing: Production never creates record types on its own.
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d "${TMPDIR:-/tmp}/litto-schema.XXXXXX")
trap 'rm -rf "$work"' EXIT
xcodebuild -project apps/apple/Litto.xcodeproj -scheme LittoMac -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath "$work/dd" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build -quiet
LITTO_INIT_CLOUDKIT_SCHEMA=1 "$work/dd/Build/Products/Debug/Litto.app/Contents/MacOS/Litto"
echo 'Now deploy it: CloudKit Console → iCloud.com.jesuspaz.litto → Development → Deploy Schema Changes.'
