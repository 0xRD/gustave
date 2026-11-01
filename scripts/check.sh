#!/bin/zsh
# Quality gate: release build with zero warnings, then unit tests.
set -euo pipefail
cd "${0:A:h}/.."

# With Command Line Tools only (no Xcode), SwiftPM adds two linker search paths that do
# not exist and cannot find the Swift Testing macro plugin. See docs/DECISIONS.md, D9.
clt=/Library/Developer/CommandLineTools
toolchain_noise="ld: warning: search path '$clt/Developer/(usr/lib|Library/Frameworks)' not found"

log=$(mktemp)
trap 'rm -f "$log"' EXIT

rm -rf .build/out/Intermediates.noindex/Gustave.build/Release
swift build -c release 2>&1 | tee "$log" | tail -1
if grep -E 'warning:|error:' "$log" | grep -vE "$toolchain_noise" | grep -q .; then
    grep -E 'warning:|error:' "$log" | grep -vE "$toolchain_noise"
    print -u2 "check: release build is not clean"
    exit 1
fi

test_args=()
if [[ "$(xcode-select -p)" == "$clt" ]]; then
    test_args=(-Xswiftc -plugin-path -Xswiftc "$clt/usr/lib/swift/host/plugins/testing")
fi
swift test "${test_args[@]}" 2>&1 | tail -1
exit "${pipestatus[1]}"
