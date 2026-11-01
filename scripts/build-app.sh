#!/bin/zsh
# Builds and signs build/Gustave.app. The designated requirement pins the bundle id and
# the certificate, so it does not change between builds and the Accessibility grant stays.
#
# GUSTAVE_SIGN_IDENTITY=- signs ad hoc, for CI only. GUSTAVE_KEYCHAIN selects a keychain.
set -euo pipefail
cd "${0:A:h}/.."

bundle_id="io.github.0xrd.gustave"
identity="${GUSTAVE_SIGN_IDENTITY:-Gustave Local Signing}"
keychain="${GUSTAVE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
app=build/Gustave.app

sign_args=()
if [[ "$identity" != "-" ]]; then
    fingerprint=$(security find-certificate -c "$identity" -Z "$keychain" 2>/dev/null \
        | awk '/^SHA-1 hash:/ { print $3; exit }')
    if [[ -z "$fingerprint" ]]; then
        print -u2 "build-app: no '$identity' certificate. Run scripts/make-cert.sh first."
        exit 1
    fi
    # Selecting by fingerprint keeps codesign from matching a same-named certificate.
    identity="$fingerprint"
    sign_args=(--keychain "$keychain" --timestamp=none
        --requirements "=designated => identifier \"$bundle_id\" and certificate leaf = H\"$fingerprint\"")
fi

swift build -c release
binary="$(swift build -c release --show-bin-path)/Gustave"

[[ -f Resources/Gustave.icns ]] || scripts/make-icns.sh

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Gustave"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/Gustave.icns "$app/Contents/Resources/Gustave.icns"

codesign --force --sign "$identity" --options runtime --identifier "$bundle_id" \
    "${sign_args[@]}" "$app"

codesign --verify --strict "$app"
codesign --display --requirements - "$app" 2>&1 | grep 'designated =>'
