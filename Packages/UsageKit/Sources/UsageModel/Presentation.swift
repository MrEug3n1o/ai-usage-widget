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
