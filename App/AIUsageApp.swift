import SwiftUI
import WidgetKit
import UsageModel
import UsageCollector

/// Phase 1 skeleton. The menu bar UI (Phase 2) and the real collection
/// (rest of Phase 1) land on top of this; what exists here is the wiring:
/// collect -> write snapshot to the App Group -> reload the widget.
@main
struct AIUsageApp: App {
    @State private var snapshot: Snapshot?

    private static let store = AppGroupSnapshotStore()

    init() {
        // Mirrors the Tauri app's --probe: print the collection and exit, so
        // parity against cli/usage_monitor.py is checkable from a terminal.
        if CommandLine.arguments.contains("--probe") {
            let providers = Collector.collectAll()
            let data = try! Snapshot.encoder.encode(providers)
            print(String(decoding: data, as: UTF8.self))
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra("AI Usage", systemImage: "gauge.with.dots.needle.50percent") {
            if let snapshot {
                ForEach(snapshot.providers, id: \.self) { provider in
                    Text("\(provider.name) — \(provider.displayLabel)")
                }
            } else {
                Text("No reading yet")
            }
            Divider()
            Button("Refresh") { refresh() }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }

    private func refresh() {
        let next = Snapshot(providers: Collector.collectAll())
        snapshot = next
        try? Self.store.save(next)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
