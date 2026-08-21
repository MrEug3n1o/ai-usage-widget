First release of the native macOS rewrite.

A menu bar app and a WidgetKit widget showing how much of your Claude, Codex
and Cursor usage limits are left, with the collector rewritten in Swift from
the Python one in [ai-usage-monitor](https://github.com/felipesja/ai-usage-monitor).

**Installing.** Open the `.dmg` and drag AI Usage to Applications. The build is
ad-hoc signed rather than notarized, so macOS will refuse it on first launch:
open **System Settings → Privacy & Security** and press **Open Anyway**, or run
`xattr -d com.apple.quarantine "/Applications/AI Usage.app"`. The warning is
accurate — nobody has vouched for this binary. Building from source takes a
couple of minutes and signs it locally with your own Apple ID.

**What's in it**

- Claude (multiple accounts), Codex and Cursor, collected natively — no Python,
  no helper processes
- Menu bar panel with session and weekly meters, renewal countdowns, and the
  standby marker showing which account is actually burning quota
- Widgets in all three sizes
- Account registration from the Claude Code logins already on the machine
- Notifications as a limit crosses each configured threshold

**Known issue.** The app icon does not appear in the widget gallery. Cosmetic;
see PLAN.md for what has been ruled out.
