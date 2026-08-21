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
            // Bridge async to sync: this path is a CLI, it prints and exits
            // before any UI exists, so blocking the main thread is the point.
            // Task.detached, NOT Task: App.init is @MainActor, so a plain Task
            // inherits the main actor and deadlocks against the wait() below.
            let done = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var providers: [Provider] = []
            Task.detached {
                providers = await Collector.collectAll()
                done.signal()
            }
            done.wait()
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
        Task {
            let next = Snapshot(providers: await Collector.collectAll())
            snapshot = next
            try? Self.store.save(next)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
