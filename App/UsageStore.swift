import Foundation
import WidgetKit
import UsageModel
import UsageCollector

/// Owns the polling loop. Collection happens here and nowhere else: the widget
/// extension is sandboxed and can only read what this writes into the App Group.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var isFetching = false

    /// Matches the Tauri widget's INTERVAL_MS.
    static let interval: TimeInterval = 60

    private let store = DualSnapshotStore()
    private let alerts = AlertCenter()
    private var loop: Task<Void, Never>?
    private var snapshotAccessFailed = false

    init() {
        // Show the last reading immediately rather than an empty panel while
        // the first collection runs.
        // Do not probe another application's container on startup. Collection
        // fills the panel; publishing below is the only cross-container access.
        alerts.loadThresholds()
        start()
    }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        let next = Snapshot(providers: await Collector.collectAll())
        snapshot = next
        alerts.check(next.providers)
        guard !snapshotAccessFailed else { return }
        do {
            try store.save(next)
            // The host pushes; the widget's own timeline is only a fallback.
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // A denied container request must not be retried by every poll.
            snapshotAccessFailed = true
            NSLog("snapshot save failed: \(error.localizedDescription)")
        }
    }
}
