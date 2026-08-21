import SwiftUI
import UsageModel
import UsageCollector

/// Phase 2 is where this becomes a real menu bar app. For now it collects on a
/// loop and publishes to the App Group so the widget has something to read.
@main
struct AIUsageApp: App {
    @StateObject private var store = UsageStore()

    init() {
        // Mirrors the Tauri app's --probe: print the collection and exit, so
        // parity against cli/usage_monitor.py is checkable from a terminal.
        if CommandLine.arguments.contains("--probe") { Probe.runAndExit() }
    }

    var body: some Scene {
        MenuBarExtra {
            if let snapshot = store.snapshot {
                ForEach(snapshot.providers.filter { !$0.isUnconfigured }, id: \.self) { provider in
                    Text(summary(of: provider))
                }
                Divider()
                Text(store.isFetching ? "Refreshing…" : "Updated \(stamp(snapshot.capturedAt))")
            } else {
                Text("No reading yet")
            }
            Divider()
            Button("Refresh") { Task { await store.refresh() } }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } label: {
            // Phase 2 proper adds the live percentage here.
            Image(systemName: "gauge.with.dots.needle.50percent")
        }
        .menuBarExtraStyle(.menu)
    }

    private func summary(of provider: Provider) -> String {
        if let error = provider.error { return "\(provider.name): \(error)" }
        let meters = provider.meters
            .map { "\($0.label) \(Int(($0.percent ?? 0).rounded()))%" }
            .joined(separator: "  ")
        return "\(provider.name) · \(provider.displayLabel) — \(meters)"
    }

    private func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

/// The --probe path, kept out of the App type so the async bridge is obvious.
enum Probe {
    static func runAndExit() -> Never {
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
