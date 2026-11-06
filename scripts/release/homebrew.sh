#!/bin/bash
# Open a PR in JesusPaz/homebrew-tap with the cask of a published release.
#   scripts/release/homebrew.sh v0.1.0-rc.2
set -euo pipefail
tag=${1:?vX.Y.Z or vX.Y.Z-rc.N}
cd "$(dirname "$0")/../.."
work=$(mktemp -d "${TMPDIR:-/tmp}/litto-tap.XXXXXX")
trap 'rm -rf "$work"' EXIT
gh release download "$tag" -R JesusPaz/litto -p "Litto-$tag-macOS.zip" -D "$work"
[[ "$tag" == *-rc.* ]] && token=litto@preview || token=litto
python3 scripts/release/cask.py "$tag" "$work/Litto-$tag-macOS.zip" "$work/$token.rb"
gh repo clone JesusPaz/homebrew-tap "$work/tap" -- --depth 1 -q
cd "$work/tap"
branch="litto/$tag"
git switch -q -c "$branch"
mkdir -p Casks && cp "$work/$token.rb" "Casks/$token.rb"
git add "Casks/$token.rb"
if git diff --cached --quiet; then echo "Tap already has $token $tag"; exit 0; fi
git commit -q -m "chore: update $token to $tag"
git push -q origin "$branch"
gh pr create -R JesusPaz/homebrew-tap --head "$branch" --title "Update $token to $tag" \
    --body "Install the signed, notarized Litto $tag release, verified with its SHA-256 checksum."
