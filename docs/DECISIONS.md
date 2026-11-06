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
approval. Superseded for windows on other Spaces by D17.

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

### D11. Features are off until turned on
Decided 2026-11-01. SPEC does not set defaults. A new install monitors nothing and does not
take Option+Tab or scroll events from apps that already handle them, such as DockDoor and
Scroll Reverser. The user turns on each feature in settings.

### D12. Title sanitising goes slightly past M1.2
Decided 2026-11-01. `DisplayTitle` also removes default-ignorable, private use and
unassigned scalars, and keeps at most two consecutive combining marks, because each of
these can hide or distort text in a row. Removing joiners and variation selectors means an
emoji family renders as separate emoji. That is accepted: titles are for recognition only.

### D13. Scroll source by the continuous flag, not by device identity
Decided 2026-11-06. Scroll Reverser (source read 2026-11-06) identifies the sending device:
it calls the private `CGEventCopyIOHIDEvent` and `IOHIDEventGetSenderID`, then reads the
device's IOKit properties (scroll acceleration type, multitouch driver class). This gives
per-device settings but breaks hard rule 4, so it is rejected. It also negates the scroll
values inside the attached IOHIDEvent, which Gustave cannot do publicly. The public
alternative, treating a continuous event as a trackpad only when it carries a scroll or
momentum phase (fields 99 and 123), is kept in reserve for smooth-scrolling mouse drivers.
The user tested the continuous flag with their devices and it works, so it stays.

### D14. Dock list details
Decided 2026-11-06. Full screen is toggled by pressing the window's
`kAXFullScreenButtonAttribute` button, not by setting `AXFullScreen`, which is not in the
public headers. Dock hit testing and window listing run on separate serial queues, so a
frozen app cannot delay the hover probe. A listing stops at the first timeout, so one frozen
app costs one 0.3 s timeout, not one per window. The panel shows at most 20 rows. A closed or
minimized row updates in place, without waiting for the app to report the change.

### D15. Dock hover from the Dock's selection, not from the pointer
Decided 2026-11-06, after the first device test missed some hovers. The Dock's AXList
posts `kAXSelectedChildrenChangedNotification` whenever the icon under the pointer changes,
including when the pointer leaves the Dock. Gustave observes it with a public `AXObserver`
(the approach DockDoor uses) and reads the selected item. This replaces the global
mouse-moved monitor, the edge gate and the 30 per second probe: no mouse events, no polling,
and the Dock itself does the hit testing. The edge gate in Core was removed with it. The
observer is re-attached when the Dock relaunches.

### D16. Panel look and sizing
Decided 2026-11-06 at the user's request: it should look like a system menu. macOS 26 and
later use the public `NSGlassEffectView` (Liquid Glass) with a 14 pt corner radius, earlier
systems the menu blur. DockDoor gets its glass through private SwiftUI internals, which
Gustave does not use. Rows follow menu metrics (13 pt text, 26 pt rows, selection colour
under the pointer) and show their controls only when highlighted. The content is passed to
the view by value and measured after rendering, which fixes the clipped panel. Minimizing
presses the window's minimize button. Restoring clears `AXMinimized`.

### D17. Private Accessibility APIs for windows on other Spaces
Approved by the user on 2026-11-06, who wants the Dock list to show windows on other
desktops as DockDoor does. Public Accessibility only returns windows on the current Space.
Allowed, and nothing else:
- `_AXUIElementCreateWithRemoteToken` (HIServices): builds an element for a window of an
  app by its element id, which reaches windows on other Spaces. The approach AltTab uses.
- `_AXUIElementGetWindow` (HIServices): the window id of an element, to drop duplicates.
Both are resolved with `dlsym` at run time, never declared for the linker, so a macOS that
removes them still launches Gustave and simply lists the current Space. Probing is bounded:
it runs off the main thread, only when the public window list shows the app has windows
that Accessibility did not return, stops at the first timeout and after 100 ms, and never
looks past element id 1000. Risks accepted: they can change in any macOS update, and a
changed signature could crash Gustave. They add no privilege: everything they reach is
already reachable with Accessibility. Not allowed under this decision: Screen Recording,
CGS or SkyLight window server calls, private Dock calls. Focusing a window on another
Space uses public calls first; if that proves unreliable, it needs a new proposal.

