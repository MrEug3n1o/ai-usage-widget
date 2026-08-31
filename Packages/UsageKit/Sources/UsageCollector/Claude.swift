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

    /// True when the access token is gone or already dead. Stricter than
    /// `expiring`: no refresh window, because for a mirrored profile the act of
    /// looking at its source costs a macOS password prompt, and spending one
    /// two minutes early buys nothing.
    static func expired(_ data: [String: Any]) -> Bool {
        (data.dict("claudeAiOauth")?.number("expiresAt") ?? 0) <= nowMS()
    }

    /// Brings the profile's cached credential up to date without ever rotating
    /// a token the Claude Code CLI owns.
    ///
    /// A profile registered from an existing CLI login is a *copy* of a session
    /// the CLI still owns, and the token endpoint rotates the refresh token on
    /// every use: whichever side refreshes first leaves the other holding a
    /// token the server has already dropped. We poll every minute and the CLI
    /// only refreshes when you actually run it, so we win that race nearly
    /// always — and the symptom lands on the CLI, whose login "expires" for no
    /// reason the user can see.
    ///
    /// So a source-backed profile never refreshes. It adopts what the CLI
    /// wrote, and when the CLI's token is expired too it says so and waits.
    /// Only a profile that owns its own login refreshes. (The Python reference
    /// in ../ai-usage-monitor still refreshes either way; this is a deliberate
    /// divergence, not a port gap.)
    static func ensureFresh(
        profileDir: URL, path: URL, data: [String: Any]
    ) async throws -> [String: Any] {
        // A mirror waits for the token to actually die before it looks at its
        // source; a profile that owns its login refreshes inside the window,
        // where the cost is one silent HTTP call rather than a password prompt.
        let mirrored = ClaudeSource.profileSource(profileDir) != nil
        guard mirrored ? expired(data) : expiring(data) else { return data }
        guard !mirrored else {
            return try await adopt(profileDir: profileDir, path: path)
        }
        do {
            return try await refresh(path: path, data: data)
        } catch {
            if error.localizedDescription.contains("invalid_grant") {
                throw SimpleError("session revoked — register this account again")
            }
            throw error
        }
    }

    /// Takes over whatever token the source holds now. Reads the source at most
    /// once per version of it: for a Keychain source that read is what raises
    /// the macOS permission dialog, and a profile left waiting for the CLI is
    /// re-read on every poll otherwise — a password prompt a minute.
    static func adopt(profileDir: URL, path: URL) async throws -> [String: Any] {
        let version = ClaudeSource.sourceVersion(profileDir)
        guard await AdoptionGate.shared.shouldRead(profile: profileDir.path,
                                                   version: version) else {
            throw SimpleError("waiting for Claude Code to refresh this session")
        }
        guard let fresh = ClaudeSource.credential(for: profileDir) else {
            throw SimpleError(
                "could not read the Claude Code session — allow Keychain access, "
                + "or register this account again")
        }
        // Worth keeping even when it is expired: it carries the CLI's live
        // refresh token, so our copy stops drifting from the login it mirrors.
        try Config.writeJSON(fresh, to: path)
        guard !expiring(fresh) else {
            throw SimpleError("Claude Code's session has expired — run claude once")
        }
        return fresh
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
