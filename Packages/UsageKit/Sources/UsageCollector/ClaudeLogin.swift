import Foundation
import CryptoKit
import Security

/// The authorization-code + PKCE login that gives a profile a session of its
/// own, rather than a copy of one the Claude Code CLI keeps.
///
/// This exists because an adopted credential can never be refreshed from here:
/// the CLI owns that refresh token and rotating it would log the CLI out, so
/// `Claude.ensureFresh` sends a mirror back to its source instead — and for a
/// Keychain source that read is the macOS password prompt. A profile registered
/// through this flow holds a session nobody else owns, so it self-refreshes
/// over HTTP and never touches the Keychain.
///
/// Same result as the reference CLI's `claude-login`, which shells out to
/// `claude auth login` under a throwaway `CLAUDE_CONFIG_DIR`. Done natively
/// here because the app has no terminal to hand the user.
public enum ClaudeLogin {
    static let authorizeURL = "https://claude.com/cai/oauth/authorize"
    /// The callback renders the code for the user to paste rather than
    /// redirecting anywhere we could listen on, which is why this flow ends in
    /// a text field instead of a loopback server.
    static let redirectURI = "https://platform.claude.com/oauth/code/callback"

    /// What Claude Code asks for. The server grants a subset — whatever comes
    /// back in the token response is what gets stored.
    static let scopes = [
        "org:create_api_key", "user:profile", "user:inference",
        "user:sessions:claude_code", "user:mcp_servers", "user:file_upload",
    ]

    /// One login in progress. The verifier and state have to survive until the
    /// user pastes the code back, so the caller holds this and hands it to
    /// `complete`.
    public struct Attempt: Identifiable, Sendable {
        public let url: URL
        public var id: String { state }
        let verifier: String
        let state: String
    }

    /// Builds the authorization URL. Opening it is the caller's job — this
    /// package has no AppKit.
    public static func begin(email: String? = nil) throws -> Attempt {
        let verifier = randomToken()
        let state = randomToken()
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        guard var components = URLComponents(string: authorizeURL) else {
            throw SimpleError("could not build the login URL")
        }
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Claude.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        if let email, !email.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "login_hint", value: email))
        }
        guard let url = components.url else {
            throw SimpleError("could not build the login URL")
        }
        return Attempt(url: url, verifier: verifier, state: state)
    }

    /// Exchanges the pasted code for a session, in the `claudeAiOauth` shape
    /// the collector and the Claude Code CLI both read.
    public static func complete(
        _ attempt: Attempt, pasted: String
    ) async throws -> [String: Any] {
        let (code, state) = try parse(pasted)
        // The state is the CSRF check: a code pasted from some other login is
        // not this attempt's, and its verifier would not match anyway.
        if let state, state != attempt.state {
            throw SimpleError("that code belongs to a different sign-in — try again")
        }

        let request = try HTTP.request(
            Claude.tokenURL, method: "POST",
            headers: ["User-Agent": "claude-code/2", "Accept": "application/json"],
            jsonBody: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "client_id": Claude.clientID,
                "code_verifier": attempt.verifier,
                "state": attempt.state,
            ])
        let response = try await HTTP.jsonAllowingError(request)
        if let status = response.status, !(200..<300).contains(status) {
            // The code is single-use and short-lived, so a stale paste is the
            // common failure and deserves better than "HTTP 400".
            if response.body.contains("invalid_grant") {
                throw SimpleError("that code was already used or has expired — sign in again")
            }
            throw SimpleError("sign-in failed (\(status))")
        }
        guard let payload = response.json as? [String: Any] else {
            throw SimpleError("sign-in returned no JSON")
        }
        guard let access = payload.string("access_token"),
              let refresh = payload.string("refresh_token")
        else { throw SimpleError("sign-in returned an incomplete session") }

        var oauth: [String: Any] = [
            "accessToken": access,
            "refreshToken": refresh,
            // Integers, like the reference — this file is shared with the
            // Python CLI and with Claude Code itself.
            "expiresAt": Int(Claude.nowMS() + (payload.number("expires_in") ?? 28_800) * 1000),
        ]
        if let refreshExpires = payload.number("refresh_token_expires_in") {
            oauth["refreshTokenExpiresAt"] = Int(Claude.nowMS() + refreshExpires * 1000)
        }
        oauth["scopes"] = (payload.string("scope")?.split(separator: " ").map(String.init))
            ?? scopes

        // `subscriptionType` and `rateLimitTier` are what the CLI's own login
        // stores, and the panel reads the first as the plan label. They are not
        // in the token response, so they come from the profile endpoint —
        // best-effort, because a session is still usable without a label.
        if let profile = try? await accountProfile(token: access) {
            let account = profile.dict("account") ?? [:]
            if account.bool("has_claude_max") == true {
                oauth["subscriptionType"] = "max"
            } else if account.bool("has_claude_pro") == true {
                oauth["subscriptionType"] = "pro"
            }
            if let tier = profile.dict("organization")?.string("rate_limit_tier") {
                oauth["rateLimitTier"] = tier
            }
        }
        return ["claudeAiOauth": oauth]
    }

    /// Accepts what the callback page shows (`code#state`), and also the plain
    /// code or the whole callback URL — people paste all three.
    static func parse(_ pasted: String) throws -> (code: String, state: String?) {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SimpleError("paste the code from the browser") }

        // Handled entirely here rather than falling through: a URL with no code
        // in it is a bad paste, not a code that happens to look like a URL.
        if trimmed.lowercased().hasPrefix("http") {
            let items = URLComponents(string: trimmed)?.queryItems ?? []
            guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                throw SimpleError("that URL has no code in it")
            }
            return (code, items.first(where: { $0.name == "state" })?.value)
        }
        // Keeping empty pieces: dropping them would make "#state" parse as a
        // code of "state".
        let parts = trimmed
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard let code = parts.first, !code.isEmpty else {
            throw SimpleError("paste the code from the browser")
        }
        return (code, parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil)
    }

    static func accountProfile(token: String) async throws -> [String: Any] {
        let request = try HTTP.request(Claude.profileURL, headers: [
            "Authorization": "Bearer \(token)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "claude-code/2",
            "Accept": "application/json",
        ])
        return try await HTTP.json(request) as? [String: Any] ?? [:]
    }

    /// 32 bytes of CSPRNG, base64url — the verifier and the state.
    static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
