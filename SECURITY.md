# Gustave security model

Gustave is a small macOS utility that runs all day, from login. It holds the
Accessibility permission, which is powerful. The design goal is a codebase small and
isolated enough that you can read and verify all of it.

## Assets

- Everything visible or controllable through Accessibility: window titles, window
  controls, which apps are running.
- Scroll input events (when inversion is on).
- The user's trust in what runs with the Accessibility permission.

## Trust boundaries

| Boundary | Direction | Handling |
|---|---|---|
| Other applications to Gustave | window titles, app names | Untrusted strings. Bounded, stripped of control and invisible formatting characters, truncated, rendered as plain text only (`displayTitle`). |
| Gustave to other applications | AX actions (raise, close, minimize, full screen), terminate | Only on explicit click. Short AX timeouts, off the main thread. |
| Gustave to the network | none | No network code, no entitlement, no updater. |
| Gustave to the rest of the OS | none | No helper, no root, no XPC service, no Apple Events. |

## Hard rules

1. Accessibility is the only privilege. No Screen Recording, no Input Monitoring, no
   Automation, no Full Disk Access.
2. No network access of any kind. No analytics, no update check.
3. No third-party dependencies. `Package.swift` must not list any.
4. No private APIs, except the ones approved in `docs/DECISIONS.md`: Accessibility and
   window server calls to list and focus windows on other Spaces (D17, D26), and one Dock
   call that only undoes an earlier build's change to auto-hide (D25). They grant no
   privilege beyond Accessibility.
5. No privileged helper and no entitlements. The hardened runtime is on.
6. A disabled feature is removed, not paused: its event monitor or tap is uninstalled.
7. Window titles and app names are never interpreted: no URL opening, no shell, no
   markdown, no format strings.

## Threats and mitigations

| Threat | Mitigation |
|---|---|
| Exfiltration of window titles or input | No network code. Verified in CI and at runtime (`scripts/verify.sh`), and observable in Hector. |
| Malicious update or supply chain compromise | No updater, no dependencies. Users build from source; checksummed releases are planned (TASKS.md, M5.4). |
| Spoofed titles (bidi overrides, zero-width characters, huge strings) | `displayTitle` sanitises and bounds input. Covered by unit tests. |
| A hung app freezes Gustave | AX calls run on a serial background queue with 0.3 s timeouts. Results carry a generation token so stale replies are dropped. |
| Event tap abuse | The only tap handles scroll-wheel events, does constant-time work, and never reads keys. The tap is installed only while scroll inversion is on. |
| Permission lost after a rebuild (ad-hoc signature) | Stable self-signed identity (`scripts/make-cert.sh`) so the designated requirement stays the same. |
| Private API changes in a macOS update | Looked up with `dlsym` at run time, never linked. Missing symbols turn the feature off for other Spaces, and the app still launches. Signatures are reviewed on each macOS major release. |
| Tampered binary on disk | Hardened runtime and signature. `codesign --verify --strict` is part of `scripts/verify.sh`. |
| Compromise of Gustave through Hector, or the reverse | Separate processes, separate bundles, no shared IPC. |

## Residual risk

Accessibility is inherently broad. If Gustave itself is compromised, an attacker can
read and drive any app. Gustave reduces this by being small, offline and dependency
free, not by removing the privilege. A self-signed build is not notarized: it is meant
to be built by its user from source.

## Verification checklist

- `swift test` passes.
- `scripts/verify.sh` passes: valid signature, hardened runtime, no entitlements, only
  system libraries, no networking symbols, no open internet sockets while running.
- Hector shows no connections for Gustave.
- Accessibility grant survives two consecutive `scripts/build-app.sh` runs.
- Idle CPU is zero and wakeups are near zero (`top -pid` or `powermetrics`; recorded measurements are TASKS.md, M5.1).

## Reporting

Use GitHub's private vulnerability reporting on this repository (Security, Report a vulnerability).
