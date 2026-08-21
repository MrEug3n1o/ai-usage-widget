import Foundation
import UsageModel

/// Limits for a Claude account stored at
/// ~/.config/ai-usage-monitor/claude/<name>/.credentials.json, refreshing the
/// OAuth token when needed. Port of `collect_claude` / `refresh_claude`.
enum Claude {
    static let usageURL = "https://api.anthropic.com/api/oauth/usage"
    static let profileURL = "https://api.anthropic.com/api/oauth/profile"
    static let tokenURL = "https://platform.claude.com/v1/oauth/token"
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    /// The window inside which a token counts as expiring. Two minutes, so a
    /// reading never starts with a token that dies mid-request.
    static let refreshWindowMS: Double = 120_000

    static func nowMS() -> Double { Date().timeIntervalSince1970 * 1000 }

    static func collect(profileDir: URL) async -> Provider {
        let name = profileDir.lastPathComponent
        do {
            return try await run(profileDir: profileDir, name: name)
        } catch {
            return Provider.failed(name: "Claude", account: name,
                                   error: error.localizedDescription)
        }
    }

    private static func run(profileDir: URL, name: String) async throws -> Provider {
        let path = profileDir.appendingPathComponent(".credentials.json")
        guard var data = try Config.readJSON(path) as? [String: Any] else {
            throw SimpleError("the file does not contain a Claude OAuth session")
        }
        data = try await ensureFresh(profileDir: profileDir, path: path, data: data)

        guard let oauth = data.dict("claudeAiOauth") else {
            throw SimpleError("the file does not contain a Claude OAuth session")
        }
        guard let token = oauth.string("accessToken") else {
            throw SimpleError("credential has no accessToken")
        }

        let usage = try await get(usageURL, token: token)
        // Identity is a nicety; losing it must not lose the limits.
        let email = ((try? await get(profileURL, token: token))?
            .dict("account")?.string("email")) ?? ""

        var provider = Provider(
            name: "Claude", account: name,
            plan: Text.titleCase(oauth.string("subscriptionType") ?? ""),
            email: email)
        for (key, label) in [("five_hour", "Session"),
                             ("seven_day", "Weekly"),
                             ("seven_day_sonnet", "Weekly Sonnet")] {
            guard let block = usage.dict(key), !block.isEmpty else { continue }
            provider.meters.append(Meter(
                label: label,
                percent: block.number("utilization") ?? 0,
                resetAt: block.string("resets_at")))
        }
        if let detail = extraUsageDetail(usage.dict("extra_usage") ?? [:]) {
            provider.details.append(detail)
        }
        return provider
    }

    /// One line describing the extra-usage credits, or nil when there are none.
    ///
    /// `utilization` is only filled in when the account has a monthly cap — with
    /// pay-as-you-go credits it comes back null, so `used_credits` (in minor
    /// units) is the field that always carries meaning. Credits already spent
    /// keep showing after the account turns extra usage off or has it capped,
    /// flagged with `off`.
    static func extraUsageDetail(_ extra: [String: Any]) -> String? {
        guard let used = extra.number("used_credits") else { return nil }
        let enabled = extra.bool("is_enabled") ?? false
        if !enabled && used == 0 { return nil }

        let places = Int(extra.number("decimal_places") ?? 0)
        let currency = extra.string("currency") ?? ""
        var text = "Extra usage: \(money(used, currency: currency, places: places))"
        if let limit = extra.number("monthly_limit"), limit != 0 {
            let percent = extra.number("utilization") ?? (used / limit * 100)
            text += " / \(money(limit, currency: currency, places: places))"
                + String(format: " (%.0f%%)", percent)
        }
        return enabled ? text : text + " · off"
    }

    /// Minor units (`used_credits`, `monthly_limit`) as a readable amount.
    static func money(_ minor: Double, currency: String, places: Int) -> String {
        let upper = currency.uppercased()
        let symbols = ["USD": "$", "BRL": "R$", "EUR": "€", "GBP": "£"]
        let symbol = symbols[upper] ?? (currency.isEmpty ? "" : "\(upper) ")
        let value = minor / pow(10, Double(places))
        return symbol + String(format: "%.\(places)f", value)
    }

    /// True when the access token is gone or inside the refresh window.
    static func expiring(_ data: [String: Any]) -> Bool {
        (data.dict("claudeAiOauth")?.number("expiresAt") ?? 0) <= nowMS() + refreshWindowMS
    }