### D18. Closing the Dock list, and row highlight while inactive
Decided 2026-11-06, after the user found the panel staying open when the Dock auto-hid or
the Space changed. While the panel is visible, and only then, a global monitor for mouse
moves and clicks is installed: the panel closes 250 ms after the pointer is neither on it
nor on the icon, at once on a click elsewhere, and at once when the active Space changes.
The monitor is removed when the panel closes, so the idle cost is unchanged. SwiftUI's hover
tracking does not run while Gustave is inactive, which hid the row controls. The panel's own
tracking area reports pointer moves, and the row comes from fixed metrics in Core
(`DockPanelLayout`). Keeping the Dock shown while the pointer is on the panel is not possible
with public API: the Dock hides as it does for DockDoor.

### D19. System menu look for the Dock list
Approved by the user on 2026-11-06 ("if you have to use a private function do it"), after
the D16 panel still looked out of place. Read on device from a live `NSMenu` window: system
menus use `NSGlassView` with a 12 pt radius, `_variant` 0, `_subduedState` 0 and
`_adaptiveAppearance` 1, where a plain `NSGlassEffectView` defaults to 2. Copying the menu
value kept the panel dark over light content, because dark-mode menus do not adapt, unlike
Control Center. The user then compared live samples of each `_variant` over light content
and picked variant 6, with 2 and 11 offered as alternatives in settings (`PanelGlass`, V6 by
default). `_adaptiveAppearance` keeps its default. The variant is set through key-value
coding, only when the view answers the setter, and only from those three constants.
The panel reports `isKeyWindow` as true so the glass draws its active look; `canBecomeKey`
stays false, so it never takes keyboard focus. Rejected: DockDoor's private SwiftUI glass,
which copies values of unknown size into a fixed buffer and can corrupt memory when the
layout changes. Row controls are the title bar buttons in their system colours, with glyphs
on the highlighted row. The panel opens after a hover delay, 0.5 s by default, set in
settings from 0 to 2 s. Windows found only by the other-Spaces search need a title, which
drops hidden helper windows such as Electron's. Opening fades in over 0.16 s while sliding
6 pt away from the Dock, closing fades out over 0.1 s, and moving between icons glides over
0.12 s. Only the window is animated, so the window server composites it and nothing is laid
out per frame. With Reduce Motion on, the slide is dropped.

### D20. Option+Tab: order from the window server, Carbon hot keys
Decided 2026-11-06, approach A of SPEC F2. The order is read once when the shortcut is
pressed: `CGWindowListCopyWindowInfo` with on-screen windows only lists them front to back,
which is what Windows' own list follows. Only ids, owners and layers are read, so it needs no
Screen Recording. Each window is matched to its Accessibility element by window id through
`_AXUIElementGetWindow`, already approved in D17. Minimized windows of regular apps follow.
Ordering and selection are pure (`SwitcherOrder`, `SwitcherSelection`) and unit tested.
Rejected: B, an MRU list kept by per-app `AXObserver`s, which costs observers in every app
all day for an order the window server already keeps; C, which adds B's cost to A.
Activating a window raises it, which moves it to the front for the next press.

The trigger is a Carbon `RegisterEventHotKey` for Option+Tab and Option+Shift+Tab, which
needs no permission. Option's release is watched by `flagsChanged` monitors installed only
while a switcher session is open; Apple documents key monitors as needing Accessibility. A
quick press is also caught when Tab comes up with Option already released. Option+Escape is
a hot key registered only during a session. The list appears after 0.12 s, so a quick press
switches without flashing it. To verify on device: no Input Monitoring or other prompt.

