#!/bin/zsh
# Builds, signs, verifies and publishes a GitHub release of Gustave, then prints what the
# Homebrew cask in 0xRD/homebrew-tap needs: the version and the archive's SHA-256.
#
# Usage: scripts/release.sh    (the version comes from Resources/Info.plist)
set -euo pipefail
cd "${0:A:h}/.."

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
tag="v$version"
archive="build/Gustave-$version-macOS.zip"

if [[ -n "$(git status --porcelain)" ]]; then
    print -u2 "release: the working tree has uncommitted changes"
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    print -u2 "release: $tag already exists; bump CFBundleShortVersionString first"
    exit 1
fi

scripts/check.sh
scripts/build-app.sh
scripts/verify.sh

rm -f "$archive"
# ditto keeps the signature and extended attributes intact, which zip does not.
ditto -c -k --sequesterRsrc --keepParent build/Gustave.app "$archive"
sha=$(shasum -a 256 "$archive" | awk '{ print $1 }')

git tag -a "$tag" -m "Gustave $version"
git push origin "$tag"
gh release create "$tag" "$archive" --title "Gustave $version" --notes "$(cat <<NOTES
Install with Homebrew: \`brew install --cask 0xrd/tap/gustave\`, or download the archive below.

Not notarized: on first launch, allow it in System Settings, Privacy & Security, Open Anyway.
Then grant Accessibility when Gustave asks. See the README for what it does and which
private functions it uses.

SHA-256 of $(basename "$archive"): $sha
NOTES
)"

print "release: $tag published"
print "cask: version \"$version\""
print "cask: sha256 \"$sha\""
