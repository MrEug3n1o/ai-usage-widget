# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## Status

Nothing is implemented yet. **Read [PLAN.md](PLAN.md) first** — it holds the full migration plan,
the source files to port from, and the phase order. Phase 0 (spiking the host→widget data channel)
gates the rest of the design and must be settled before porting begins.

## Language

Comments, user-visible strings, error messages, and docs are in **English**. Keep that standard.

## The data contract

This project is one of **two implementations of the same contract**. The other is
`../ai-usage-monitor/cli/usage_monitor.py`, the headless path and the reference implementation.

When changing the shape of `Provider` / `Meter`, the user-visible meter labels, or the `details`
strings, **change both** — the two surfaces must read alike. The Python side is authoritative when
they disagree.

## Architecture (target)

- `Packages/UsageKit` — local Swift package, two products:
  - `UsageModel` — `Provider`, `Meter`, `Snapshot`, formatting helpers. Linked by the app *and* the
    widget extension.
  - `UsageCollector` — Claude / Codex / Cursor collection, config store, accounts. Linked by the app
    only; the widget extension is sandboxed and cannot collect.
- App target — `MenuBarExtra` panel, notifications, `Settings` scene, poll loop.
- Widget extension — `TimelineProvider` reading a snapshot the app writes. It never collects.

Each `collect*` captures its own failure and returns a `Provider` with `error` filled in; it never
propagates.

## Security

Tokens, cookies, and keys never appear in the UI, in logs, or in process arguments. Config
directories are `0700`, credential files `0600`. Never copy credentials into chats, issues, or
commits.
