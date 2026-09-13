import WidgetKit
import SwiftUI
import UsageModel

/// The extension NEVER collects — it is sandboxed and has no access to the
/// Keychain, the config dir, or subprocesses. It only reads what the host app
/// left in the App Group container. See docs/data-channel.md.
struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let error: String?
}

struct UsageProvider: TimelineProvider {
    private let store = DualSnapshotStore()

    private func read() -> Entry {
        do { return Entry(date: Date(), snapshot: try store.load(), error: nil) }
        catch { return Entry(date: Date(), snapshot: nil, error: error.localizedDescription) }
    }

    func placeholder(in context: Context) -> Entry { read() }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // Host pushes reloads while it runs; this is the fallback so a dead host
        // produces a visibly stale widget rather than a frozen fresh one.
        // Countdown text advances via TimelineView without re-fetching.
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(300))))
    }
}

// MARK: - Colors

/// Unified status language: remaining capacity, not brand accents.
private enum RingPalette {
    static func fill(for severity: RemainingSeverity, mode: WidgetRenderingMode) -> AnyShapeStyle {
        guard mode == .fullColor else {
            // Vibrant / tinted: hue collapses; weight carries urgency.
            switch severity {
            case .critical:    return AnyShapeStyle(.primary)
            case .low:         return AnyShapeStyle(.primary.opacity(0.75))
            case .normal:      return AnyShapeStyle(.secondary)
            case .unavailable: return AnyShapeStyle(.tertiary)
            }
        }
        switch severity {
        case .normal:      return AnyShapeStyle(Color.green)
        case .low:         return AnyShapeStyle(Color.orange)
        case .critical:    return AnyShapeStyle(Color.red)
        case .unavailable: return AnyShapeStyle(Color.secondary.opacity(0.45))
        }
    }

    static var track: some ShapeStyle { Color.primary.opacity(0.12) }
}

// MARK: - Icons

/// Monochrome provider marks from the asset catalog (template rendering).
private struct ProviderIcon: View {
    let kind: AIProviderKind
    var size: CGFloat = 22

    private var assetName: String {
        switch kind {
        case .cursor: return "ProviderCursor"
        case .codex:  return "ProviderCodex"
        case .claude: return "ProviderClaude"
        }
    }

    var body: some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            // Slight per-logo optical correction so the three marks read equal weight.
            .scaleEffect(kind == .codex ? 0.92 : (kind == .claude ? 0.88 : 0.95))
            .frame(width: size, height: size)
            .foregroundStyle(.primary.opacity(0.92))
    }
}

// MARK: - Indicator

/// One Batteries-style column: ring, icon, compact reset countdown. Nothing else.
struct AIUsageIndicator: View {
    let indicator: ProviderUsageIndicator
    var ringDiameter: CGFloat = 56
    var ringLine: CGFloat = 5.5
    var iconSize: CGFloat = 22
    var countdownSize: CGFloat = 12

    @Environment(\.widgetRenderingMode) private var mode

    private var severity: RemainingSeverity {
        RemainingSeverity(remainingFraction: indicator.remainingFraction)
    }

    private var fraction: Double {
        indicator.remainingFraction ?? 0
    }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(RingPalette.track, lineWidth: ringLine)
                if indicator.isAvailable {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            RingPalette.fill(for: severity, mode: mode),
                            style: StrokeStyle(lineWidth: ringLine, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                ProviderIcon(kind: indicator.kind, size: iconSize)
                    .opacity(indicator.isAvailable ? 1 : 0.40)
            }
            .frame(width: ringDiameter, height: ringDiameter)
            .widgetAccentable()

            // Advances from the cached reset date without re-collecting.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(Formatting.compactResetRemaining(
                    until: indicator.isAvailable ? indicator.resetAt : nil,
                    now: context.date))
                    .font(.system(size: countdownSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(minHeight: countdownSize + 2, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Widget

struct AIUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Entry

    private var indicators: [ProviderUsageIndicator] {
        WidgetSelection.indicators(from: entry.snapshot?.providers ?? [])
    }

    var body: some View {
        batteryRow(metrics: family == .systemSmall ? Metrics.small : Metrics.medium)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    private func batteryRow(metrics: Metrics) -> some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(indicators.enumerated()), id: \.element.kind) { _, item in
                AIUsageIndicator(
                    indicator: item,
                    ringDiameter: metrics.ring,
                    ringLine: metrics.ringLine,
                    iconSize: metrics.icon,
                    countdownSize: metrics.countdown)
            }
        }
        // Keep padding light — WidgetKit already applies content margins.
        .padding(.horizontal, metrics.hPad)
        .padding(.vertical, metrics.vPad)
    }
}

private struct Metrics {
    var ring: CGFloat
    var ringLine: CGFloat
    var icon: CGFloat
    var countdown: CGFloat
    var hPad: CGFloat
    var vPad: CGFloat

    /// Tuned against the system Batteries medium widget proportions.
    static let medium = Metrics(
        ring: 56, ringLine: 5, icon: 22,
        countdown: 11, hPad: 6, vPad: 4)

    static let small = Metrics(
        ring: 40, ringLine: 4, icon: 15,
        countdown: 10, hPad: 2, vPad: 2)
}

struct AIUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIUsageWidget", provider: UsageProvider()) {
            AIUsageWidgetView(entry: $0)
        }
        .configurationDisplayName("AI Usage")
        .description("Remaining Cursor, Codex and Claude capacity.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct AIUsageWidgetBundle: WidgetBundle {
    var body: some Widget { AIUsageWidget() }
}

#if DEBUG
#Preview("Medium", as: .systemMedium) {
    AIUsageWidget()
} timeline: {
    Entry(date: .now, snapshot: PreviewData.snapshot, error: nil)
}

#Preview("Unavailable", as: .systemMedium) {
    AIUsageWidget()
} timeline: {
    Entry(date: .now, snapshot: Snapshot(providers: []), error: nil)
}

private enum PreviewData {
    static var snapshot: Snapshot {
        let now = Date()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return Snapshot(providers: [
            Provider(name: "Cursor", account: "team", email: "you@example.com", meters: [
                Meter(label: "Total usage", percent: 35,
                      resetAt: fmt.string(from: now.addingTimeInterval(2 * 3600 + 14 * 60))),
            ]),
            Provider(name: "Codex", account: "ChatGPT", meters: [
                Meter(label: "Session", percent: 29,
                      resetAt: fmt.string(from: now.addingTimeInterval(2 * 3600))),
                Meter(label: "Weekly", percent: 82,
                      resetAt: fmt.string(from: now.addingTimeInterval(4 * 86_400))),
            ]),
            Provider(name: "Claude", account: "work", email: "you@example.com", meters: [
                Meter(label: "Session", percent: 53,
                      resetAt: fmt.string(from: now.addingTimeInterval(47 * 60))),
                Meter(label: "Weekly", percent: 20,
                      resetAt: fmt.string(from: now.addingTimeInterval(6 * 86_400))),
            ]),
        ], capturedAt: now)
    }
}
#endif
