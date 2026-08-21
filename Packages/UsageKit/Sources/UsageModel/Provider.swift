import Foundation

/// One limit within a provider (a 5h window, a weekly cap, a billing cycle).
///
/// The JSON shape is the contract shared with `cli/usage_monitor.py` in the
/// ai-usage-monitor repo, which is the reference implementation. Field names are
/// snake_case there (`asdict` over the dataclass), hence the explicit keys.
public struct Meter: Codable, Hashable, Sendable {
    public var label: String
    public var percent: Double?
    public var resetAt: String?
    public var used: String?
    public var limit: String?

    public init(
        label: String,
        percent: Double? = nil,
        resetAt: String? = nil,
        used: String? = nil,
        limit: String? = nil
    ) {
        self.label = label
        self.percent = percent
        self.resetAt = resetAt
        self.used = used
        self.limit = limit
    }

    enum CodingKeys: String, CodingKey {
        case label, percent
        case resetAt = "reset_at"
        case used, limit
    }

    /// Written by hand because the synthesized version uses `encodeIfPresent`
    /// for optionals, which *omits* nil keys. Python's `asdict` and Rust's serde
    /// both emit `"percent": null`, and the parity diff compares the two.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(percent, forKey: .percent)
        try c.encode(resetAt, forKey: .resetAt)
        try c.encode(used, forKey: .used)
        try c.encode(limit, forKey: .limit)
    }
}

/// One account of one provider. Collection never throws out of a `collect*`
/// call: a failure comes back as a `Provider` with `error` filled in, so one
/// dead provider cannot take the panel down with it.
public struct Provider: Codable, Hashable, Sendable {
    public var name: String
    public var account: String
    public var plan: String
    public var email: String
    /// Registered but not the account currently burning quota — `◉ STANDBY`.
    public var standby: Bool
    public var meters: [Meter]
    public var details: [String]
    public var error: String?

    public init(
        name: String,
        account: String,
        plan: String = "",
        email: String = "",
        standby: Bool = false,
        meters: [Meter] = [],
        details: [String] = [],
        error: String? = nil
    ) {
        self.name = name
        self.account = account
        self.plan = plan
        self.email = email
        self.standby = standby
        self.meters = meters
        self.details = details
        self.error = error
    }

    public static func failed(name: String, account: String, error: String) -> Provider {
        Provider(name: name, account: account, error: error)
    }

    /// What the UI shows as the account's identity.
    public var displayLabel: String { email.isEmpty ? account : email }

    /// A provider that was never set up on this machine (Codex without the CLI,
    /// Cursor without a key) is noise in the panel; one that *was* set up and
    /// then broke keeps showing its error. Port of `isUnconfigured` in the
    /// Tauri widget's main.js — the tests pin these exact strings, so changing
    /// a collector's error message means changing them here too.
    public var isUnconfigured: Bool {
        guard let error, meters.isEmpty else { return false }
        switch name {
        case "Cursor":
            return error.hasPrefix("set it up with")
        case "Codex":
            return error.contains("did not start") && error.contains("no local session found")
        default:
            return false
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(account, forKey: .account)
        try c.encode(plan, forKey: .plan)
        try c.encode(email, forKey: .email)
        try c.encode(standby, forKey: .standby)
        try c.encode(meters, forKey: .meters)
        try c.encode(details, forKey: .details)
        try c.encode(error, forKey: .error)
    }
}
