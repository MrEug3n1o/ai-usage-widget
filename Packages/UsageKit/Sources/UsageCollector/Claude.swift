import Foundation
import UsageModel

/// Port of collector/claude.rs — pending.
enum Claude {
    static func collect(profileDir: URL) async -> Provider {
        Provider.failed(name: "Claude", account: profileDir.lastPathComponent,
                        error: "collector not ported yet")
    }
}
