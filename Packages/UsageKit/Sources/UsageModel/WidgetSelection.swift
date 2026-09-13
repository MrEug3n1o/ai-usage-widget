import Foundation

/// The three providers the combined widget always shows, in display order.
public enum AIProviderKind: String, CaseIterable, Sendable {
    case cursor = "Cursor"
    case codex = "Codex"
    case claude = "Claude"
}

/// One column of the Batteries-style widget: ring fill + reset time, no labels.
public struct ProviderUsageIndicator: Equatable, Sendable {
    public var kind: AIProviderKind
    /// Remaining quota in 0...1. `nil` means unavailable / not configured.
    public var remainingFraction: Double?
    public var resetAt: Date?

    public init(kind: AIProviderKind, remainingFraction: Double? = nil, resetAt: Date? = nil) {
        self.kind = kind
        self.remainingFraction = remainingFraction
        self.resetAt = resetAt
    }

    public var isAvailable: Bool { remainingFraction != nil }
}

/// Urgency derived from *remaining* capacity — battery semantics, not used %.
public enum RemainingSeverity: Sendable, Equatable {
    case normal, low, critical, unavailable

    /// Thresholds are easy to retune: green above 25%, orange above 10%, else red.
    public init(remainingFraction: Double?) {
        guard let remainingFraction else { self = .unavailable; return }
        if remainingFraction > 0.25 { self = .normal }
        else if remainingFraction > 0.10 { self = .low }
        else { self = .critical }
    }
}

/// Selection helpers for the combined widget. Kept out of SwiftUI views so the
/// "lowest remaining wins" rule can be unit-tested without WidgetKit.
public enum WidgetSelection {
    /// Remaining quota fraction for a meter whose `percent` is used quota.
    public static func remainingFraction(of meter: Meter) -> Double? {
        guard let percent = meter.percent else { return nil }
        return min(max(1 - percent / 100, 0), 1)
    }

    /// The currently most restrictive window: lowest remaining capacity.
    public static func tightestWindow(from meters: [Meter]) -> Meter? {
        meters
            .compactMap { meter -> (Meter, Double)? in
                guard let remaining = remainingFraction(of: meter) else { return nil }
                return (meter, remaining)
            }
            .min { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Build the three fixed columns from a live snapshot.
    public static func indicators(from providers: [Provider]) -> [ProviderUsageIndicator] {
        AIProviderKind.allCases.map { kind in
            indicator(for: kind, from: providers)
        }
    }

    public static func indicator(for kind: AIProviderKind, from providers: [Provider]) -> ProviderUsageIndicator {
        let matches = providers.filter { $0.name == kind.rawValue && !$0.isUnconfigured }
        guard !matches.isEmpty else {
            return ProviderUsageIndicator(kind: kind)
        }

        // Prefer accounts that are actively burning quota; fall back to standby.
        let active = matches.filter { !$0.standby }
        let pool = active.isEmpty ? matches : active

        // Across accounts of the same provider, still pick the tightest window.
        var best: (Meter, Double)?
        for provider in pool {
            guard let meter = tightestWindow(from: provider.meters),
                  let remaining = remainingFraction(of: meter)
            else { continue }
            if best == nil || remaining < best!.1 {
                best = (meter, remaining)
            }
        }

        guard let best else {
            // Configured but no numeric meters (auth error, etc.): unavailable look.
            return ProviderUsageIndicator(kind: kind)
        }
        return ProviderUsageIndicator(
            kind: kind,
            remainingFraction: best.1,
            resetAt: best.0.resetAt.flatMap(Formatting.parseISO))
    }
}