    /// Brings the profile's cached credential up to date, healing the refresh
    /// race against the Claude Code CLI.
    ///
    /// A profile registered from an existing CLI login is a *copy* of a session
    /// the CLI still owns, and the token endpoint rotates the refresh token on
    /// every use: whichever side refreshes first leaves the other holding a
    /// token the server has already dropped, and that copy stays dead — the
    /// account then has to be registered again by hand. The account in daily
    /// use in the CLI loses this race almost every time.
    ///
    /// So the source recorded at registration is the authority. When our copy
    /// is about to expire we adopt the source's token if it is still valid — no
    /// refresh, so nothing to race — and only refresh ourselves when the source
    /// has nothing better. A rejected refresh means the CLI rotated past us,
    /// and the source's refresh token is the live one to use instead.
    static func ensureFresh(
        profileDir: URL, path: URL, data: [String: Any]
    ) async throws -> [String: Any] {
        guard expiring(data) else { return data }

        let fresh = ClaudeSource.credential(for: profileDir)
        if let fresh, !expiring(fresh) {
            // Adopt, do not refresh: nothing is rotated, so nothing races.
            try Config.writeJSON(fresh, to: path)
            return fresh
        }
        do {
            return try await refresh(path: path, data: data)
        } catch {
            if let fresh, let healed = try? await refresh(path: path, data: fresh) {
                return healed
            }
            if error.localizedDescription.contains("invalid_grant") {
                throw SimpleError("session revoked — register this account again")
            }
            throw error
        }
    }

    /// Refreshes the access token if it expires in under the refresh window,
    /// and writes it back.
    static func refresh(path: URL, data: [String: Any]) async throws -> [String: Any] {
        guard var oauth = data.dict("claudeAiOauth") else {
            throw SimpleError("the file does not contain a Claude OAuth session")
        }
        if (oauth.number("expiresAt") ?? 0) > nowMS() + refreshWindowMS { return data }
        guard let refreshToken = oauth.string("refreshToken") else {
            throw SimpleError("credential has no refreshToken")
        }
        let scopes = (oauth.array("scopes") ?? []).compactMap { $0 as? String }

        let request = try HTTP.request(
            tokenURL, method: "POST",
            headers: ["User-Agent": "claude-code/2", "Accept": "application/json"],
            jsonBody: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
                "scope": scopes.joined(separator: " "),
            ])
        let response = try await HTTP.jsonAllowingError(request)
        if let status = response.status, !(200..<300).contains(status) {
            // invalid_grant is the revoked-token case: the login moved on
            // without us and only registering the account again will fix it.
            if response.body.contains("invalid_grant") {
                throw SimpleError("session revoked — register this account again")
            }
            throw SimpleError("token refresh failed (\(status))")
        }
        guard let payload = response.json as? [String: Any] else {
            throw SimpleError("token refresh returned no JSON")
        }

        if let access = payload.string("access_token") { oauth["accessToken"] = access }
        if let token = payload.string("refresh_token") { oauth["refreshToken"] = token }
        let expiresIn = payload.number("expires_in") ?? 28_800
        // Stored as an integer, like the reference — this file is shared with
        // the Python CLI and the Claude Code CLI reads the same shape.
        oauth["expiresAt"] = Int(nowMS() + expiresIn * 1000)
        if let refreshExpires = payload.number("refresh_token_expires_in") {
            oauth["refreshTokenExpiresAt"] = Int(nowMS() + refreshExpires * 1000)
        }
        if let scope = payload.string("scope") {
            oauth["scopes"] = scope.split(separator: " ").map(String.init)
        }

        var updated = data
        updated["claudeAiOauth"] = oauth
        try Config.writeJSON(updated, to: path)
        return updated
    }

    private static func get(_ url: String, token: String) async throws -> [String: Any] {
        let request = try HTTP.request(url, headers: [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2",
            "Accept": "application/json",
        ])
        return try await HTTP.json(request) as? [String: Any] ?? [:]
    }
}

extension Claude {
    /// Refresh-if-needed plus the account's identity (email, plan) for the
    /// credential at `path`, without collecting usage.
    ///
    /// Registration uses this to recognise an account that is already
    /// registered, so a stale copy is healed rather than added a second time
    /// under a suffixed name.
    static func identify(_ path: URL) async throws -> (email: String, plan: String) {
        guard var data = try Config.readJSON(path) as? [String: Any] else {
            throw SimpleError("the file does not contain a Claude OAuth session")
        }
        let profileDir = path.deletingLastPathComponent()
        data = try await ensureFresh(profileDir: profileDir, path: path, data: data)

        guard let oauth = data.dict("claudeAiOauth") else {
            throw SimpleError("the file does not contain a Claude OAuth session")
        }
        guard let token = oauth.string("accessToken") else {
            throw SimpleError("credential has no accessToken")
        }
        let request = try HTTP.request(profileURL, headers: [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2",
            "Accept": "application/json",
        ])
        guard let payload = try await HTTP.json(request) as? [String: Any],
              let email = payload.dict("account")?.string("email")
        else { throw SimpleError("the profile response has no email") }
        return (email, Text.titleCase(oauth.string("subscriptionType") ?? ""))
    }
}
