#!/bin/zsh
# Security posture checks, see SECURITY.md. Exits non-zero on any failure.
#
# Usage: verify.sh [--ci] [path/to/Gustave.app]
# --ci accepts an ad hoc signature, because CI has no local identity.
set -uo pipefail
cd "${0:A:h}/.."

ci=0
if [[ "${1:-}" == "--ci" ]]; then
    ci=1
    shift
fi
app="${1:-build/Gustave.app}"
binary="$app/Contents/MacOS/Gustave"
failures=0

pass() { print "ok    $1" }
fail() { print "FAIL  $1"; failures=$((failures + 1)) }

if [[ ! -x "$binary" ]]; then
    print -u2 "verify: $binary not found. Run scripts/build-app.sh first."
    exit 1
fi

if codesign --verify --strict "$app" 2>/dev/null; then
    pass "signature valid"
else
    fail "signature invalid"
fi

details=$(codesign --display --verbose=2 "$app" 2>&1)
if print -r -- "$details" | grep -qE '^CodeDirectory.*flags=.*runtime'; then
    pass "hardened runtime on"
else
    fail "hardened runtime off"
fi

if [[ "$ci" == 0 ]]; then
    if print -r -- "$details" | grep -q '^Signature=adhoc'; then
        fail "ad hoc signature, the Accessibility grant would not survive a rebuild"
    else
        pass "stable signing identity"
    fi
fi

entitlements=$(codesign --display --entitlements - --xml "$app" 2>/dev/null)
if [[ -z "$entitlements" ]]; then
    pass "no entitlements"
else
    fail "entitlements present: $entitlements"
fi

if grep -qE '\.package\(' Package.swift; then
    fail "Package.swift declares a dependency"
else
    pass "no package dependencies"
fi

libraries=$(otool -L "$binary" | tail -n +2 | awk '{ print $1 }')
foreign=$(print -r -- "$libraries" | grep -vE '^(/usr/lib/|/System/Library/)')
if [[ -z "$foreign" ]]; then
    pass "only system libraries linked"
else
    fail "non-system libraries linked: $foreign"
fi

# Heuristic: names any network client or server would need to import.
banned_libraries='/(Network|CFNetwork|ScreenCaptureKit|ReplayKit)\.framework/'
banned=$(print -r -- "$libraries" | grep -E "$banned_libraries")
if [[ -z "$banned" ]]; then
    pass "no networking or capture frameworks"
else
    fail "banned frameworks: $banned"
fi

banned_symbols='^_(socket|connect|bind|listen|accept|sendto|recvfrom|getaddrinfo|gethostbyname)$'
banned_symbols+='|^_nw_|^_CFSocket|^_CFStreamCreate.*Socket|^_SCNetwork'
banned_symbols+='|NSURLSession|NSURLConnection|URLSession|NWConnection|NWListener'
found=$(nm -u "$binary" | grep -E "$banned_symbols")
if [[ -z "$found" ]]; then
    pass "no networking symbols"
else
    fail "networking symbols: $found"
fi

# Private APIs are never linked, and only the ones approved in docs/DECISIONS.md (D17) may
# be named for lookup at run time.
linked_private=$(nm -u "$binary" | grep -E '^(__AX|_CGS|_SLS|_CoreDock)')
if [[ -z "$linked_private" ]]; then
    pass "no private APIs linked"
else
    fail "private APIs linked: $linked_private"
fi

approved_private='^(_AXUIElement(CreateWithRemoteToken|GetWindow)|CoreDock(Get|Set)AutoHideEnabled)$'
# CGS and SLS names continue with a capital letter, which keeps public CGSize out.
named_private=$(strings -a "$binary" | grep -E '^(_AX[A-Za-z]+|_?(CGS|SLS)[A-Z][A-Za-z]*|_?CoreDock[A-Za-z]+)$' \
    | grep -vE "$approved_private")
if [[ -z "$named_private" ]]; then
    pass "only approved private APIs looked up"
else
    fail "unapproved private API names: $named_private"
fi

if [[ "$ci" == 0 ]]; then
    pid=$(pgrep -x Gustave | head -1)
    if [[ -z "$pid" ]]; then
        print "skip  no internet sockets (not running)"
    elif lsof -nP -a -p "$pid" -i >/dev/null 2>&1; then
        fail "internet sockets open"
    else
        pass "no internet sockets"
    fi
fi

if ((failures > 0)); then
    print -u2 "verify: $failures check(s) failed"
    exit 1
fi
print "verify: all checks passed"
