import Foundation
import ServiceManagement

/// Start at login, replacing the Tauri build's autostart plugin.
///
/// Only in release builds: registering a debug binary points launchd at a path
/// inside DerivedData that the next build invalidates.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("login item \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }

    /// Enabled on first run of a release build, matching the Tauri behaviour.
    static func enableOnFirstRun() {
        #if !DEBUG
        let key = "loginItem.configuredOnce"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        setEnabled(true)
        #endif
    }
}
