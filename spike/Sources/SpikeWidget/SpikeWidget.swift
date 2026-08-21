import WidgetKit
import SwiftUI
import os

let log = Logger(subsystem: "dev.erickmenezes.aiusage.spike", category: "widget")

/// Reads every channel and reports what arrived. This is the whole point of the
/// spike: whichever channels come back green here are the ones the real widget
/// can be built on.
func probeAll() -> [ChannelResult] {
    Channel.allCases.map { channel in
        guard let url = readerURL(for: channel) else {
            return ChannelResult(channel: channel, ok: false, detail: "no container")
        }
        do {
            let data = try Data(contentsOf: url)
            let body = try JSONSerialization.jsonObject(with: data) as? [String: String]
            let stamp = body?["stamp"] ?? "?"
            log.info("read \(channel.rawValue, privacy: .public) ok stamp=\(stamp, privacy: .public)")
            return ChannelResult(channel: channel, ok: true, detail: stamp)
        } catch {
            log.error("read \(channel.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return ChannelResult(channel: channel, ok: false, detail: "\((error as NSError).code)")
        }
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let sandboxed: Bool
    let home: String
    let results: [ChannelResult]
}

struct Provider: TimelineProvider {
    func snapshotEntry() -> Entry {
        Entry(date: Date(), sandboxed: isSandboxed, home: NSHomeDirectory(), results: probeAll())
    }
    func placeholder(in context: Context) -> Entry { snapshotEntry() }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(snapshotEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = snapshotEntry()
        log.info("timeline sandboxed=\(entry.sandboxed, privacy: .public) home=\(entry.home, privacy: .public)")
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }
}

struct SpikeView: View {
    var entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.sandboxed ? "SANDBOXED" : "UNSANDBOXED")
                .font(.caption.bold())
                .foregroundStyle(entry.sandboxed ? .orange : .green)
            ForEach(entry.results, id: \.channel) { r in
                Text("\(r.ok ? "✓" : "✗") \(r.channel.rawValue)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(r.ok ? .primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct SpikeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SpikeWidget", provider: Provider()) { SpikeView(entry: $0) }
            .configurationDisplayName("Spike probe")
            .description("Reports which host→widget data channels work.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SpikeWidgetBundle: WidgetBundle {
    var body: some Widget { SpikeWidget() }
}
