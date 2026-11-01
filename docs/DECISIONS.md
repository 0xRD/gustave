# Decisions

Short ADR log. Add an entry whenever a behaviour is verified on device or a rule needs
an exception. Newest at the bottom of each section.

## Accepted

### D1. Separate app, not part of Hector
Hector is a security tool with a root helper and a published threat model, and it makes
network requests (database and hosts list downloads). Gustave needs Accessibility, so
merging them would give any Hector compromise Accessibility, and would give up
Gustave's no-network property. Separate processes also keep release cadences apart and
let Hector observe Gustave (event taps, connections). Share conventions and CI
patterns, not binaries.

### D2. Accessibility only, no Screen Recording
No thumbnails. Window titles, state and controls all come from Accessibility. This
removes the most expensive and most privacy-sensitive capability of DockDoor.

### D3. No network, no updater, no dependencies
Update path is "pull and rebuild" or a checksummed release. This keeps the supply chain
to Apple's SDK.

### D4. No private APIs
Consequence: windows on other Spaces are not listed. Revisit only with explicit user
approval.

### D5. Self-signed stable identity
Accessibility trust is tied to the code signature. An ad-hoc signature changes on every
build and, as far as we know, resets the grant. A self-signed identity with the bundle
id pinned keeps the designated requirement stable. No paid Apple Developer account.
Windows-style signing (Authenticode, SignPath) is unrelated and not needed here.
Verify on device in M0.6.

### D6. Plain AppKit entry point, accessory app
No SwiftUI `App` lifecycle, no menu bar item. Reopening the app shows settings.
SwiftUI is used for views only.

### D7. Name and mascot
Gustave, a flat-capped, mustachioed neighbour peeking over the same wall and sun as
Hector. Names checked against GitHub repository names and Homebrew core and cask on
2026-11-01. Still to check before publishing: crates.io, npm, domains, trademarks.

### D8. Switcher behaves like Windows Alt+Tab
Decided 2026-11-01. All standard windows of all apps on the current Space, one entry per
window, most recently used first, quick press toggles the two most recent windows. Not
the macOS Cmd+` model (frontmost app only). Windows orders its list by z-order, with
minimized windows sent to the back. The consequence is that Gustave needs a reliable MRU
order across apps, which macOS does not expose publicly: see `SPEC.md`, F2 and task
M4.1.

### D9. Swift Testing, and a gate script for Command Line Tools
Decided 2026-11-01. Command Line Tools ship Swift Testing but not XCTest, so unit tests
use Swift Testing. With Swift 6.4 and no Xcode, SwiftPM does not find the Testing macro
plugin and passes two linker search paths that do not exist. Both come from the
toolchain, not from Gustave. `scripts/check.sh` is the gate: it adds the plugin path and
ignores exactly those two linker warnings. Any other warning fails it.

### D10. Release signing in GitHub Actions, once the repository is public
Planned 2026-11-01, not implemented. Public repositories get free standard runners, which
removes the Actions minutes limit. Whoever holds the signing key can build a binary that
inherits the Accessibility grant without a prompt, so the key is never shared with local
builds. Releases use a separate certificate, with the local identity staying only in the
login keychain. The secret lives in a protected GitHub environment with required review,
used only by a workflow triggered by tags, never on `pull_request`, with actions pinned by
commit. Moving between a local and a release build needs a new grant. Self-signing does not
satisfy Gatekeeper, so building from source stays the primary path. To verify when
implementing: how to trust the certificate on a hosted runner.

## Verified on device

- 2026-11-01, macOS 26.6: codesign refuses an untrusted self-signed identity ("no identity
  found"), so the trust step in `scripts/make-cert.sh` is required.
- 2026-11-01, macOS 26.6: M0 shell, ad hoc build. Launches with no permission prompt. Idle
  over 9 s of `top`: 0.0 percent CPU, 0 idle wakeups, 19 MB, no internet sockets.

- 2026-11-01, macOS 26.6: do not run an ad hoc build on a Mac that uses the local identity.
  After ad hoc test launches, granting the signed build left `tccd` checking an old cdhash
  requirement, and Accessibility stayed denied although System Settings showed it on. The
  log (`/usr/bin/log`, process `tccd`) shows status -67050 on that cdhash. The ad hoc origin
  is inferred, not proven. Recovery: `tccutil reset Accessibility io.github.0xrd.gustave`,
  then grant again.
- 2026-11-01, macOS 26.6: `com.apple.accessibility.api` reached the app while it was
  inactive, with the default suspension behaviour.

- 2026-11-01, macOS 26.6: after a reset and a new grant on the local identity, the status
  flipped without a restart and the grant survived a rebuild that changed the binary.

## Open questions

- How to obtain MRU window order without private APIs (SPEC F2, approaches A, B, C).
- Which permission an active scroll event tap needs on macOS 15 and later.
- Whether Dock hover works reliably with magnification and auto-hide.
