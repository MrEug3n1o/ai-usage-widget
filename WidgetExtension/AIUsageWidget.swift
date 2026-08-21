import WidgetKit
import SwiftUI
import UsageModel

/// Phase 1 skeleton. The extension NEVER collects — it is sandboxed and has no
/// access to the Keychain, the config dir, or subprocesses. It only reads what
/// the host app left in the App Group container.
struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let error: String?
}

struct Provider: TimelineProvider {
    private let store = AppGroupSnapshotStore()

    private func read() -> Entry {
        do {
            return Entry(date: Date(), snapshot: try store.load(), error: nil)
        } catch {
            return Entry(date: Date(), snapshot: nil, error: error.localizedDescription)
        }
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

struct AIUsageWidgetView: View {
    var entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let snapshot = entry.snapshot {
                if snapshot.isStale {
                    Text("stale").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(snapshot.providers.filter { !$0.isUnconfigured }, id: \.self) { provider in
                    Text(provider.name).font(.caption)
                }
            } else {
                Text(entry.error ?? "No reading").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct AIUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIUsageWidget", provider: Provider()) {
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
