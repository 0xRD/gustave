# CLAUDE.md

Guidance for Claude Code working on Gustave.

## What this is

Gustave is a tiny, offline macOS companion for Hector (github.com/0xRD/hector). It runs
from login and provides: a Dock window list on hover, an Option+Tab window switcher, and
per-device scroll inversion. It holds the Accessibility permission, so the whole project
is organised around being small, auditable, offline and cheap on CPU.

Read, in this order: `SPEC.md`, `SECURITY.md`, `TASKS.md`, `docs/DECISIONS.md`.

## Hard rules (never break these, never "temporarily")

1. Accessibility is the only privilege. No Screen Recording, no Input Monitoring, no
   Automation, no Full Disk Access.
2. No network code of any kind. No URLSession, no sockets, no update checker, no
   analytics, no crash reporter.
3. No third-party dependencies. `Package.swift` must never gain a dependency.
4. No private or undocumented APIs. If something needs one, stop and write a proposal in
   `docs/DECISIONS.md` for the user to approve.
5. No entitlements, no privileged helper, no XPC service. Hardened runtime stays on.
6. A disabled feature is removed, not paused: its monitor or event tap is uninstalled.
7. No timers or polling in steady state. Idle wakeups must be near zero.
8. Text that comes from other apps (window titles, app names) is untrusted. It is only
   ever sanitised and rendered as plain text.
9. Do not add features that are not in `SPEC.md` without asking.

## Architecture

- `Sources/GustaveCore`: pure logic. No AppKit, no Accessibility, no I/O. Strict Swift 6
  concurrency. Everything here must be unit tested.
- `Sources/Gustave`: AppKit, SwiftUI and Accessibility glue. Thin. Logic that can be
  pure belongs in Core.
- `Tests/GustaveCoreTests`: unit tests for Core.
- `scripts/`: signing, build, verification helpers (see `TASKS.md`, M0).
- Target: macOS 15+, Apple silicon, Swift 6 toolchain.

## Workflow

Work one task at a time, in the order of `TASKS.md`.

Startup checklist, every session, before touching code:
1. `git status` and `git log --oneline -10`.
2. Read `TASKS.md` and find the current task.
3. Run `swift build` and `swift test` and report the state.
4. Say which task you will do and which acceptance criteria apply.

Quality gate before each commit (all must pass):
1. `swift build -c release` with zero warnings.
2. `swift test` passes.
3. `scripts/verify.sh` passes (once it exists, M0).
4. Acceptance criteria of the task are met, including any manual checks. Manual checks
   that need a human (granting permission, trying the UI) are listed for the user, not
   skipped or assumed.
5. Update `TASKS.md` and `docs/DECISIONS.md` if anything changed.

Then commit with a clear message and stop for review before starting the next task.

## Conventions

- Swift API design guidelines. Small files, one responsibility each.
- Comments explain why, not what. No commented-out code.
- Prefer value types and `Sendable`. `@MainActor` for anything touching AppKit.
- All calls into other processes through Accessibility use a short timeout and run off
  the main thread.
- Errors in optional features degrade silently to "feature unavailable" in the UI, never
  crash.
- No em dashes in code comments, docs or commit messages. Write plainly.

## Things to verify on a real Mac (do not guess)

Several behaviours depend on macOS internals and must be checked on device, then
recorded in `docs/DECISIONS.md`: Dock hover hit testing, scroll event field handling
with momentum, event tap permission class, Accessibility grant persistence across
rebuilds, behaviour with an auto-hiding Dock, multiple displays, Stage Manager.
