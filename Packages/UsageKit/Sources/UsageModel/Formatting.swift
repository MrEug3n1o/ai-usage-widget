import Foundation

/// Presentation shared by the menu bar panel and the widget. Ports the helpers
/// that lived in the Tauri widget's main.js so the two surfaces read alike.
public enum Formatting {
    /// Time left until a limit renews, as "2d 3h" / "3h 40m" / "12m".
    /// Empty string when there is no reset (some meters have none) or the
    /// timestamp is unparseable — never a placeholder like "?" that would read
    /// as a real value. Port of `resetRemaining`.
    public static func resetRemaining(_ isoDate: String?, now: Date = Date()) -> String {
        guard let isoDate, !isoDate.isEmpty, let date = parseISO(isoDate) else { return "" }
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        if seconds >= 86_400 {
            return "\(seconds / 86_400)d \((seconds % 86_400) / 3600)h"
        }
        if seconds >= 3600 {
            return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
        }
        return "\(seconds / 60)m"
    }

    /// Providers emit a few ISO-8601 shapes; accept fractional seconds or not.
    public static func parseISO(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: text) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    /// Integer when exact, shortest useful decimal otherwise.
    ///
    /// Port of `display_number` in cli/usage_monitor.py, which is `f"{v:g}"` —
    /// C's `%g`, six significant digits. The Rust collector used `{}` instead
    /// (Swift/Rust shortest-round-trip), which agrees on ordinary values but
    /// not on float noise: 0.1+0.2 prints "0.3" here and
    /// "0.30000000000000004" there. Python is the reference, so `%g` wins.
    public static func displayNumber(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%g", value)
    }
}

/// How urgent a meter is. The thresholds are the ones the TUI, the Tauri panel
/// and the Python collector all use; keep them in step.
public enum Severity: Sendable {
    case unknown, normal, warning, critical

    public init(percent: Double?) {
        guard let percent else { self = .unknown; return }
        if percent >= 85 { self = .critical }
        else if percent >= 65 { self = .warning }
        else { self = .normal }
    }
}
