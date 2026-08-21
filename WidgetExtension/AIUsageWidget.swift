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
    private let store = AppGroupSnapshotStore()

    private func read() -> Entry {
        do { return Entry(date: Date(), snapshot: try store.load(), error: nil) }
        catch { return Entry(date: Date(), snapshot: nil, error: error.localizedDescription) }
    }

    func placeholder(in context: Context) -> Entry { read() }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The host pushes reloads while it runs; this is the fallback so a dead
        // host produces a visibly stale widget rather than a frozen fresh one.
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(300))))
    }
}

// MARK: - Metrics

/// Point sizes chosen from how many rows have to fit. A widget showing two
/// accounts has room to be read from across the desk; one showing five does
/// not, and shrinking beats clipping.
private struct Metrics {
    var ring: CGFloat
    var ringLine: CGFloat
    var name: CGFloat
    var caption: CGFloat
    var summary: CGFloat
    var meterLabel: CGFloat
    var percent: CGFloat
    var bar: CGFloat
    var spacing: CGFloat
    var padding: CGFloat

    static func rows(_ count: Int) -> Metrics {
        switch count {
        case ...2:
            Metrics(ring: 54, ringLine: 6, name: 17, caption: 13, summary: 14,
                    meterLabel: 13, percent: 15, bar: 8, spacing: 14, padding: 16)
        case 3:
            Metrics(ring: 44, ringLine: 5, name: 15, caption: 12, summary: 13,
                    meterLabel: 12, percent: 14, bar: 7, spacing: 11, padding: 15)
        default:
            Metrics(ring: 36, ringLine: 4, name: 13, caption: 11, summary: 11,
                    meterLabel: 11, percent: 12, bar: 6, spacing: 8, padding: 14)
        }
    }
}

// MARK: - Pieces

/// Severity as a fill style. On the desktop macOS renders widgets in `.vibrant`
/// mode, which flattens every hue to the same luminance — so urgency cannot be
/// carried by color there. Hue is used where it survives (Notification Center,
/// full colour) and weight carries it everywhere else.
private struct SeverityStyle {
    let mode: WidgetRenderingMode
    let severity: Severity
    let accent: Color

    var fill: AnyShapeStyle {
        guard mode == .fullColor else {
            // Vibrant: the only axis left is how solid the fill reads.
            switch severity {
            case .critical: return AnyShapeStyle(.primary)
            case .warning:  return AnyShapeStyle(.primary.opacity(0.75))
            case .normal:   return AnyShapeStyle(.secondary)
            case .unknown:  return AnyShapeStyle(.tertiary)
            }
        }
        return AnyShapeStyle(severity.color(accent: accent))
    }
}

private struct Bar: View {
    let meter: Meter
    let style: SeverityStyle
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.tertiary)
                Capsule()
                    .fill(style.fill)
                    .frame(width: max(3, geo.size.width * meter.fraction))
            }
        }
        .frame(height: height)
        .widgetAccentable()
    }
}

/// A ring with the percentage inside, mirroring the system Batteries widget.
private struct Ring: View {
    let meter: Meter
    let style: SeverityStyle
    var diameter: CGFloat = 56
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(.tertiary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: meter.fraction)
                .stroke(style.fill, style: .init(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((meter.percent ?? 0).rounded()))")
                .font(.system(size: diameter * 0.40, weight: .medium))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: diameter, height: diameter)
        .widgetAccentable()
    }
}

