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

# Other ways to reach the network or run code without a networking symbol: launching a
# process (such as curl), loading a library, or looking up a class or function by name.
banned_indirect='^_(posix_spawnp?|execv[ep]?|execl[ep]?|fork|vfork|system|popen|dlopen)$'
banned_indirect+='|NSTask|NSClassFromString|NSSelectorFromString|^_objc_getClass$|^_objc_lookUpClass$'
found=$(nm -u "$binary" | grep -E "$banned_indirect")
if [[ -z "$found" ]]; then
    pass "no process launching, library loading or lookups by name"
else
    fail "indirect execution symbols: $found"
fi

# Opening a URL in the browser could carry data out with no socket in Gustave. The only
# URL opened is the constant System Settings one, so every open call must name it.
opens=$(grep -rnE '\.open\(|openURL|openApplication' Sources | grep -v 'AccessibilityPermission.swift')
if [[ -z "$opens" ]]; then
    pass "no URL opened beyond System Settings"
else
    fail "URL opening in source: $opens"
fi

# Private APIs are never linked, and only the ones approved in docs/DECISIONS.md may be
# named for lookup at run time.
linked_private=$(nm -u "$binary" | grep -E '^(__AX|__?CGS[A-Z]|__?SLS[A-Z]|__?SLPS[A-Z]|__?CoreDock)')
if [[ -z "$linked_private" ]]; then
    pass "no private APIs linked"
else
    fail "private APIs linked: $linked_private"
fi

approved_private='^(_AXUIElement(CreateWithRemoteToken|GetWindow)|CoreDockSetAutoHideEnabled|CGS(MainConnectionID|CopySpacesForWindows)|_SLPSSetFrontProcessWithOptions|SLPSPostEventRecordTo)$'
# CGS, SLS and SLPS names continue with a capital letter, which keeps public CGSize out.
named_private=$(strings -a "$binary" | grep -E '^(_AX[A-Za-z]+|_?(CGS|SLS|SLPS)[A-Z][A-Za-z]*|_?CoreDock[A-Za-z]+)$' \
    | grep -vE "$approved_private")
if [[ -z "$named_private" ]]; then
    pass "only approved private APIs looked up"
else
    fail "unapproved private API names: $named_private"
fi

# The binary check above cannot see names of 15 bytes or less, which Swift stores inside the
# code. So the source is checked too: every name passed to dlsym or to a symbol helper must
# be a string literal on the approved list.
lookups=$(grep -rhoE '(dlsym\([^,]*, *|symbol\()[^)]*' Sources | sed -E 's/^(dlsym\([^,]*, *|symbol\()//')
unapproved=$(print -r -- "$lookups" | grep -vE '^"[A-Za-z_]+"' | grep -vE '^name$' )
unlisted=$(print -r -- "$lookups" | grep -oE '^"[A-Za-z_]+"' | tr -d '"' \
    | grep -vE "$approved_private" | grep -vx 'GetProcessForPID')
if [[ -z "$unapproved$unlisted" ]]; then
    pass "every looked up name is an approved literal"
else
    fail "unapproved lookups in source: $unapproved $unlisted"
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
