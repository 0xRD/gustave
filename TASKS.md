# Tasks

One task at a time, in order. Mark a task done only when every acceptance criterion is
met. Criteria marked (manual) need the user on a real Mac: list them, do not assume.

Status: [ ] todo, [~] in progress, [x] done.

## M0. Foundations

- [x] M0.1 Package skeleton builds. `Package.swift` already declares `GustaveCore`,
  `Gustave` and tests, zero dependencies. Add the minimum sources so `swift build`
  and `swift test` succeed.
  - Accept: both commands succeed with zero warnings.
- [x] M0.2 `scripts/make-cert.sh`: create a self-signed code signing identity
  ("Gustave Local Signing") in the login keychain, idempotent, trusted for code signing.
  - Accept: `security find-identity -v -p codesigning` lists it. Re-running does nothing.
- [x] M0.3 `scripts/build-app.sh`: build release, assemble `build/Gustave.app` from
  `Resources/Info.plist` (and icon if present), sign with the identity, hardened
  runtime, `--identifier io.github.0xrd.gustave`, no entitlements.
  - Accept: `codesign --verify --strict` passes. Designated requirement printed and
    identical across two consecutive builds.
- [x] M0.4 `scripts/verify.sh`: security posture checks. Valid signature, hardened
  runtime, no entitlements, only system and Swift runtime libraries (`otool -L`), no
  networking symbols (`nm -u`, heuristic), and if the app is running, no internet
  sockets (`lsof -i`). Non-zero exit on failure.
  - Accept: passes on a clean build, fails when a networking symbol is introduced.
- [~] M0.5 `scripts/make-icns.sh`: build `Resources/Gustave.icns` from
  `Resources/icon-1024.png` with `sips` and `iconutil`.
  - Accept: the built app shows the icon in Finder.
- [x] M0.6 Accessory app shell: AppKit entry point, accessory activation policy, a
  settings window shown on first launch, when Accessibility is missing, and on reopen.
  Accessibility status row with request and open-settings buttons, reacting to
  permission changes via the distributed notification (no polling). Quit button.
  - Accept (manual): grant permission, status flips without restart. Rebuild with
    `build-app.sh`, relaunch: still granted (identity persistence).
- [x] M0.7 GitHub Actions on a macOS 15 runner: build, test, `verify.sh` (non-runtime
  checks). Add LICENSE (GPL-3.0-or-later, to match Hector).
  - Accept: workflow green on a push.

## M1. Core logic (all pure, all unit tested, strict Swift 6)

- [x] M1.1 `Settings` and a tolerant JSON codec (missing keys default, unknown keys
  ignored, garbage decodes to defaults).
- [x] M1.2 `displayTitle`: bound the work on huge input, strip control and invisible
  format characters (bidi overrides, zero width), collapse whitespace, truncate with an
  ellipsis, empty becomes "Untitled".
- [x] M1.3 Dock geometry: infer Dock edge and thickness from `frame` and `visibleFrame`,
  O(1) "near Dock edge" gate, AppKit to Accessibility coordinate conversion.
- [x] M1.4 Scroll rule: device classification from the continuous flag, per-device
  inversion decision from settings.
  - Accept for M1: `swift test` covers every branch, including edge cases (auto-hide
    with no inset, negative coordinates on secondary displays, empty and enormous titles).

## M2. Scroll inversion (F3)

- [~] M2.1 Event tap lifecycle: install only while a toggle is on, remove completely
  when off, re-enable after system disable, survive permission revocation.
  - Open: confirm removal when both toggles go off while running. Hector lists keyboard
    taps only (0xRD/hector#4), so use `CGGetEventTapList` until that is fixed.
- [x] M2.2 Per-device inversion, vertical axis, momentum included.
  - Accept (manual): mouse inverted with trackpad natural and the reverse. Disable both,
    confirm in Hector that no tap remains. No visible latency.
- [x] M2.3 Settings toggles wired to the app model, persisted.

## M3. Dock window list (F1)

- [~] M3.1 Accessibility helper layer with timeouts, all calls off the main thread,
  stale result protection (generation token).
- [~] M3.2 Window enumeration and actions (raise, close, minimize, full screen, quit).
- [~] M3.3 Dock hover detection: Dock selection observer (D15), icon to running app
  resolution, anchor rectangle.
- [~] M3.4 Panel UI: non-activating panel, compact list rows as in `SPEC.md`, hover
  tracking, grace period close, placement for bottom, left and right Docks, clamped
  to the screen.
  - Accept (manual): bottom, left, right and auto-hide Docks, two displays, a frozen
    app, a window with hostile title text, Stage Manager on and off.
  - Done on device (2026-11-06): bottom Dock, auto-hide, windows on other Spaces (D17),
    glass and animation (D19), closing rules (D18, `DockPanelRule`), focus never taken.
  - Done: minimize and close from a row (user, 2026-11-06).
  - Open: left and right Docks,
    two displays, a frozen app, a hostile title, Stage Manager.

## M4. Option+Tab switcher (F2)

- [~] M4.1 MRU window ordering across apps (see approaches A, B, C in `SPEC.md`, F2).
  Prototype on device, pick one, record the result and the rejected options in
  `docs/DECISIONS.md`. Pure ordering logic (move to front, minimized last, drop closed
  windows) lives in Core and is unit tested.
  - Accept (manual): with two windows of the same app as the two most recent, they are
    adjacent in the list. No polling, no Screen Recording prompt, idle cost zero.
- [~] M4.2 Trigger without Input Monitoring if possible. Document the permission
  actually required to detect the Option key release.
- [~] M4.3 Switcher UI reusing the F1 row design, keyboard navigation (Tab, Shift+Tab,
  Escape), quick press toggles the two most recent windows, list frozen while open,
  cleanup on dismiss.
  - Accept (manual): quick press toggles two windows, including two of the same app.
    Works across fullscreen apps and multiple displays. Zero idle cost.
  - Open (D27): quick press reaches the previous window on another Space, and a window
    seen once (Safari's third window) is listed from other Spaces in both lists.

## M5. Hardening and release

- [ ] M5.1 Cost measurements recorded in `docs/DECISIONS.md`: idle CPU, wakeups
  (`powermetrics`), hover cost (Instruments).
- [ ] M5.2 Security review pass against `SECURITY.md`. Update the threat model with
  anything learned.
- [ ] M5.3 Launch at login, silent start, final settings polish.
- [ ] M5.4 README update, release checklist, checksummed GitHub release, optional
  Homebrew tap cask (self-signed, build from source stays primary).
- [ ] M5.5 When the repository is public: sign tagged releases in GitHub Actions with a
  dedicated release certificate stored as a secret (see `docs/DECISIONS.md`, D10).
  - Accept: a tag produces a signed build, `scripts/verify.sh` passes on it, and the
    secret is available only to the protected release environment.
