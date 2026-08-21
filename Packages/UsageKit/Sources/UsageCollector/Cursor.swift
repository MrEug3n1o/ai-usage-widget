import Foundation
import UsageModel

/// Port of collector/cursor.rs — pending.
enum Cursor {
}

extension Cursor {
    static func collect() -> Provider {
        Provider.failed(name: "Cursor", account: "-", error: "collector not ported yet")
    }
}
