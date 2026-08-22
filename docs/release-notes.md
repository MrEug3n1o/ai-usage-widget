Second release. Small, and all of it in the accounts panel.

**What changed since v0.1.0**

- The accounts panel now has a **Codex** section. Codex was always collected —
  the app reads the Codex CLI's own ChatGPT login — but the panel said nothing
  about it, so it looked as though Codex were unsupported next to the Claude
  and Cursor sections that do take input. It now reports whether the CLI is
  installed and which account it holds, and says there is nothing to add.
- Opening the accounts window no longer puts the keyboard focus in the Cursor
  secret field. AppKit hands the first responder to the first text field it
  finds; a window for listing accounts opened with a password box active.

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
