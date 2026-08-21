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
}

public extension Provider {
    /// Short, unambiguous identity for a row. Two Claude accounts must never
    /// render as two identical "Claude" lines — the account IS the information.
    var shortLabel: String {
        if !email.isEmpty, let local = email.split(separator: "@").first {
            return String(local)
        }
        return account
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
}
