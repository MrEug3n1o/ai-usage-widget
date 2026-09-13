Fourth release. The desktop widget is now a Batteries-style glance.

**What changed since v0.1.2**

- The medium widget shows Cursor, Codex and Claude together as three equal
  columns: a remaining-quota ring, the provider mark, and a compact reset
  countdown. No email, percentages, or window labels in the widget.
- When a provider has several limits, the widget picks the tightest one
  (lowest remaining capacity) and shows only that ring and its reset time.
- Rings read as remaining capacity (battery semantics), coloured green /
  orange / red by how little is left.
- App icon refreshed to the lime→cyan open-bottom gauge with a white `%`.
- Provider marks inside the rings are the monochrome Cursor, OpenAI and
  Claude glyphs.

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
- One medium widget with all three providers at a glance (small/large too)
- Account registration from the Claude Code logins already on the machine, and
  a Codex section saying it needs none — that comes from the Codex CLI's login
- Notifications as a limit crosses each configured threshold

**Known issue.** The app icon does not appear in the widget gallery. Cosmetic;
see PLAN.md for what has been ruled out.
