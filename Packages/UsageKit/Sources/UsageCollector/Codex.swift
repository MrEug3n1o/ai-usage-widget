import Foundation
import UsageModel

/// Port of collector/codex.rs — pending.
enum Codex {
    static func collect() async -> Provider {
        Provider.failed(name: "Codex", account: "-", error: "collector not ported yet")
    }
}
