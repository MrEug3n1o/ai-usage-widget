import WidgetKit
import SwiftUI
import UsageModel

/// The extension only renders the snapshot its host app writes to the shared
/// container. It never reaches into a provider's credentials or APIs.
struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct UsageProvider: TimelineProvider {
    private let store = DualSnapshotStore()

    private func read(at date: Date = .now) -> Entry {
        Entry(date: date, snapshot: try? store.load())
    }

    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(read())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let snapshot = try? store.load()
        let entries = (0...60).map { minute in
            Entry(date: now.addingTimeInterval(TimeInterval(minute * 60)), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(61 * 60))))
    }
}

private enum AIProvider: String, CaseIterable, Identifiable {
    case cursor = "Cursor"
    case codex = "Codex"
    case claude = "Claude"

    var id: String { rawValue }

    /// Initials are intentional. Brand or SF symbols can fail to render in a
    /// widget's vibrancy/tinted modes; a letter keeps the card identifiable.
    var mark: String { String(rawValue.prefix(1)) }
}

private struct ProviderReading {
    let meter: Meter

    var remainingFraction: Double { meter.remainingFraction ?? 0 }
    var usedPercent: String { meter.percent.map { "\(Int($0.rounded()))%" } ?? "—" }
    var resetText: String {
        let text = Formatting.resetRemaining(meter.resetAt)
        return text.isEmpty ? "No reset time" : "Resets \(text)"
    }
}

private extension Snapshot {
    /// One actionable window per provider. For a provider with multiple
    /// accounts, surface the account closest to its limit.
    func reading(for provider: AIProvider) -> ProviderReading? {
        providers
            .filter { $0.name == provider.rawValue }
            .compactMap { $0.tightestMeter.map(ProviderReading.init) }
            .min { $0.remainingFraction < $1.remainingFraction }
    }
}

private enum CapacityStyle {
    static func color(for remainingFraction: Double?) -> Color {
        guard let remainingFraction else { return .secondary }
        switch remainingFraction {
        case ...0.10: return .red
        case ...0.25: return .orange
        default: return .green
        }
    }
}

private struct UsageRing: View {
    let reading: ProviderReading?

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 6)
            if let reading {
                Circle()
                    .trim(from: 0, to: reading.remainingFraction)
                    .stroke(
                        CapacityStyle.color(for: reading.remainingFraction),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            Text(reading?.usedPercent ?? "—")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .foregroundStyle(reading == nil ? .tertiary : .primary)
        }
        .frame(width: 62, height: 62)
        .accessibilityLabel(reading.map { "\($0.usedPercent) used" } ?? "No reading")
    }
}

private struct ProviderCard: View {
    let provider: AIProvider
    let reading: ProviderReading?

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 4) {
                Text(provider.mark)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(.quaternary))
                Text(provider.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            UsageRing(reading: reading)

            Text(reading?.resetText ?? "Not configured")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(reading == nil ? .tertiary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct AIUsageWidgetView: View {
    var entry: Entry

    private var status: String {
        guard let snapshot = entry.snapshot else { return "Waiting for data" }
        return snapshot.isStale ? "Data may be stale" : "Used"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI Usage")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
              HStack(spacing: 6) {
                ForEach(AIProvider.allCases) { provider in
                    ProviderCard(provider: provider, reading: entry.snapshot?.reading(for: provider))
                }
              }
              VStack(spacing: 6) {
                ForEach(AIProvider.allCases) { provider in
                    HStack {
                        Text(provider.rawValue).font(.caption.bold())
                        Spacer()
                        Text(entry.snapshot?.reading(for: provider)?.usedPercent ?? "—")
                            .font(.caption.monospacedDigit())
                    }
                }
              }
            }
        }
        .padding(14)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct AIUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIUsageWidget", provider: UsageProvider()) {
            AIUsageWidgetView(entry: $0)
        }
        .configurationDisplayName("AI Usage")
        .description("Usage used and reset times for your AI tools.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct AIUsageWidgetBundle: WidgetBundle {
    var body: some Widget { AIUsageWidget() }
}

#Preview(as: .systemMedium) {
    AIUsageWidget()
} timeline: {
    Entry(date: .now, snapshot: Snapshot(providers: [
        Provider(name: "Cursor", account: "preview", meters: [
            Meter(label: "Usage", percent: 35, resetAt: "2026-09-14T12:14:00Z"),
        ]),
        Provider(name: "Codex", account: "preview", meters: [
            Meter(label: "Session", percent: 29, resetAt: "2026-09-14T03:30:00Z"),
            Meter(label: "Weekly", percent: 82, resetAt: "2026-09-19T10:00:00Z"),
        ]),
        Provider(name: "Claude", account: "preview", meters: [
            Meter(label: "Session", percent: 45, resetAt: "2026-09-14T00:47:00Z"),
        ]),
    ]))
}
