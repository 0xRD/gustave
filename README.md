# Gustave

A tiny, offline macOS companion for [Hector](https://github.com/0xRD/hector). It does three
things, each one switch in its settings:

- **Window list on Dock hover.** Rest the pointer on a running app in the Dock to see its
  windows, on every desktop, and raise, close, minimize or full-screen one.
- **Option+Tab window switcher.** Windows-style: every window of every app, most recently
  used first, across desktops. A quick press goes back to the previous window, even another
  window of the same app.
- **Scroll inversion per device.** Invert a wheel mouse, a trackpad, or both, independently.

It needs Accessibility and nothing else: no Screen Recording, no Input Monitoring, no
network, no dependencies, no auto-update.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark.png">
  <img src="docs/images/settings-light.png" alt="Gustave's settings window: the mark, Accessibility allowed, switches for the Dock window list with its delay, the Option+Tab switcher, mouse and trackpad scroll inversion, and open at login." width="460">
</picture>

Status: **early, used daily by its author.** See [Known limitations](#known-limitations).

## Privacy and private APIs

Gustave holds the Accessibility permission, so it is built to be read in an afternoon:
offline, no dependencies, every check in [`scripts/verify.sh`](scripts/verify.sh). Window
titles and app names are only shown as plain text, never logged.

Public macOS APIs cannot list or focus windows on other desktops, so Gustave uses a few
private functions, the same ones DockDoor and AltTab rely on. Each is looked up at run time;
if a macOS update removes one, Gustave still launches and that feature falls back to the
current desktop. `verify.sh` fails the build if any other private name appears.

| Function | Why |
|---|---|
| `_AXUIElementCreateWithRemoteToken`, `_AXUIElementGetWindow` | Reach windows on other desktops through Accessibility, and know their window ids |
| `CGSMainConnectionID`, `CGSCopySpacesForWindows` | Tell real windows on other desktops from hidden helper windows |
| `_SLPSSetFrontProcessWithOptions`, `SLPSPostEventRecordTo` | Bring one window forward on its own desktop, even when its app is already in front |
| `CoreDockSetAutoHideEnabled` | Only to undo an older build's change to Dock auto-hide after a crash |

They grant nothing beyond Accessibility. The reasoning for each is in
[`docs/DECISIONS.md`](docs/DECISIONS.md) (D17, D25, D26) and the threat model in
[`SECURITY.md`](SECURITY.md).

## Install

Requires macOS 15 or later on Apple silicon, and Xcode 16 or later or the Command Line
Tools. Building with the macOS 26 SDK (Xcode 26) gives the panels Liquid Glass; older
SDKs use a rounded blur instead.

```sh
git clone https://github.com/0xRD/gustave.git
cd gustave
scripts/make-cert.sh     # once per Mac, see below
scripts/build-app.sh     # builds and signs build/Gustave.app
scripts/verify.sh        # optional: the security checks
cp -R build/Gustave.app /Applications/
open /Applications/Gustave.app
```

**Why a certificate.** macOS ties the Accessibility permission to the app's signature.
`make-cert.sh` creates a self-signed code signing certificate named "Gustave Local Signing"
in your login keychain and trusts it for code signing only (macOS asks you to confirm). Each
rebuild is then signed the same way, so the permission survives updates. Nothing leaves your
Mac.

**First run.** The settings window opens. Click Allow Access, turn Gustave on in System
Settings, Privacy & Security, Accessibility, then turn on the features you want. "Open at
login" works best from the copy in /Applications. Gustave then runs out of sight; open it
again from Finder or Spotlight to see its settings.

**Option+Tab.** If DockDoor, AltTab or another switcher also uses Option+Tab, turn its
shortcut off.

## Update

```sh
git pull && scripts/build-app.sh && cp -R build/Gustave.app /Applications/
```

## Uninstall

1. Quit Gustave from its settings window, and turn off Open at login first if it is on.
2. Delete Gustave.app.
3. Remove it from System Settings, Privacy & Security, Accessibility.
4. Delete the "Gustave Local Signing" certificate in Keychain Access, login keychain.
5. Optional: `defaults delete io.github.0xrd.gustave`.

## Known limitations

- Windows on other desktops come from the private functions above. A window Gustave has
  never seen may be missing until you visit its desktop once.
- Not yet checked on device: a Dock on the left or right, several displays, Stage Manager,
  a frozen app.
- The Dock hides while the pointer is on the window list when auto-hide is on. Keeping it
  shown moves maximized windows, so Gustave does not.
- The scroll inversion event tap runs on the main thread; a busy moment there can delay a
  scroll (planned fix in [`TASKS.md`](TASKS.md), M5.0).
- A mouse whose driver sends smooth scrolling counts as a trackpad, and so does a Magic
  Mouse.

## Development

```sh
scripts/check.sh         # release build with zero warnings, unit tests
```

| Path | Purpose |
|---|---|
| `SPEC.md` | What each feature does |
| `SECURITY.md` | Threat model and verification checklist |
| `TASKS.md` | Milestones and what is still open |
| `docs/DECISIONS.md` | Every decision and what was verified on device |
| `CLAUDE.md`, `docs/KICKOFF_PROMPT.md` | Rules and workflow for Claude Code, which wrote most of the code |
| `Sources/GustaveCore` | Pure logic, unit tested |
| `Sources/Gustave` | AppKit, SwiftUI and Accessibility glue |
| `scripts/` | Signing, build, verification and quality gate |

## Acknowledgements

Studied, not copied: [DockDoor](https://github.com/ejbills/DockDoor) and
[AltTab](https://github.com/lwouis/alt-tab-macos) for reaching windows on other desktops,
[Hammerspoon](https://github.com/Hammerspoon/hammerspoon) and
[yabai](https://github.com/koekeishiya/yabai) for focusing a window on another desktop, and
[Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser) for scroll inversion.

## License

GPL-3.0-or-later, see [LICENSE](LICENSE).
