# Gustave

A tiny, offline macOS companion for Hector. Hover an app in the Dock to list its
windows, switch windows with Option+Tab, and invert scrolling per device. It needs
Accessibility and nothing else.

Status: **project scaffold only, no application code yet.** Implementation is driven by
`TASKS.md` with Claude Code, see `docs/KICKOFF_PROMPT.md`.

No Screen Recording, no network, no dependencies, no auto-update. See
[SECURITY.md](SECURITY.md) for the threat model and [SPEC.md](SPEC.md) for behaviour.

## Repository map

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Rules and workflow for Claude Code |
| `SPEC.md` | Product spec, acceptance criteria, implementation notes |
| `SECURITY.md` | Threat model, hard rules, verification checklist |
| `TASKS.md` | Milestones M0 to M5 with acceptance criteria |
| `docs/DECISIONS.md` | Decision log and things verified on device |
| `docs/KICKOFF_PROMPT.md` | First prompt for a Claude Code session |
| `Package.swift` | SwiftPM manifest, zero dependencies, Core plus app target |
| `Sources/GustaveCore` | Pure logic (empty) |
| `Sources/Gustave` | AppKit and Accessibility glue (empty) |
| `Tests/GustaveCoreTests` | Core unit tests (empty) |
| `scripts/` | Cert, build, verify, icon helpers (to be written in M0) |
| `Resources/` | `Info.plist`, `icon.svg`, `icon-1024.png` |

## Planned build flow (after M0)

```sh
scripts/make-cert.sh     # once: stable local signing identity
swift test
scripts/build-app.sh     # builds and signs build/Gustave.app
scripts/verify.sh        # security checks
```

Requires macOS 15, Apple silicon, Xcode 16 command line tools.

License: intended GPL-3.0-or-later to match Hector. LICENSE is added in M0.7.
