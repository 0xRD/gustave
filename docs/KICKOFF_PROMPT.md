# Kickoff prompt for Claude Code

Paste this as the first message of a Claude Code session in the repo root.

---

You are working on Gustave, a tiny offline macOS companion app for Hector. Before doing
anything else, read `CLAUDE.md`, `SPEC.md`, `SECURITY.md`, `TASKS.md` and
`docs/DECISIONS.md` in full. `CLAUDE.md` rules are hard rules.

Run the startup checklist from `CLAUDE.md` and report the state of the repo and the
current task before touching any code.

This session's scope is milestone M0 only (foundations and the accessory app shell).
Do the tasks one at a time, in order. After each task:
1. Run the quality gate from `CLAUDE.md`.
2. Tick the task in `TASKS.md`.
3. Commit.
4. Tell me which acceptance criteria were checked by you and which need me to check
   manually on the Mac (permission prompts, UI), with exact steps.

Stop at the end of M0 and wait for my review. Do not start M1.

If anything in the spec is ambiguous or conflicts with a hard rule, stop and ask rather
than choosing. Do not add dependencies, network code, private APIs or entitlements.
Anything you cannot verify without a real Mac (Accessibility behaviour, scroll events,
Dock hit testing) must be written down as a manual check, not assumed.

---

Later sessions: same prompt, with the scope changed to the next milestone.