### D21. Public SwiftUI glass for both panels
Decided 2026-11-06 by the user from live samples over white and black. With an AppKit
`NSGlassEffectView` (any private variant, including V6), the glass turns light over white
content but the text inside keeps the dark appearance, so white text disappears. SwiftUI's
public `.glassEffect(.regular)` stays readable over both. Both panels now draw it themselves
(`panelBackground()`), with a rounded `.regularMaterial` before macOS 26. This supersedes
the glass parts of D19: the private `_variant` and `_adaptiveAppearance` keys, the V2, V6
and V11 choice and its setting are removed. Old settings files that still hold a glass
value decode as before, the key is ignored. The panel still reports `isKeyWindow` as true
so materials draw active, as in the sample the user chose.

### D22. Keep an auto-hiding Dock shown while the window list is open
Approved by the user on 2026-11-06, who wants the Dock to stay up while they use the panel,
as DockDoor does. With auto-hide on, the Dock hides as soon as the pointer moves onto the
panel. DockDoor turns auto-hide off while its preview is open with the private
`CoreDockGetAutoHideEnabled` and `CoreDockSetAutoHideEnabled`, and back on when it closes.
Gustave does the same, and nothing else with them:
- Only when auto-hide is on, and only while the Dock list panel is open.
- A flag is written to Gustave's defaults before turning auto-hide off and removed after
  turning it back on. If Gustave is killed in between, the next launch sees the flag and
  turns auto-hide back on. Quitting normally also restores it.
- Both functions are resolved with `dlsym`; without them the Dock is left alone.
- Calls run on the Dock queue, in order, never on the main thread.
Risk accepted: this changes a system preference for the time the panel is open; a crash
followed by never relaunching Gustave would leave auto-hide off until the user turns it back
on. The screen's visible frame changes while the Dock is held, which windows may notice.
`CLAUDE.md` rule 4 names D17 only; adding D22 there is left to the user.

### D23. Option+Tab lists windows on every Space
Decided 2026-11-06 at the user's request, after they found the switcher missing windows
that DockDoor shows. Supersedes the "current Space" scope of D8 and SPEC F2. The list is
built in two steps. First the current Space, with every app asked in parallel, so it costs
about the slowest app instead of the sum (the serial version took 109 to 239 ms for 20
apps). Then the other-Spaces search of D17, also in parallel, on its own queue: a quick
press never waits for it, and raising the chosen window is never queued behind it. Windows
from other Spaces follow the current Space's in the window server's global order, before
the minimized ones. When they join an open list, the selection stays on its window
(`SwitcherOrder.index(keeping:in:)`). The Dock list's search moved to the same queue.

### D24. Option+Tab follows focus history, like Command+Tab
Decided 2026-11-06, after the user found Option+Tab and Command+Tab disagreeing: with Claude
and Safari on different Spaces, Command+Tab toggled them and Option+Tab did not, because
the window server's stacking order is per Space. This revisits D20's rejection of approach
B in a cheaper form: Gustave records which window gains focus (`FocusTracker`), from
`NSWorkspace.didActivateApplicationNotification` and one `AXObserver` for
`kAXFocusedWindowChangedNotification` on the frontmost app only, moved on each activation.
Windows are keyed by window id through `_AXUIElementGetWindow` (D17). The history is pure
(`RecentWindows`, 256 entries, in memory, cleared per app on quit) and leads the order
(`SwitcherOrder`), across Spaces; windows never focused while Gustave ran follow in window
server order, and minimized windows stay last. Started from the on-screen order, and only
while the switcher is on. No polling: work happens only when focus changes.

The other-Spaces search no longer stops an app's search on a failed read that is not a
timeout, which could hide the windows after it, and it logs why candidates are skipped.

