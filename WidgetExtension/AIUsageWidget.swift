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

private struct Bar: View {
    let meter: Meter
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(meter.severity.color(accent: accent))
                    .frame(width: max(2, geo.size.width * meter.fraction))
            }
        }
        .frame(height: 4)
    }
}

private struct MeterRow: View {
    let provider: Provider
    let meter: Meter
    let showReset: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(meter.label).font(.system(size: 10))
                Spacer(minLength: 4)
                if showReset, case let left = Formatting.resetRemaining(meter.resetAt), !left.isEmpty {
                    Text(left).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                Text(meter.displayPercent)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            Bar(meter: meter, accent: provider.accent)
        }
    }
}

private struct ProviderBlock: View {
    let provider: Provider
    let showReset: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(provider.accent).frame(width: 6, height: 6)
                Text(provider.standby ? "\(provider.name) ◉" : provider.name)
                    .font(.system(size: 10, weight: .semibold))
                Spacer(minLength: 0)
            }
            if let error = provider.error {
                Text(error).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
            } else {
                ForEach(provider.meters, id: \.self) { meter in
                    MeterRow(provider: provider, meter: meter, showReset: showReset)
                }
            }
        }
    }
}

struct AIUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Entry

    private var providers: [Provider] {
        (entry.snapshot?.providers ?? []).filter { !$0.isUnconfigured }
    }

    /// What the small size shows: the meter closest to running out.
    private var worst: (Provider, Meter)? {
        providers
            .flatMap { provider in provider.meters.map { (provider, $0) } }
            .max { ($0.1.percent ?? -1) < ($1.1.percent ?? -1) }
    }

    var body: some View {
        Group {
            if entry.snapshot == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No reading").font(.caption)
                    Text(entry.error ?? "Open AI Usage to start collecting")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            } else {
                switch family {
                case .systemSmall: small
                default:           list
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("AI Usage").font(.system(size: 10, weight: .semibold))
            Spacer(minLength: 0)
            // Stale numbers rendered plainly are worse than none: the whole
            // point is knowing how much quota is left right now.
            if entry.snapshot?.isStale == true {
                Text("stale").font(.system(size: 9)).foregroundStyle(.orange)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let (provider, meter) = worst {
                Spacer(minLength: 0)
                Text(meter.displayPercent)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(meter.severity.color(accent: provider.accent))
                Text("\(provider.name) · \(meter.label)")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                Bar(meter: meter, accent: provider.accent)
            } else {
                Text("Nothing configured").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ForEach(providers, id: \.self) { provider in
                ProviderBlock(provider: provider, showReset: family == .systemLarge)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
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
