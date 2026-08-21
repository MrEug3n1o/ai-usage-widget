import Foundation
import UsageModel

/// Fans out over every configured provider and returns one `Provider` each.
///
/// Port of `collect_all` in the Tauri widget's collector/mod.rs, itself a port
/// of cli/usage_monitor.py. The invariant that matters: a `collect*` never
/// throws out of here. A failure comes back as a `Provider` carrying `error`,
/// so one dead provider cannot blank the panel.
public enum Collector {
    /// The 5h quota window, also the horizon for trusting a `.claude.json` mtime.
    static let claudeSessionSeconds: TimeInterval = 5 * 3600
    /// Environments whose configs are this close apart are both taken as in use.
    static let claudeConfigTieSeconds: TimeInterval = 600

    public static func collectAll() -> [Provider] {
        var providers: [Provider] = []
        for dir in claudeProfiles() {
            providers.append(Claude.collect(profileDir: dir))
        }
        providers.append(Codex.collect())
        providers.append(Cursor.collect())
        markStandby(&providers)
        return providers
    }

    /// Each Claude account lives in its own subdirectory of
    /// ~/.config/ai-usage-monitor/claude/, holding .credentials.json.
    static func claudeProfiles() -> [URL] {
        let dirs = (try? FileManager.default.contentsOfDirectory(
            at: Config.claudeDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        return dirs
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Flags the Claude accounts that are not the one currently burning quota.
    /// Not yet ported — see PLAN.md. Until it is, nothing is flagged, which is
    /// the same thing `mark_standby` does when it cannot tell the accounts
    /// apart, so the placeholder is honest rather than wrong.
    static func markStandby(_ providers: inout [Provider]) {
        // TODO(phase-1): port mark_standby / active_claude_emails.
    }
}