### D25. Withdraw D22, and cancel a pending show when the user moves on
Decided 2026-11-06 after the user's test. Turning the Dock's auto-hide off while the panel
was open made maximized and tiled windows move up and back down, because the usable screen
area changes with it; nothing avoids that, and DockDoor ships the same option off by
default for that reason. The hold is removed. Only the recovery stays: a launch that finds
the flag an earlier build wrote turns auto-hide back on, using `CoreDockSetAutoHideEnabled`
for that single purpose. The Dock hides while the pointer is on the panel, as with DockDoor.

Clicking an icon before the hover delay ended made the panel appear after the app came
forward and the Dock hid, because the Dock reports no change when it hides that way. While a
show is pending, and only then, a global mouse-down monitor and observers for app activation
and Space changes cancel it. DockDoor cancels its pending preview on a Dock click too. Any app
activation cancels it, including one the user did not cause; the panel then opens on the next
icon hovered. An independent review of this change found the five issues fixed in D26.

### D26. Space-aware search and focus on any Space, as DockDoor does
Approved by the user on 2026-11-06 (private functions allowed when needed). Research of
DockDoor's source found two gaps. Adds, resolved with `dlsym`, with public fallbacks:
- `CGSMainConnectionID` and `CGSCopySpacesForWindows` (mask 7): a window that belongs to no
  Space is ordered out, a hidden helper. Candidates for the other-Spaces search are now
  layer 0, at least 100 by 50, alpha above 0.01, not on screen, and on some Space. Most apps
  then have no candidate and skip the search, so it no longer needs a 100 ms cut-off, which
  missed Safari windows with high element ids. It covers ids 0 to 999, stops on a timeout,
  and has a 1 s backstop. The title filter applies only when Spaces cannot be read.
- `_SLPSSetFrontProcessWithOptions` (mode 0x200, user generated) with the window id, then
  `SLPSPostEventRecordTo` twice with the make-key event record DockDoor and Hammerspoon use
  (0x100 bytes; 0x04 = 0xF8, 0x08 = 1 then 2, 0x20 to 0x2F = 0xFF, 0x3A = 0x10, 0x3C =
  window id), via the deprecated public `GetProcessForPID`. This brings a window forward on
  its own Space even when its app is already frontmost, which AXRaise and AXFrontmost cannot.
  AXRaise and AXMain follow; AXFrontmost is the fallback when the window server call fails.
  A minimized window takes the public path only: restoring is asynchronous, and the window
  server call would act on a window still ordered out.
- Windows of a hidden app (Command+H) may belong to no Space: for those the Space test is
  skipped and the title test applies. A failed Space query counts as unknown, not as hidden.
- The window server calls run off the main thread (Accessibility queues), where Hammerspoon
  and yabai call them on main; no problem seen, to keep an eye on.
Checked on device: Safari's windows on other Spaces report their Space, its hidden helper
reports none. Not allowed under this decision: changing Spaces directly, moving windows
between Spaces, window capture.

`FocusTracker` now reads the focused window from the frontmost app on each change rather
than trusting the notification's element, and logs window ids (no titles) at debug level.

### D27. Remember the windows already seen
Decided 2026-11-06 after two reports from the user's debug log (Safari pid 1489, Finder 653).
Both have one cause: Gustave forgot windows it had already seen, and found windows on other
Spaces only by the search of D17, which runs after the first list and cannot reach every
window.
- Safari has 3 windows; from another Space both lists showed 2, every time: "3 windows not
  on this Space, 2 found, ... 1 not reached, stopped: id limit, last id 1000". The third
  window's element id is above 1000. Element ids grow as a long-running app creates
  elements, so no fixed range reaches every window.
- A quick Option+Tab went to Finder 418 although the focus history was Safari 4081, Safari
  9111, Finder 418. 9111 is on another Space. The first list holds the current Space only,
  `SwitcherOrder` drops history entries that are not listed, and a quick press commits on
  the first list, before the search (D23) adds 9111. The history was right; the list it
  was applied to was not.

