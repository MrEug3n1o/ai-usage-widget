import Foundation
import UsageModel

/// Port of collector/codex.rs — pending.
enum Codex {
}

extension Codex {
    static func collect() -> Provider {
        Provider.failed(name: "Codex", account: "-", error: "collector not ported yet")
    }
}
