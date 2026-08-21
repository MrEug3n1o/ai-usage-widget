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

    public init() {}

    public enum StoreError: Error, LocalizedError {
        case noContainer
        public var errorDescription: String? {
            "App Group container unavailable — check the application-groups entitlement on both targets."
        }
    }

    static func url() throws -> URL {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { throw StoreError.noContainer }
        return dir.appendingPathComponent("snapshot.json")
    }

    public func load() throws -> Snapshot {
        try Snapshot.read(from: Self.url())
    }

    public func save(_ snapshot: Snapshot) throws {
        try Snapshot.write(snapshot, to: Self.url())
    }
}

/// The widget extension's own sandbox container.
///
/// Needs no entitlement at all, which is what makes it the channel that
/// survives ad-hoc signing: App Groups are a restricted entitlement, so an
/// unsigned build downloaded from a release would leave the widget reading an
/// empty container forever. The extension sees this path as its own
/// NSHomeDirectory; the host, being unsandboxed, writes to it absolutely.
public struct ContainerSnapshotStore: SnapshotStore {
    public static let widgetBundleID = "com.erickmenezes.AIUsage.Widget"

    public init() {}

    static func hostURL() -> URL {
        realHome
            .appendingPathComponent("Library/Containers/\(widgetBundleID)/Data/snapshot.json")
    }

    /// Inside the sandbox the container IS home, so the same file is reached by
    /// a different path than the one the host writes.
    static func readerURL() -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return home.path == realHome.path
            ? hostURL()
            : home.appendingPathComponent("snapshot.json")
    }

    /// The real home, bypassing the sandbox redirect NSHomeDirectory applies.
    static var realHome: URL {
        guard let pw = getpwuid(getuid()) else { return URL(fileURLWithPath: NSHomeDirectory()) }
        return URL(fileURLWithPath: String(cString: pw.pointee.pw_dir))
    }

    public func load() throws -> Snapshot {
        try Snapshot.read(from: Self.readerURL())
    }

    public func save(_ snapshot: Snapshot) throws {
        try Snapshot.write(snapshot, to: Self.hostURL())
    }
}

/// Writes both channels and reads whichever answers.
///
/// Which one works is decided by how the build was signed, and the app cannot
/// tell at runtime: an unsandboxed host can write to the App Group container
/// whether or not it is entitled, so a successful write there says nothing
/// about the sandboxed widget's ability to read it. Writing both is a few
/// hundred bytes and removes the question.
public struct DualSnapshotStore: SnapshotStore {
    private let stores: [SnapshotStore] = [AppGroupSnapshotStore(), ContainerSnapshotStore()]

    public init() {}

    public func save(_ snapshot: Snapshot) throws {
        var failures: [Error] = []
        for store in stores {
            do { try store.save(snapshot) } catch { failures.append(error) }
        }
        // Only a failure of every channel is a failure.
        if failures.count == stores.count, let first = failures.first { throw first }
    }

    public func load() throws -> Snapshot {
        var newest: Snapshot?
        for store in stores {
            guard let candidate = try? store.load() else { continue }
            if newest == nil || candidate.capturedAt > newest!.capturedAt { newest = candidate }
        }
        guard let newest else { throw AppGroupSnapshotStore.StoreError.noContainer }
        return newest
    }
}

extension Snapshot {
    static func read(from url: URL) throws -> Snapshot {
        try decoder.decode(Snapshot.self, from: Data(contentsOf: url))
    }

    static func write(_ snapshot: Snapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: .atomic)
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
