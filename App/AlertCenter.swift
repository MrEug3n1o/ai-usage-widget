import Foundation
import UserNotifications
import UsageModel
import UsageCollector

/// Notifies once as a limit rises through each configured level.
///
/// Port of `checkAlerts` in the Tauri widget's main.js. The high-water mark per
/// meter is what stops a limit parked on a boundary from re-announcing itself
/// on every refresh, which is the failure mode that makes people mute an app.
@MainActor
final class AlertCenter {
    /// A level re-arms only once usage falls this far below it.
    static let rearmMargin: Double = 5

    private var firedLevels: [String: Double] = [:]
    private var thresholds: [Double] = Config.defaultAlertThresholds
    private var askedForPermission = false

    func loadThresholds() {
        thresholds = Config.alertThresholds()
    }

    func check(_ providers: [Provider]) {
        guard !thresholds.isEmpty else { return }
        for provider in providers {
            for meter in provider.meters {
                guard let percent = meter.percent else { continue }
                // reset_at stays out of the key: some providers jitter it
                // between fetches, which would reset the latch every time.
                let key = "\(provider.displayLabel)|\(meter.label)"
                var mark = firedLevels[key] ?? 0

                // Forget any level the meter has dropped clearly below — the
                // window renewed, or usage genuinely fell. A real reset lands
                // near zero, far past the margin, so every level re-arms.
                if mark > 0, percent < mark - Self.rearmMargin {
                    mark = reachedLevel(percent)
                    firedLevels[key] = mark
                }
                let level = reachedLevel(percent)
                guard level > mark else { continue }
                firedLevels[key] = level

                let remaining = Formatting.resetRemaining(meter.resetAt)
                notify(
                    title: "\(provider.name) · \(provider.displayLabel)",
                    body: "\(meter.label) at \(Int(percent.rounded()))%"
                        + (remaining.isEmpty ? "" : " · renews in \(remaining)"))
            }
        }
    }

    /// Highest configured threshold at or below `percent`, or 0 below them all.
    private func reachedLevel(_ percent: Double) -> Double {
        thresholds.filter { percent >= $0 }.max() ?? 0
    }

    private func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        let post = {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                             content: content, trigger: nil))
        }
        // macOS requires an explicit grant. Ask once, lazily, on the first
        // alert rather than with a prompt the moment the app launches.
        guard !askedForPermission else { return post() }
        askedForPermission = true
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { Task { @MainActor in post() } }
        }
    }
}
