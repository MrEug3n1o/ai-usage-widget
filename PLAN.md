# Plan — native macOS menu bar app + WidgetKit widget

## Context

This repo replaces the Tauri widget that currently lives at
`../ai-usage-monitor/widget/`. That widget works, but it is a WKWebView pretending to be a native
one: no Notification Center presence, no desktop widget, no menu bar glance value, and a whole
webview process for what is ultimately three progress bars.

**Goal:** a Swift menu bar app showing the most urgent usage percentage directly in the menu bar,
plus a **WidgetKit extension** so the numbers are available in Notification Center and on the
desktop.

**Windows support is dropped.** The Tauri app's Rust collector is therefore *rewritten in Swift*
rather than bridged — the WSL config bridge, the `codex.cmd` shim, and the NSIS packaging all
disappear with it.

### What carries over from the old repo

`../ai-usage-monitor/` remains the home of `cli/usage_monitor.py`, the headless/Linux path and the
**reference implementation of the data contract**. The rule that used to read "keep Python and Rust
in sync" becomes **keep Python and Swift in sync**: the `Provider` / `Meter` JSON shape, the
user-visible meter labels, and the `details` strings must stay identical across both.

Source material for the port (read these, don't re-derive them):

| What | Where |
|---|---|
| Contract, `collect_all`, standby detection | `../ai-usage-monitor/widget/src-tauri/src/collector/mod.rs` |
| Claude OAuth, token refresh, **credential mirroring** | `.../collector/claude.rs` |
| Codex app-server JSON-RPC + session-cache fallback | `.../collector/codex.rs` |
| Cursor admin-key / dashboard-cookie | `.../collector/cursor.rs` |
| Config store, alert thresholds | `.../collector/config.rs` |
| Keychain / credential-file detection, add/remove | `.../src-tauri/src/accounts.rs` |
| Panel rendering, alert latch, accounts view | `.../widget/src/main.js` |
| Reference behavior for everything above | `../ai-usage-monitor/cli/usage_monitor.py` |

### The one real unknown

A WidgetKit extension is normally sandboxed, so it cannot read `~/.config/ai-usage-monitor/`, reach
the Keychain, or spawn `codex`. Collection must therefore happen in the (unsandboxed) host app,
which writes a snapshot the widget reads.

The supported channel for that is an **App Group**, which free personal teams cannot enable — and
the signing identity on this machine (`Apple Development`, team `VG87LBRMTR`) does not reveal
whether the membership is paid.

Worth being clear about what the $99/yr actually buys, because it is less than it first appears:

- **Not required** to build this and run it daily on your own Mac. A free personal team signs a
  *Mac* app that runs indefinitely — the 7-day expiry is an iOS device-provisioning limit.
- **Required** for App Groups, and for Developer ID + notarization (i.e. for other people to install
  a prebuilt binary without Gatekeeper friction). Anyone else can still build from source with their
  own free team.

Phase 0 settles the channel empirically. Everything downstream is written against a `SnapshotStore`
protocol, so swapping channels is a single-file change.

## Phase 0 — Spike the data channel

Do this first, throw the code away. Minimal Xcode project: host app + widget extension, nothing
else. Determine, in order:

1. Can the widget extension be built **unsandboxed** (drop `com.apple.security.app-sandbox`) and
   still load? If yes it reads the config dir directly and no snapshot channel is needed at all.
2. If not: can the unsandboxed host write into `~/Library/Containers/<ext-bundle-id>/Data/`, and can
   the extension read it back? Needs no entitlement.
3. If not: App Groups — which confirms a paid membership is required.

Also confirm here:

- A free-team-signed Mac app still launches after 7 days.
- `WidgetCenter.shared.reloadAllTimelines()` from a running host refreshes at a useful cadence.
  Expect **minutes-fresh in the widget, live in the menu bar panel** — the widget is glanceable, not
  real-time. Do not design around live widget numbers.

**Output:** a decision recorded in `docs/data-channel.md`, plus the chosen `SnapshotStore`
implementation.

## Phase 1 — Skeleton and Swift port of the collector

`AIUsageWidget.xcodeproj` with three targets and a local Swift package (`Packages/UsageKit`)
exposing two products:

- **`UsageModel`** — `Provider`, `Meter`, `Snapshot` (providers + `capturedAt`), `Codable` with
  exactly the JSON shape `collector/mod.rs` serializes today, plus the formatting helpers currently
  duplicated between `main.js` and Rust (`resetRemaining`, `displayNumber`, severity colors).
  Linked by both the app and the widget.
- **`UsageCollector`** — depends on `UsageModel`; linked by the app only.

Port module by module, verifying each against the Python before moving on:

| From (Rust) | To (Swift) | Notes |
|---|---|---|
| `mod.rs` — `collect_all`, `mark_standby`, `active_claude_emails` | `UsageCollector/Collector.swift` | `TaskGroup` replaces `thread::scope`. **Delete all three `other_side_claude_configs` variants** — macOS has no second side, so it collapses to `default_claude_source` + `custom_dir_claude_configs`. Keep the `history.jsonl` liveness signal and the `CLAUDE_CONFIG_TIE_SECONDS` tolerance verbatim. |
| `claude.rs` | `UsageCollector/Claude.swift` | `URLSession` async. **Port `ensure_fresh` and `source.json` exactly** — the refresh-token rotation race against the Claude Code CLI is the subtlest logic in the project, and re-deriving it will reintroduce the bug it fixed. |
| `codex.rs` | `UsageCollector/Codex.swift` | `Process` + `Pipe` for the JSON-RPC app-server. Drop `codex_command`'s `.cmd` / `CREATE_NO_WINDOW` branch. **Keep `find_codex`'s nvm / Homebrew / `~/.local/bin` search** — a GUI app still gets a minimal launchd PATH. Keep the session-cache fallback and its `details` downgrade note. |
| `cursor.rs` | `UsageCollector/Cursor.swift` | Both methods, including the team dashboard's divide-by-4 `request_scale`. |
| `config.rs` | `UsageCollector/Config.swift` | `FileManager` with explicit `posixPermissions` 0700/0600. Keep `normalize_thresholds` and the write-defaults-on-first-read behavior. |
| `date.rs` | **deleted** | `ISO8601DateFormatter` + `Calendar` replace 134 lines of hand-rolled civil-date math. |
| `accounts.rs` | `UsageCollector/Accounts.swift` | Improvement available: replace `security dump-keychain` with `SecItemCopyMatching` using `kSecReturnAttributes` and *not* `kSecReturnData` — that enumerates metadata without prompting, and only the Add path (`kSecReturnData`) triggers the permission dialog. Same `Candidate` / `Detection` / `Registered` shapes, same dedup and `profile_name` collision suffixing. |

Give the app a `--probe` flag mirroring the Tauri one, so parity is checkable from a terminal.

**Parity gate — do not start Phase 2 until this passes:**

```
diff <(python3 ../ai-usage-monitor/cli/usage_monitor.py once --json) \
     <(/Applications/AIUsageWidget.app/Contents/MacOS/AIUsageWidget --probe)
```

must differ only in timing-dependent fields.

## Phase 2 — Menu bar app

- `MenuBarExtra(content:label:)` with `.menuBarExtraStyle(.window)`, targeting macOS 14. This
  deletes the old `main.rs`'s entire monitor-containment and positioning block (~80 lines) — the
  system anchors the panel to the status item.
- **Label: icon + live percentage** of the most urgent meter. `MenuBarExtra`'s label takes a view,
  so an `HStack { Image; Text }`; if severity tinting fights template-image rendering, fall back to
  a rendered `NSImage` via `ImageRenderer`.
- Panel: SwiftUI port of `render()` in `main.js` — per-provider accent, bars, `%`, reset time,
  `◉ STANDBY`, and the `isUnconfigured` hiding rule.
- Alerts: port `checkAlerts`'s per-meter high-water mark and `REARM_MARGIN` re-arm to
  `UNUserNotificationCenter`, reading levels from `Config.alertThresholds()`.
- Login item: `SMAppService.mainApp.register()` replaces `tauri-plugin-autostart`.
- `NSApp.setActivationPolicy(.accessory)` — no Dock icon.
- Poll loop writes the snapshot via `SnapshotStore`, then `WidgetCenter.shared.reloadAllTimelines()`.

## Phase 3 — Accounts settings window

Native `Settings` scene, reachable from the panel and the menu bar. Port the accounts view from
`main.js:267-429` and the commands in `accounts.rs`: list detected sources, Add (behind the Keychain
prompt), Remove, and the Cursor admin-key / dashboard-cookie form with the same validation as
`save_cursor`. Secrets stay out of logs and out of process arguments.

## Phase 4 — WidgetKit extension

`TimelineProvider` reads the snapshot via `SnapshotStore`; single entry, refresh policy
`.after(now + 5min)` so it degrades gracefully if the host app dies. Show a staleness indicator once
the snapshot is older than ~10 minutes — stale numbers must not look fresh.

- **`.systemSmall`** — the single most-used meter as a `Gauge`, provider-tinted.
- **`.systemMedium`** — one row per configured provider: name, bar, percentage.
- **`.systemLarge`** — every meter with reset times, mirroring the panel.

No interactivity in v1 (widgets have no text fields). A refresh `Button` via AppIntent is a possible
follow-up.

## Phase 5 — Retire the Tauri widget (in the other repo)

- Delete `../ai-usage-monitor/widget/`.
- Rewrite that repo's `CLAUDE.md`: Tauri sections go; the contract rule becomes Python + Swift, with
  a pointer to this repo.
- Update its `README.md` and replace the `docs/*.png` screenshots (they show the Tauri panel).

## Verification

1. **Collector parity** — the `--probe` diff from Phase 1, re-run after every collector change.
2. **Multi-account standby** — with two Claude profiles registered, use the CLI on one and confirm
   the other shows `◉ STANDBY` in both the panel and the widget, matching `ai-usage once`.
3. **Refresh-race regression** — the highest-value manual test. Let a profile's token approach expiry
   while the Claude Code CLI uses that same login, then refresh: the profile must adopt the source's
   token rather than dying with `invalid_grant`.
4. **Codex fallback** — rename the `codex` binary off PATH; the app must fall back to the session
   cache and say so in `details`, not error.
5. **Alerts** — set `alert_thresholds` low in `config.json`; one notification per level crossed, and
   no repeat while a meter sits parked on a boundary.
6. **Widget freshness** — add all three sizes from Notification Center and the desktop; confirm they
   track the menu bar within a few minutes, and that quitting the host app produces the staleness
   indicator.
7. **Cold boot** — reboot; `SMAppService` should start the app and the widgets should populate
   without opening the panel.

## Risks

- **Phase 0 is load-bearing.** If all three channels fail, the widget requires a paid membership.
  Everything else still stands and the menu bar app ships regardless.
- **WidgetKit refresh cadence is not guaranteed.** The menu bar is the live surface; the widget is
  glanceable. Don't promise live widget numbers.
- **`ensure_fresh` is easy to get subtly wrong in translation.** Port it line by line and run
  verification #3 before trusting it with a daily-driver account.
