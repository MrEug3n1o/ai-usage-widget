Third release. Appearance, and a word about Codex.

**What changed since v0.1.1**

- The menu bar panel no longer reads pale next to real menu bar dropdowns.
  MenuBarExtra's own window already paints the menu material, and the panel
  set a second one on top of it; two materials composite lighter than one.
  Removing it leaves the panel with the background macOS gives it.
- The provider cards lost their tint. It sat a shade darker than the panel
  behind them, which reads as a seam rather than as grouping — the spacing
  between cards already groups them.

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
- Account registration from the Claude Code logins already on the machine, and
  a Codex section saying it needs none — that comes from the Codex CLI's login
- Notifications as a limit crosses each configured threshold

**Known issue.** The app icon does not appear in the widget gallery. Cosmetic;
see PLAN.md for what has been ruled out.
