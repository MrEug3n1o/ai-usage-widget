import Foundation

/// The three candidate ways the (unsandboxed) host app can hand a snapshot to
/// the (normally sandboxed) widget extension. Phase 0 exists to find out which
/// of them actually work on this machine, with this signing identity.
enum Channel: String, CaseIterable {
    /// No channel at all: the widget reads the real config dir directly.
    /// Only possible if the extension can run unsandboxed.
    case direct = "A/direct-config-dir"
    /// Host writes into the extension's own sandbox container. No entitlement.
    case container = "B/extension-container"
    /// The supported route. Needs an App Group entitlement, hence a paid team.
    case appGroup = "C/app-group"
}

let widgetBundleID = "dev.erickmenezes.aiusage.spike.widget"
let appGroupID = "VG87LBRMTR.group.dev.erickmenezes.aiusage"

/// The user's real home, bypassing the sandbox redirect that `NSHomeDirectory`
/// applies inside a container. Comparing the two is how we detect sandboxing.
var realHome: String {
    guard let pw = getpwuid(getuid()) else { return NSHomeDirectory() }
    return String(cString: pw.pointee.pw_dir)
}

var isSandboxed: Bool { NSHomeDirectory() != realHome }

func payloadURL(for channel: Channel) -> URL? {
    switch channel {
    case .direct:
        return URL(fileURLWithPath: realHome)
            .appendingPathComponent(".config/ai-usage-monitor/spike-A.json")
    case .container:
        // From the host this is an absolute path under the real home; from
        // inside the sandboxed extension the same file is simply its own
        // NSHomeDirectory().
        return URL(fileURLWithPath: realHome)
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/spike-B.json")
    case .appGroup:
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("spike-C.json")
    }
}

/// The extension's view of the same files. Only differs for the container
/// channel, where the sandbox rewrites the home directory underneath us.
func readerURL(for channel: Channel) -> URL? {
    if channel == .container, isSandboxed {
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("spike-B.json")
    }
    return payloadURL(for: channel)
}

struct ChannelResult {
    let channel: Channel
    let ok: Bool
    let detail: String
}