private struct MeterRow: View {
    let meter: Meter
    let style: SeverityStyle
    let showReset: Bool
    let metrics: Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(meter.label)
                    .font(.system(size: metrics.meterLabel))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if showReset {
                    let left = Formatting.resetRemaining(meter.resetAt)
                    if !left.isEmpty {
                        Text(left)
                            .font(.system(size: metrics.meterLabel))
                            .foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Text(meter.displayPercent)
                    .font(.system(size: metrics.percent, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Bar(meter: meter, style: style, height: metrics.bar)
        }
    }
}

/// One account: who it is, what tier, and its meters. The identity line is the
/// point — two Claude accounts must never render identically.
private struct ProviderBlock: View {
    let provider: Provider
    let mode: WidgetRenderingMode
    let showReset: Bool
    let metrics: Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(provider.shortLabel)
                    .font(.system(size: metrics.name, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if provider.standby {
                    Text("standby")
                        .font(.system(size: metrics.caption - 2, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
                Spacer(minLength: 4)
                Text(provider.caption)
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).layoutPriority(-1)
            }
            if let error = provider.error {
                Text(error)
                    .font(.system(size: metrics.summary)).foregroundStyle(.secondary)
                    .lineLimit(2).minimumScaleFactor(0.9)
            } else {
                ForEach(provider.meters, id: \.self) { meter in
                    MeterRow(
                        meter: meter,
                        style: SeverityStyle(mode: mode, severity: meter.severity,
                                             accent: provider.accent),
                        showReset: showReset, metrics: metrics)
                }
            }
        }
        .opacity(provider.standby ? 0.55 : 1)
    }
}

/// Medium is 329x155pt — two accounts with two bars each does not fit, and the
/// previous attempt clipped the last bar. A ring for the most urgent meter plus
/// a one-line summary of the rest carries the same information in half the
/// height.
private struct CompactRow: View {
    let provider: Provider
    let mode: WidgetRenderingMode
    let metrics: Metrics

    var body: some View {
        HStack(spacing: 10) {
            // Fixed width whether or not there is a ring, so a provider with no
            // meters does not shunt its text out of the column.
            Group {
                if let primary = provider.primaryMeter {
                    Ring(meter: primary,
                         style: SeverityStyle(mode: mode, severity: primary.severity,
                                              accent: provider.accent),
                         diameter: metrics.ring, lineWidth: metrics.ringLine)
                } else {
                    Circle().stroke(.quaternary, lineWidth: metrics.ringLine)
                        .frame(width: metrics.ring, height: metrics.ring)
                }
            }
            .frame(width: metrics.ring)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(provider.shortLabel)
                        .font(.system(size: metrics.name, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(provider.caption)
                        .font(.system(size: metrics.caption)).foregroundStyle(.secondary)
                        .lineLimit(1).layoutPriority(-1)
                }
                Text(provider.summaryLine)
                    .font(.system(size: metrics.summary))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
        }
        .opacity(provider.standby ? 0.55 : 1)
    }
}

// MARK: - Widget

struct AIUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    var entry: Entry

    private var providers: [Provider] {
        (entry.snapshot?.providers ?? []).filter { !$0.isUnconfigured }
    }

    /// How many blocks fit without clipping. Measured against the real widget
    /// rather than guessed — the previous version cut "Codex" in half.
    private var visibleLimit: Int { 4 }

    var body: some View {
        Group {
            if entry.snapshot == nil {
                empty
            } else if family == .systemSmall {
                small
            } else if family == .systemMedium {
                compact
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No reading").font(.subheadline.weight(.semibold))
            Text(entry.error ?? "Open AI Usage to start collecting")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
    }

    /// Stale numbers rendered plainly are worse than none: the whole point is
    /// knowing how much quota is left *now*.
    @ViewBuilder private var staleBadge: some View {
        if entry.snapshot?.isStale == true {
            Text("stale")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
        }
    }

    private var small: some View {
        let pick = providers.compactMap { p in p.primaryMeter.map { (p, $0) } }
            .max { ($0.1.percent ?? -1) < ($1.1.percent ?? -1) }
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(pick?.0.shortLabel ?? "AI Usage")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                staleBadge
            }
            Spacer(minLength: 8)
            if let (provider, meter) = pick {
                Ring(meter: meter,
                     style: SeverityStyle(mode: mode, severity: meter.severity,
                                          accent: provider.accent),
                     diameter: 84, lineWidth: 9)
                Spacer(minLength: 8)
                Text("\(provider.name) · \(meter.label)")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("Nothing configured").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
        }
        .padding(14)
    }

    private var compact: some View {
        let shown = Array(providers.prefix(3))
        let hidden = providers.count - shown.count
        let metrics = Metrics.rows(shown.count)
        return VStack(alignment: .leading, spacing: metrics.spacing) {
            ForEach(shown, id: \.self) { provider in
                CompactRow(provider: provider, mode: mode, metrics: metrics)
            }
            if hidden > 0 || entry.snapshot?.isStale == true {
                HStack(spacing: 4) {
                    staleBadge
                    if hidden > 0 {
                        Text("+\(hidden) more").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        // Without this the stack sizes to its content and the spacers above
        // and below collapse to nothing, leaving the rows pinned to the top.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(metrics.padding)
    }

    private var list: some View {
        let shown = Array(providers.prefix(visibleLimit))
        let hidden = providers.count - shown.count
        let metrics = Metrics.rows(shown.count)
        return VStack(alignment: .leading, spacing: metrics.spacing) {
            HStack(spacing: 4) {
                Text("AI Usage")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                staleBadge
                Spacer(minLength: 0)
                if hidden > 0 {
                    Text("+\(hidden)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            ForEach(shown, id: \.self) { provider in
                ProviderBlock(provider: provider, mode: mode,
                              showReset: family == .systemLarge, metrics: metrics)
            }
            Spacer(minLength: 0)
        }
        .padding(metrics.padding)
    }
}

struct AIUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIUsageWidget", provider: UsageProvider()) {
            AIUsageWidgetView(entry: $0)
        }
        .configurationDisplayName("AI Usage")
        .description("Claude, Codex and Cursor usage limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct AIUsageWidgetBundle: WidgetBundle {
    var body: some Widget { AIUsageWidget() }
}
