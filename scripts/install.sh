#!/bin/zsh
# Installs or updates build/Gustave.app in /Applications, the safe way: the running copy is
# stopped, the old bundle is replaced as a whole, and Gustave starts again if it was running.
# Copying over the old bundle instead rewrites the running program's file in place, which
# macOS answers by killing it, and it can refuse to start the new one until a restart.
#
# Usage: scripts/install.sh [path/to/Gustave.app]    (after scripts/build-app.sh)
set -euo pipefail
cd "${0:A:h}/.."

source_app="${1:-build/Gustave.app}"
target=/Applications/Gustave.app
staged="/Applications/.Gustave.app.installing"

if [[ ! -x "$source_app/Contents/MacOS/Gustave" ]]; then
    print -u2 "install: $source_app not found. Run scripts/build-app.sh first."
    exit 1
fi
codesign --verify --strict "$source_app"

# Only a copy running from the place being replaced is stopped and started again.
was_running=0
for pid in $(pgrep -x Gustave || true); do
    if [[ "$(ps -o comm= -p "$pid")" == "$target/Contents/MacOS/Gustave" ]]; then
        was_running=1
        kill "$pid"
        for _ in {1..50}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            print -u2 "install: Gustave (pid $pid) did not quit"
            exit 1
        fi
    fi
done

# The new bundle is complete on the same volume before the old one goes, so a failed copy
# leaves the installed app as it was.
rm -rf "$staged"
ditto "$source_app" "$staged"
rm -rf "$target"
mv "$staged" "$target"
codesign --verify --strict "$target"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$target/Contents/Info.plist")
if ((was_running)); then
    open -g "$target"
    print "install: Gustave $version installed and started again"
else
    print "install: Gustave $version installed. Open it from /Applications."
fi
