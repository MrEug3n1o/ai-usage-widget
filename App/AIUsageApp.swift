import SwiftUI
import UsageModel
import UsageCollector

/// Menu bar only, no Dock icon — done here rather than with LSUIElement in the
/// Info.plist, because Launch Services reads that key statically and an agent
/// app's icon does not reach the widget gallery.
///
/// It has to be a delegate callback: NSApp does not exist yet inside App.init,
/// where touching it crashes on an implicitly unwrapped nil before the app can
/// draw anything.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct AIUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
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
            PanelView(store: store, openAccounts: {
                openWindow(id: "accounts")
                // An accessory app is never made active by opening a window, so
                // without this the window arrives behind whatever is frontmost —
                // and with no Dock icon or ⌘-Tab entry there is nothing to click
                // to reach it.
                NSApp.activate()
            })
        } label: {
            Image(systemName: "gauge.with.dots.needle.50percent")
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