Fix, as DockDoor keeps its window cache: an Accessibility element read while its window is
on the current Space keeps working after the user leaves that Space. Gustave remembers the
element of every window it sees: each window `FocusTracker` sees focused, each window
`AXWindows` returns for either list, and each window the search finds. Kept in memory only,
at most 256 windows, least recently seen dropped first (`SeenWindows` in Core, unit tested,
behind a lock in `SeenWindowElements`, as the Accessibility queues and main all use it).
A remembered element is used only for a window the window server still lists for that pid
as a candidate on another Space (the D26 test), and only if it answers a read with the
short timeout; one that fails is forgotten. Windows the window server no longer has are
dropped whenever their app's remembered windows are read, which every Option+Tab does for
every app, and an app's windows go when it quits (observed only while a window feature is
on). The memory is emptied when both the Dock list
and the switcher are off, or Accessibility is revoked.
- The switcher's first step now includes the remembered windows on other Spaces: one read
  per window, no search, so the first step stays fast and a quick press reaches the window
  focused before, on any Space.
- The search, used by the Dock list's second step and the switcher's, reads remembered
  windows first and looks by element id only for the rest, so once every window has been
  seen it does not run at all. The Dock list could take them in its first step too
  (`AppWindows.remembered`), left for the next change to that file.
- The search's range stays 0 to 999. Raising it would cost a scan of every id up to the
  new limit on every list, for every app with a window never seen, and would still miss
  higher ids. Its log line now records how long it took, to decide this on data.
Not done, to keep steady-state cost at zero: refreshing the memory on every Space change,
or listing every app at launch. A window never focused or listed since Gustave started,
whose element id is above 999, is still missing until the user visits its Space and
focuses it, hovers its app in the Dock, or presses Option+Tab there. No new private API.

Fixed with it, from a review of the switcher by three test agents:
- A hidden app's windows (Command+H) are returned by `AXWindows` but not on screen, so they
  had no place in the order and were dropped. They now follow other Spaces, before the
  minimized windows (`offScreen` in `SwitcherOrder`). Windows without a window id, as when
  `_AXUIElementGetWindow` is missing, are listed there too instead of the switcher being
  empty.
- `AppWindows.list` dropped a whole app when one window failed to read (one closing while
  listed); only a timeout does that now. Subroles are logged only when they are system
  values, as they are app-supplied text.
- Repeated quick presses re-picked the same window: the history learnt of the switch only
  after the raise, the app's answer and a hop to main. The chosen window now leads the
  history at once.
