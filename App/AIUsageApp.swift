import SwiftUI
import UsageModel
import UsageCollector

@main
struct AIUsageApp: App {
    @StateObject private var store = UsageStore()
    @Environment(\.openWindow) private var openWindow

    init() {
        // Mirrors the Tauri app's --probe: print the collection and exit, so
        // parity against cli/usage_monitor.py is checkable from a terminal.
        if CommandLine.arguments.contains("--probe") { Probe.runAndExit() }
        LoginItem.enableOnFirstRun()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store, openAccounts: { openWindow(id: "accounts") })
        } label: {
            MenuBarLabel(headline: store.headline)
        }
        // .window, not .menu: the panel is a real view with bars and buttons,
        // not a list of menu items.
        .menuBarExtraStyle(.window)

        Window("Accounts", id: "accounts") {
            AccountsView(store: store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Icon plus the most urgent percentage, so the number is readable without
/// opening anything — the main thing the Tauri build could not do.
private struct MenuBarLabel: View {
    let headline: (provider: Provider, meter: Meter)?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.50percent")
            if let percent = headline?.meter.percent {
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
            }
        }
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
