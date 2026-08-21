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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.tertiary)
                Capsule()
                    .fill(style.fill)
                    .frame(width: max(3, geo.size.width * meter.fraction))
            }
        }
        .frame(height: 6)
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
                .font(.system(size: diameter * 0.34, weight: .medium))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(meter.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if showReset {
                    let left = Formatting.resetRemaining(meter.resetAt)
                    if !left.isEmpty {
                        Text(left).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Text(meter.displayPercent)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Bar(meter: meter, style: style)
        }
    }
}

/// One account: who it is, what tier, and its meters. The identity line is the
/// point — two Claude accounts must never render identically.
private struct ProviderBlock: View {
    let provider: Provider
    let mode: WidgetRenderingMode
    let showReset: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(provider.shortLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if provider.standby {
                    Text("standby")
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
                Spacer(minLength: 4)
                Text(provider.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let error = provider.error {
                Text(error)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(2).minimumScaleFactor(0.9)
            } else {
                ForEach(provider.meters, id: \.self) { meter in
                    MeterRow(
                        meter: meter,
                        style: SeverityStyle(mode: mode, severity: meter.severity,
                                             accent: provider.accent),
                        showReset: showReset)
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

    var body: some View {
        HStack(spacing: 10) {
            // Fixed width whether or not there is a ring, so a provider with no
            // meters does not shunt its text out of the column.
            Group {
                if let worst = provider.worstMeter {
                    Ring(meter: worst,
                         style: SeverityStyle(mode: mode, severity: worst.severity,
                                              accent: provider.accent),
                         diameter: 42, lineWidth: 5)
                } else {
                    Circle().stroke(.quaternary, lineWidth: 5).frame(width: 42, height: 42)
                }
            }
            .frame(width: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(provider.shortLabel)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(provider.caption)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).layoutPriority(-1)
                }
                Text(provider.summaryLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
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
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(.quaternary))
        }
    }

    private var small: some View {
        let pick = providers.compactMap { p in p.worstMeter.map { (p, $0) } }
            .max { ($0.1.percent ?? -1) < ($1.1.percent ?? -1) }
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(pick?.0.shortLabel ?? "AI Usage")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                staleBadge
            }
            Spacer(minLength: 8)
            if let (provider, meter) = pick {
                Ring(meter: meter,
                     style: SeverityStyle(mode: mode, severity: meter.severity,
                                          accent: provider.accent),
                     diameter: 68, lineWidth: 8)
                Spacer(minLength: 8)
                Text("\(provider.name) · \(meter.label)")
                    .font(.caption2).foregroundStyle(.secondary)
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
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(shown, id: \.self) { provider in
                CompactRow(provider: provider, mode: mode)
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
        .padding(14)
    }

    private var list: some View {
        let shown = Array(providers.prefix(visibleLimit))
        let hidden = providers.count - shown.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Text("AI Usage")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                staleBadge
                Spacer(minLength: 0)
                if hidden > 0 {
                    Text("+\(hidden)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            ForEach(shown, id: \.self) { provider in
                ProviderBlock(provider: provider, mode: mode,
                              showReset: family == .systemLarge)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
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