- With no focused window (the desktop, or Gustave's settings), the first press skipped the
  most recent window. It now selects it (`SwitcherSelection.steps`).
- Each press queued a full build and a search that ran to the end even after the session
  was over. A session's work now stops at its end, checked before each app and during the
  search, so a quick press no longer runs the search at all.
- Each press read the window server's full list about three times per app. It is now read
  once per session for every app and both steps, plus the on-screen list.
- A session whose Option release went unseen (secure input) stayed open with its list up.
  The show delay and the list's arrival now check Option and switch when it is already up.
- `FocusTracker` removed its notification from the app being left on the main thread; that
  call into a possibly frozen app now runs on the Accessibility queue.

### D28. Settings window identity and launch at login
Decided 2026-11-06 at the user's request ("a small UI that has an identity kind of like
Hector", "the setting for Gustave to work on startup"). The settings window uses Hector's
warm canvas, cards, verdict pill and serif title (tokens copied from Hector's design brief,
no shared code), and Gustave's mark drawn in code on a 24 point grid like Hector's helmet,
taken from the app icon. Launch at login uses `SMAppService.mainApp`: the system's own
login item, no helper, no entitlement; its state is read from the system each time the
window shows and never stored. Registering works best from a copy in /Applications.

### D29. Findings of the stability, feature and security testers
2026-11-06: three agents tested HEAD c7e47ae from code, unit tests and fuzzing (they cannot
drive the UI). Fixed here, in c8e7e66 and the commit after it:
- Dock list: the panel kept the previous app's rows, and Quit could quit the hovered app
  instead of the one shown (`DockPanelContent.app`); a non-answering app now hides it.
- Dock list: row controls vanished after a refresh under a still pointer; the header lacked
  the app icon (SPEC F1); the panel could cover the menu bar; "1 more windows".
- Dock list: work queued for an older hover now stops before starting (`GenerationToken`).
- Dock observer: reattaching relied on launch notifications that are not reliably posted for
  the Dock, a UI element app. It now observes the running apps list (an event) and retries
  the subscription 5 times, 0.5 s apart, after a Dock change. Unsubscribing runs off main.
- `DisplayTitle` could return 121 characters for a clipped input; fuzz tests kept.
- Settings reopen when Accessibility is revoked while running (SPEC F4).
- The Carbon handler is removed when a shortcut cannot be registered.
- `verify.sh` also checks the source: every name looked up at run time must be an approved
  literal. Names of 15 bytes or less never appear in `strings` output, so the binary check
  alone could miss them. Checked both ways: a lookup of "SLSMoveWindow" fails it.
Passed to the switcher work (D27): hidden apps on the current Space, failed reads in
`AppWindows.list`, quick presses within 100 ms, missing `_AXUIElementGetWindow`, stale
switcher work, window server snapshots per press, a missed Option release, the main-thread
unsubscribe in `FocusTracker`, public logging of app-supplied subroles.
Not done yet: moving the scroll tap off the main run loop (a main-thread stall delays
scrolling); confirming on device that "Option+Tab is taken" is ever reported; removing the
D25 recovery after a release.

### D30. Dock icon while the settings window is open
Decided 2026-11-06 at the user's request ("can Gustave also get his app icon when opened in the
Dock"). The bundle already carries the icon at every size; an accessory app simply never
shows in the Dock. Gustave now switches to the regular activation policy while its settings
window is open (Dock icon, app menu with Close Window, Hide and Quit) and back to accessory
when the window closes. LSUIElement stays true, so it never shows at login or in the
background. Supersedes the "no Dock icon" line of D6 and SPEC F4 for that window only.

### D31. Cover the Dock's name label while the panel is open
Decided 2026-11-06 at the user's request ("it should remove the app name from behind it ...
if not possible, abort"). The label is drawn by the Dock; no public API and no known private
function hides it. The panel now sits 6 pt from the icon, which places it over the label,
so the label is hidden while the panel is open and shows again when it closes. Supersedes
the 15 pt of D19's follow-up. To check on device: no part of the label shows below the panel,
and the panel does not cover the icon.

### D32. First release and the Homebrew cask
Decided 2026-11-06, when the user made the repository public and asked for Gustave in their
tap (0xRD/homebrew-tap, which ships apps as casks of a GitHub release zip with a pinned
SHA-256, as Hector does). `scripts/release.sh` checks, builds, signs, verifies, archives with
`ditto`, tags, publishes the release and prints the cask's version and checksum. Releases
are signed locally with the "Gustave Local Signing" certificate, so the Accessibility grant
of a Homebrew install carries over between releases (the designated requirement pins that
certificate). Not notarized: first launch needs Open Anyway, as for Hector. Moving release
signing to CI (D10, M5.5) would change the certificate, so users would grant once more.

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
- 2026-11-01, macOS 26.6: an active `cgSessionEventTap` on scroll-wheel events is created
  with Accessibility alone, with no Input Monitoring prompt. `CGGetEventTapList` shows one
  enabled tap with mask 0x400000 while a toggle is on at launch, and none while both are
  off. Removal by toggling at runtime, and scroll behaviour, are still manual checks.
- 2026-11-06, macOS 26.6: user check of M2. Mouse inverted with the trackpad natural, and
  the reverse, work with their devices, as do momentum and latency. A tap installed at
  runtime by a toggle shows in `CGGetEventTapList`. Hector cannot show scroll taps yet
  (0xRD/hector#4), so removal by toggling off while running is not yet confirmed.
- 2026-11-06, macOS 26.6: with the Dock list on, the global mouse-moved monitor adds no
  event tap (`CGGetEventTapList` shows only the scroll tap) and causes no new TCC request.
  Idle: 0.0 percent CPU, 12 MB, no sockets. Hover, panel and window actions are manual checks.
- 2026-11-06, Command Line Tools with the macOS 27 SDK: SwiftUI's `@State` is a macro whose
  plugin is not found, like Swift Testing's (D9). View state lives in observable models.
- 2026-11-06, macOS 26.6, first Dock list test by the user: Safari showed one window of
  three, a minimized window was missing, the minimize button did nothing, a panel was clipped,
  some hovers showed nothing. Focus was never taken. Fixes in D15 and D16. The missing
  windows are not explained yet: windows on other Spaces are expected to be missing (D4).
  `AppWindows` logs counts and subroles at debug level, without titles, to find out.
- 2026-11-06, macOS 26.6, debug log from the user's test: Mail, Messages and Photos report
  their main window as `AXDialog`, so dialogs at window layer 0 are now listed too (as
  DockDoor does). Safari reported 0 windows while its windows were on another Space.
  Pressing Safari's minimize button through Accessibility failed. The log now records the
  AXError of each step, and the panel re-reads the windows after an action.
- 2026-11-06, macOS 26.6: `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)` returns
  nothing for windows on other Spaces, so layers come from one `.optionAll` list per
  listing. With that build, the other-Spaces search found Safari and Mail windows the
  public list missed (log: "5 windows not on this Space, 2 found").
- 2026-11-06, macOS 26.6: `NSGlassEffectView` stops the process with a fatal error when
  `_adaptiveAppearance` is set outside 0 to 2. `_variant` and `_subduedState` accepted 0 to 20.
  Values are therefore fixed constants, never taken from settings or other input.
- 2026-11-06, macOS 26.6: the open animation animated the panel's whole frame toward its
  size at open time. When windows from other Spaces arrived during it, the panel was resized,
  then shrunk back as the animation ended, which cut off the header and the rounded corners.
  Every frame change now goes through one setter that replaces any running animation, and
  only same-size moves animate. The gap between icon and panel counts as inside.
- 2026-11-06: the clipping had a second, real cause, reproduced in a scratch program. The
  glass view was sized to the new panel size and also autoresized with the window, so each
  resize was applied twice (a 160 pt panel got 220 pt of glass, the first open doubled it).
  The glass is now sized explicitly only. A 38 pt gap put the panel far above the Dock's
  label; 15 pt is the value read from the user's screenshots.
- 2026-11-06: moving from a running app to the icon of an app that is not running left the
  panel open. The Dock reported a selection Gustave could not map to a running app, which
  was handled as "left the Dock", and the pointer was still inside the panel and icon area.
  Another Dock item (an app that is not running, a folder, the Trash) now closes the panel
  at once (`DockPanelRule`). The grace period applies only when nothing is selected.
- 2026-11-06: the user confirmed the panel now renders whole, with its title and corners.
- 2026-11-06, macOS 26.6, user test of M4: switching works. The list did not show: it was
  shown only if the window list was ready at the 0.12 s mark, which collecting every app's
  windows can exceed. It now shows once both are ready, and the build time is logged.
- 2026-11-06, macOS 26.6: over a white background the glass turns light, but the views
  inside keep the dark appearance (checked with a glass panel over a white window), so white
  text becomes unreadable. The appearance does not follow the glass; a fix is being chosen
  with the user from live samples.

## Open questions

- How to obtain MRU window order without private APIs (SPEC F2, approaches A, B, C).
- Whether an active scroll tap behaves the same on macOS 15. Accessibility is enough on 26.6.
- Whether Dock hover works reliably with magnification and auto-hide.
- Whether `AXWindows` omits minimized windows for some apps, or only windows on other Spaces.
