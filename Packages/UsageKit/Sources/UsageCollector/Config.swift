import Foundation

/// Location and I/O for the credential store, mirroring the Python collector's
/// layout: `~/.config/ai-usage-monitor/`. Writes keep Python's 0600/0700
/// permissions (`ensure_private_dir` / `write_private_json`) — the two tools
/// share these files, so one must not loosen what the other tightened.
public enum Config {
    public static var home: URL {
        // Not NSHomeDirectory(): the host app is unsandboxed today, but reading
        // the real passwd entry keeps this correct if that ever changes and
        // makes the intent explicit — we want the user's home, not a container.
        if let dir = ProcessInfo.processInfo.environment["HOME"], !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        guard let pw = getpwuid(getuid()) else { return URL(fileURLWithPath: NSHomeDirectory()) }
        return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
    }

    public static var configDir: URL { home.appendingPathComponent(".config/ai-usage-monitor") }
    public static var claudeDir: URL { configDir.appendingPathComponent("claude") }
    public static var cursorConfig: URL { configDir.appendingPathComponent("cursor.json") }
    public static var configFile: URL { configDir.appendingPathComponent("config.json") }

    /// Percentages at which a limit fires a notification. Mirrors
    /// `DEFAULT_ALERT_THRESHOLDS` in cli/usage_monitor.py.
    public static let defaultAlertThresholds: [Double] = [80, 90, 95, 98, 100]

    /// Notification levels from config.json, or the defaults if absent/broken.
    /// Writes the default file when missing so the user has one to edit.
    public static func alertThresholds() -> [Double] {
        let path = configFile
        guard FileManager.default.fileExists(atPath: path.path) else {
            try? writeJSON(["alert_thresholds": defaultAlertThresholds], to: path)
            return defaultAlertThresholds
        }
        guard let object = try? readJSON(path) as? [String: Any] else {
            return defaultAlertThresholds
        }
        return normalizeThresholds(object["alert_thresholds"])
    }

    /// Ints in 1...100, unique, ascending; the defaults when absent or unusable,
    /// so a hand-edited config that goes wrong still notifies instead of going
    /// silently quiet.
    static func normalizeThresholds(_ value: Any?) -> [Double] {
        guard let items = value as? [Any] else { return defaultAlertThresholds }
        let levels = items
            // JSON true/false bridge to NSNumber and would otherwise count as 1.
            .compactMap { $0 as? NSNumber }
            .filter { CFGetTypeID($0) != CFBooleanGetTypeID() }
            .map { Int($0.doubleValue.rounded()) }
            .filter { (1...100).contains($0) }
        let unique = Set(levels).sorted()
        return unique.isEmpty ? defaultAlertThresholds : unique.map(Double.init)
    }

    public static func readJSON(_ path: URL) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(contentsOf: path))
    }

    /// 0600 from creation — no window in which credentials are world-readable.
    public static func writeJSON(_ value: Any, to path: URL) throws {
        let fm = FileManager.default
        let dir = path.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

        var data = try JSONSerialization.data(withJSONObject: value,
                                              options: [.prettyPrinted, .sortedKeys])
        data.append(0x0A)
        if fm.fileExists(atPath: path.path) {
            try data.write(to: path, options: .atomic)
        } else {
            guard fm.createFile(atPath: path.path, contents: data,
                                attributes: [.posixPermissions: 0o600])
            else { throw CocoaError(.fileWriteUnknown) }
        }
        // Also tightens files the Python CLI created with different modes.
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
}
