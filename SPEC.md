# Gustave specification

Version 0.1 draft. Owner: Romain.

## Goals

- Replace DockDoor and Scroll Reverser for one user's needs with a smaller, offline,
  auditable app.
- Idle cost indistinguishable from zero. It runs from login all day.
- Minimal privilege: Accessibility only.
- A small settings window to toggle each feature on and off.

## Non-goals

- Window thumbnails or any screen capture.
- Windows on other Spaces (needs private APIs).
- Window tiling, hot corners, themes, plugins, telemetry, auto-update.
- Distribution through the App Store or notarized releases (self-signed, build from
  source is the primary path).

## Users and environment

One power user on macOS 15 or newer, Apple silicon. Standard Dock (bottom, left or
right, magnification possible, auto-hide possible). Multiple displays possible.

## Features

### F1. Dock window list

Hovering a running app's icon in the Dock opens a compact list panel above (or beside)
the icon. One row per standard window, in the style of DockDoor's compact list.

- Header: app icon, app name, quit button.
- Row: app icon, window title (single line, tail truncated), controls: close, minimize,
  full screen toggle. Minimized windows are dimmed.
- Clicking a row raises that window, restores it if minimized, and activates the app.
- The panel stays open while the pointer is on the icon or the panel, and closes after
  a short grace period (about 250 ms) once it leaves both.
- Apps with no standard window show no panel.
- Works with Dock at bottom, left, right, with auto-hide, and with multiple displays.
- Never steals focus until a row is clicked (non-activating panel).

Acceptance:
- No Screen Recording permission requested at any point.
- Panel appears within about 150 ms of hovering an icon with a responsive app.
- A frozen app does not freeze Gustave or delay other apps' panels beyond the AX timeout.
- Window titles with control characters, bidi overrides or huge length render safely.

### F2. Option+Tab window switcher

Windows-style Alt+Tab. Decided: the list contains every standard window of every app
on the current Space, each window as its own entry, ordered by most recently used
(MRU). Two Chrome windows are two entries, and they sit next to each other if they were
the last two used.

Behaviour (modelled on Windows):
- A quick press (hold Option, tap Tab, release both) switches to the previously used
  window. Repeating it toggles between the two most recent windows.
- Holding Option and pressing Tab repeatedly moves the selection forward through the MRU
  list. Shift+Tab goes backwards. Releasing Option activates the selection. Escape
  cancels.
- Selecting a window raises it, restores it if minimized, and moves it to the front of
  the MRU list.
- The list does not reorder while the switcher is open.
- Minimized windows are listed after the non-minimized ones (Windows sends a minimized
  window to the back of the order).
- Row design is the same as F1 (icon, title). The hotkey is configurable later,
  Option+Tab first.

Acceptance:
- Quick Option+Tab toggles between the two most recently used windows, including two
  windows of the same app.
- Does not require Input Monitoring. Prefer a Carbon `RegisterEventHotKey` for the
  trigger. If tracking the Option key release needs an event tap, document why and the
  exact permission it needs before implementing.
- Zero cost while idle. MRU tracking must be event driven, never polling.

MRU tracking is the hard part: macOS has no public API that returns windows in
most-recently-used order across apps. Candidate approaches, to evaluate on device in
M4 and record in `docs/DECISIONS.md` (hard rule 4 forbids private APIs such as
`_AXUIElementGetWindow` without approval):
- A. Z-order: `CGWindowListCopyWindowInfo` returns windows front to back. Windows'
  own list follows z-order, so this approximates MRU. Window names need Screen
  Recording, so match entries to Accessibility windows by pid and frame instead of by
  title. Verify it does not trigger any Screen Recording prompt.
- B. Own MRU list: update it on `NSWorkspace` app activation notifications and on
  `AXObserver` focused-window and main-window change notifications for running apps.
  Event driven, but needs one observer per app and careful cleanup.
- C. Hybrid: use B for ordering, A to correct drift when the switcher opens.

### F3. Scroll inversion

Independent toggles for mouse and trackpad. Vertical axis only in v1.

- Classic wheel mice send non-continuous scroll events, trackpads and Magic Mouse send
  continuous events. Magic Mouse is therefore treated as a trackpad (documented limit).
- Inversion also applies to momentum scrolling without visible glitches.
- The event tap exists only while at least one toggle is on.

Acceptance:
- Mouse inverted and trackpad natural (and the reverse) works at the same time.
- Disabling both toggles removes the tap. Verify with Hector's event tap view.
- Scroll latency is not perceptibly affected.

### F4. Settings window

Small window, no menu bar item, no Dock icon (accessory app). Opened on first launch,
whenever Accessibility is missing, and when the app is opened again from Finder or
Spotlight. Contents: one toggle per feature, launch at login, Accessibility status with
a button to request or open System Settings, Quit button.

- Settings persist locally (UserDefaults, JSON, tolerant decoding of missing keys).
- Launch at login uses `SMAppService.mainApp`.
- Silent at login when permission is granted.

## Permissions model

Accessibility only. The app reacts to permission changes without polling by observing
the `com.apple.accessibility.api` distributed notification, then re-applies its
features. Feature code must tolerate permission being revoked while running.

## Identity and signing

Bundle id `io.github.0xrd.gustave`. Signed with a stable self-signed code signing
identity, with the bundle id pinned in the designated requirement, so the Accessibility
grant survives rebuilds. Hardened runtime on, no entitlements.

## Performance budget

- Idle CPU 0.0 percent, idle wakeups near zero (`powermetrics --show-process-wakeups`).
- Dock hover: constant-time pointer check, Accessibility probes only near the Dock
  edge and at most about 30 per second.
- Memory: low tens of MB resident. No caches of window lists.

## Implementation notes (verify on device, then record in DECISIONS.md)

These are starting points, not facts.

Dock hover:
- Global `NSEvent` monitor for mouse-moved events. It does not report events delivered
  to the app's own windows, which is useful: tracking areas on the panel tell you when
  the pointer is on it.
- Find the Dock icon with `AXUIElementCopyElementAtPosition` against the Dock process
  (`com.apple.dock`). App items have subrole `AXApplicationDockItem` and an `AXURL`.
  Match the URL to a running app by bundle URL.
- Dock placement can be inferred from the gap between `NSScreen.frame` and
  `visibleFrame`. With auto-hide there is no gap: read the Dock orientation preference.
- AppKit coordinates have a bottom-left origin, Accessibility uses top-left origin
  anchored on the primary screen. Convert carefully, test with a pure function.

Windows:
- `AXWindows` on the app element. Keep standard windows (`AXStandardWindow`). Read
  `AXTitle` and `AXMinimized`. Set a messaging timeout on every element.
- Actions: set `AXFrontmost` on the app element (does not depend on cooperative
  activation), clear `AXMinimized`, set `AXMain`, perform `AXRaise`. Close by pressing
  the `AXCloseButton`. Full screen via the `AXFullScreen` attribute. Quit through
  `NSRunningApplication.terminate()`.

Scroll:
- Active `CGEventTap` on scroll-wheel events, attached to the main run loop. Check the
  continuous field to tell mouse from trackpad. Negate the axis 1 delta, point delta
  and fixed-point delta. Re-enable the tap when the system disables it (timeout or user
  input). Confirm on device which permission an active tap needs.

Switcher:
- Prefer a Carbon `RegisterEventHotKey` for Option+Tab. It needs no permission. Check
  what is needed to observe Option release.

## Out of scope for now

Hector integration beyond being observable by it. Possible later: Hector recognises
Gustave and shows its permission state.
