import SwiftUI

/// Colors shared by the panel and the widget, so both surfaces read alike.
/// Ports ACCENT and meterColor from the Tauri widget's main.js.
public extension Provider {
    var accent: Color {
        switch name {
        case "Claude": return Color(red: 0.85, green: 0.47, blue: 0.29)
        case "Codex":  return Color(red: 0.10, green: 0.72, blue: 0.55)
        case "Cursor": return Color(red: 0.40, green: 0.55, blue: 0.95)
        default:       return .primary
        }
    }
}

public extension Severity {
    /// Urgency wins over the provider's accent: at 85% the color is the point.
    func color(accent: Color) -> Color {
        switch self {
        case .critical: return Color(red: 0.90, green: 0.30, blue: 0.29)
        case .warning:  return Color(red: 0.93, green: 0.66, blue: 0.20)
        case .normal:   return accent
        case .unknown:  return .secondary
        }
    }
}

public extension Meter {
    var severity: Severity { Severity(percent: percent) }
    /// Rounded for display; the bar still uses the exact value.
    var displayPercent: String { "\(Int((percent ?? 0).rounded()))%" }
    var fraction: Double { min(max((percent ?? 0) / 100, 0), 1) }

    /// The collectors report quota *used*. The widget is deliberately a
    /// battery-style view, so its ring represents the inverse: capacity left.
    /// Keep this conversion in the shared model rather than making each view
    /// rediscover the semantics of `percent`.
    var remainingFraction: Double? {
        guard let percent else { return nil }
        return 1 - min(max(percent / 100, 0), 1)
    }
}

/// The one limit a minimal provider indicator represents.
///
/// A provider can publish several independent caps (for example, a five-hour
/// and a weekly window). The least remaining capacity is the limit that will
/// constrain the user first, so it is the only useful one in the compact
/// widget. Windows without a measurement are intentionally ignored: selecting
/// an unknown value would make an unavailable ring look meaningful.
public func tightestWindow(from windows: [Meter]) -> Meter? {
    windows
        .filter { $0.remainingFraction != nil }
        .min { ($0.remainingFraction ?? 1) < ($1.remainingFraction ?? 1) }
}

public extension Provider {
    /// Identity for a row: the whole email, domain included. Two Claude
    /// accounts must never render as two identical "Claude" lines, and the
    /// domain is the half that says which account it is — work or personal.
    /// Where space runs short, truncate in the MIDDLE so the domain survives.
    var shortLabel: String {
        email.isEmpty ? account : email
    }

    /// Trailing caption: what it is, and which tier. "Claude · Max", or just
    /// "Codex" when the provider reports no plan.
    var caption: String {
        plan.isEmpty ? name : "\(name) · \(plan)"
    }

    /// One line describing the meters, or the best available explanation when
    /// there are none — never a blank line.
    var summaryLine: String {
        if !meters.isEmpty {
            return meters.map { "\($0.label) \($0.displayPercent)" }.joined(separator: " · ")
        }
        if let error { return error }
        guard let detail = details.first else { return "no limits reported" }
        // Details can carry a raw RPC payload for diagnosis. That belongs in
        // --probe output, not on a widget: keep the human half, drop the JSON.
        if let brace = detail.firstIndex(of: "{") {
            return detail[..<brace]
                .trimmingCharacters(in: CharacterSet(charactersIn: " ·:-"))
        }
        return detail
    }

    /// The meter the ring stands for when there is room for exactly one number.
    ///
    /// The rolling session window, deliberately, not whichever meter happens to
    /// read highest: the session is what governs whether the next prompt goes
    /// through, and the weekly figure would otherwise mask it for most of the
    /// week. Providers with no session (Cursor bills monthly) fall back to
    /// their first meter.
    var primaryMeter: Meter? {
        meters.first { $0.label == "Session" } ?? meters.first
    }

    /// The quota window the combined WidgetKit indicator renders. This is
    /// intentionally separate from `primaryMeter`, which keeps the app's
    /// detailed session-first presentation behavior.
    var tightestMeter: Meter? { tightestWindow(from: meters) }
}

public extension Meter {
    /// No reset time and no usage means the window has not opened yet — a
    /// Claude session only starts on the first request. The Tauri panel dims
    /// these rows rather than claiming "0%", which would read as "measured, and
    /// it is zero" instead of "not started".
    var isIdle: Bool {
        Formatting.resetRemaining(resetAt).isEmpty && (percent ?? 0) == 0
    }

    /// "Session" on its own, or "Usage 144/500" when the provider reports
    /// absolute figures. Ports the label composition in main.js's render().
    var composedLabel: String {
        guard let used, let limit else { return label }
        return "\(label) \(used)/\(limit)"
    }
}
