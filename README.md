# AI Usage Widget — macOS

Native macOS menu bar app and WidgetKit widget for AI coding-tool usage limits (Claude, Codex,
Cursor).

> **Status: not implemented yet.** This repo currently holds the migration plan only —
> see [PLAN.md](PLAN.md).

## What this is

A Swift rewrite of the Tauri widget in
[`ai-usage-monitor/widget/`](../ai-usage-monitor/widget), replacing the WKWebView panel with:

- a **menu bar app** showing the most urgent usage percentage inline, with a native SwiftUI panel,
  notifications, and account management;
- a **WidgetKit extension** in small / medium / large, for Notification Center and the desktop.

macOS only. Windows support is dropped in the move; the Rust collector is rewritten in Swift.

## Where this comes from

This is a native rewrite of the desktop widget in
**[ai-usage-monitor](https://github.com/felipesja/ai-usage-monitor)** by
[@felipesja](https://github.com/felipesja). It is a descendant of that project rather than an
independent one: the data model, the meter labels, and most of the behaviour that took real work to
get right came from there and were ported rather than reinvented — the Claude credential mirroring
that survives the CLI rotating a refresh token, the Codex app-server fallback to the local session
cache, the standby detection that works out which of several accounts is actually burning quota.

That project's `cli/usage_monitor.py` remains the **reference implementation of the data contract**,
and the two are kept in step deliberately: `Scripts/parity.sh` diffs this app's collection against
it, and a divergence in the `Provider` / `Meter` shape, the meter labels, or the `details` strings is
treated as a bug here rather than a difference of opinion.

What is new here is the macOS half — a Swift collector in place of the Python and Rust ones, a
SwiftUI menu bar app, and a WidgetKit extension. Licensed MIT, as the original is.

## Installing

Download the `.dmg` from [Releases](../../releases), open it, and drag **AI
Usage** to Applications.

**The first launch needs one extra step.** The app is ad-hoc signed rather than
notarized — there is no paid Apple Developer membership behind it — so macOS
quarantines it and refuses to open it:

1. Open it once. macOS says it "cannot be opened because Apple cannot check it
   for malicious software".
2. Go to **System Settings → Privacy & Security**, scroll to Security, and
   press **Open Anyway** next to the message about AI Usage.
3. Confirm.

Or, equivalently, from a terminal:

```bash
xattr -d com.apple.quarantine "/Applications/AI Usage.app"
```

That is the whole cost of the app being unsigned. It is worth understanding
rather than clicking through: Gatekeeper is telling you the truth, which is
that nobody has vouched for this binary. If you would rather not take that on
faith, build it yourself — see below — which takes a couple of minutes and
signs it locally with your own Apple ID.

Then:

- The app runs in the menu bar with no Dock icon. Click the gauge icon for the
  panel, and ⚙ inside it to register accounts.
- For the widget: **Edit Widgets** (right-click the desktop, or click the clock
  to open Notification Center) → search **AI Usage** → pick a size.

## Building

Requirements: Xcode 26+, macOS 14+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
xcodegen generate
open AIUsageWidget.xcodeproj
```

Signing works with a free Apple personal team: set it in Signing &
Capabilities. Building the AIUsage scheme installs to `/Applications` as a
post-action, which is what lets the widget gallery see fresh code — widgets
never load from DerivedData.

```bash
Packages/UsageKit && swift test    # the unit tests, ~0.03s
Scripts/parity.sh                  # diff the collection against usage_monitor.py
Scripts/make-icon.sh               # regenerate the app icon
Scripts/release.sh 1.0.0           # build an unsigned release DMG
```

### A note on the App Group

The widget extension is sandboxed and cannot collect anything itself — no
Keychain, no config dir, no subprocesses — so the app collects and leaves a
snapshot for it. That normally travels through an App Group, which is a
restricted entitlement that ad-hoc signing cannot carry, so a downloaded
release would otherwise show a permanently empty widget.

The snapshot is therefore written to the widget's own sandbox container as
well, which needs no entitlement, and the widget reads whichever channel
answers. See [docs/data-channel.md](docs/data-channel.md).
