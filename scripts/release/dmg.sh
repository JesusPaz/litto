#!/bin/bash
set -euo pipefail
app=${1:?Path to the signed Litto.app}
output=${2:?Destination DMG}
test -d "$app/Contents"
test ! -e "$output"
stage=$(mktemp -d "${TMPDIR:-/tmp}/litto-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Litto.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Litto -srcfolder "$stage" -format UDZO "$output"
