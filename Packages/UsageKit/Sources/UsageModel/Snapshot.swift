import Foundation

/// What the host app hands the widget through the App Group container.
///
/// `capturedAt` exists so the widget can tell "nothing changed" from "the host
/// died an hour ago" — a stale reading rendered as if fresh is worse than no
/// reading, since the whole point is knowing how much quota is left.
public struct Snapshot: Codable, Sendable {
    public var providers: [Provider]
    public var capturedAt: Date

    public init(providers: [Provider], capturedAt: Date = Date()) {
        self.providers = providers
        self.capturedAt = capturedAt
    }

    public var age: TimeInterval { Date().timeIntervalSince(capturedAt) }

    /// Beyond this the widget marks itself stale rather than showing the
    /// numbers plainly. Generous, because WidgetKit refresh is best-effort.
    public static let staleAfter: TimeInterval = 10 * 60
    public var isStale: Bool { age > Self.staleAfter }
}

/// Where a snapshot lives. Behind a protocol because Phase 0 left two working
/// channels: the App Group (chosen) and the widget's own sandbox container
/// (fallback, needs no entitlement). See docs/data-channel.md.
public protocol SnapshotStore {
    func load() throws -> Snapshot
    func save(_ snapshot: Snapshot) throws
}

public struct AppGroupSnapshotStore: SnapshotStore {
    /// MUST be team-ID prefixed. An unprefixed id silently half-works: the
    /// container is created and the unsandboxed host writes into it, and only
    /// the sandboxed widget's read is denied. See docs/data-channel.md.
    public static let groupID = "VG87LBRMTR.group.com.erickmenezes.AIUsage"

    private let fileName = "snapshot.json"

    public init() {}

    public enum StoreError: Error, LocalizedError {
        case noContainer
        public var errorDescription: String? {
            "App Group container unavailable — check the application-groups entitlement on both targets."
        }
    }

    private func url() throws -> URL {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.groupID)
        else { throw StoreError.noContainer }
        return dir.appendingPathComponent(fileName)
    }

    public func load() throws -> Snapshot {
        let data = try Data(contentsOf: try url())
        return try Snapshot.decoder.decode(Snapshot.self, from: data)
    }

    public func save(_ snapshot: Snapshot) throws {
        try Snapshot.encoder.encode(snapshot).write(to: try url(), options: .atomic)
    }
}

extension Snapshot {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
