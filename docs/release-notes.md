## What changed in v0.2.3

- Restored the small, medium, and large widget descriptors. Existing widgets
  now load a timeline instead of remaining on placeholder bars.
- Ad-hoc releases use the widget container directly, avoiding repeated macOS
  requests to access data from other applications.
- Release builds no longer replace a running copy in Applications.

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
- Desktop widgets for Claude, Codex, and Cursor
- Account registration from the Claude Code logins already on the machine, and
  a Codex section saying it needs none — that comes from the Codex CLI's login
- Notifications as a limit crosses each configured threshold

**Known issue.** The app icon does not appear in the widget gallery. Cosmetic;
see PLAN.md for what has been ruled out.
