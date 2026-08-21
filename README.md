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

## Building

Requirements: Xcode 26+, macOS 14+.

```bash
open AIUsageWidget.xcodeproj
```

Signing works with a free Apple personal team for local use. See PLAN.md § *The one real unknown*
for what a paid membership does and does not change.
