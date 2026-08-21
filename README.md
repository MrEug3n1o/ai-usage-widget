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

## Relationship to `ai-usage-monitor`

`../ai-usage-monitor` keeps `cli/usage_monitor.py`, the headless collector and the **reference
implementation of the data contract**. The `Provider` / `Meter` JSON shape, the user-visible meter
labels, and the `details` strings must stay identical between the two — changing one means changing
the other.

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
