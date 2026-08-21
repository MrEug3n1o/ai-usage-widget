import SwiftUI
import WidgetKit
import os

let log = Logger(subsystem: "dev.erickmenezes.aiusage.spike", category: "host")

/// Writes a stamped payload down every channel it can, so the widget can report
/// which ones arrived. Returns one line per channel for the menu bar panel.
@discardableResult
func writeAll() -> [ChannelResult] {
    let stamp = ISO8601DateFormatter().string(from: Date())
    return Channel.allCases.map { channel in
        guard let url = payloadURL(for: channel) else {
            return ChannelResult(channel: channel, ok: false,
                                 detail: "no container (entitlement missing?)")
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let body = ["stamp": stamp, "channel": channel.rawValue]
            try JSONSerialization.data(withJSONObject: body).write(to: url, options: .atomic)
            log.info("wrote \(channel.rawValue, privacy: .public) -> \(url.path, privacy: .public)")
            return ChannelResult(channel: channel, ok: true, detail: url.path)
        } catch {
            log.error("write \(channel.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return ChannelResult(channel: channel, ok: false, detail: error.localizedDescription)
        }
    }
}

@main
struct SpikeApp: App {
    @State private var results: [ChannelResult] = []

    init() {
        // `--probe` makes the host scriptable: write everything, print, exit.
        if CommandLine.arguments.contains("--probe") {
            print("host sandboxed: \(isSandboxed)")
            print("host home: \(NSHomeDirectory())")
            for r in writeAll() {
                print("\(r.ok ? "ok  " : "FAIL") \(r.channel.rawValue): \(r.detail)")
            }
            WidgetCenter.shared.reloadAllTimelines()
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra("Spike", systemImage: "gauge.medium") {
            Text("host sandboxed: \(isSandboxed ? "yes" : "no")")
            Divider()
            ForEach(results, id: \.channel) { r in
                Text("\(r.ok ? "✓" : "✗") \(r.channel.rawValue)")
            }
            Divider()
            Button("Write + reload widgets") {
                results = writeAll()
                WidgetCenter.shared.reloadAllTimelines()
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .menuBarExtraStyle(.menu)
    }
}

extension Channel: Identifiable { var id: String { rawValue } }
