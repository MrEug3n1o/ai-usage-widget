import XCTest
import CryptoKit
@testable import UsageCollector

/// The callback page prints `code#state`, but people paste what they have.
final class ClaudeLoginParseTests: XCTestCase {
    func testCodeAndStateFromTheCallbackPage() throws {
        let (code, state) = try ClaudeLogin.parse("abc123#xyz789")
        XCTAssertEqual(code, "abc123")
        XCTAssertEqual(state, "xyz789")
    }

    /// A bare code is accepted; there is simply no state to cross-check.
    func testBareCodeHasNoState() throws {
        let (code, state) = try ClaudeLogin.parse("abc123")
        XCTAssertEqual(code, "abc123")
        XCTAssertNil(state)
    }

    func testWhitespaceIsTrimmed() throws {
        let (code, state) = try ClaudeLogin.parse("  abc123#xyz789\n")
        XCTAssertEqual(code, "abc123")
        XCTAssertEqual(state, "xyz789")
    }

    /// Copying the address bar instead of the code is a common slip.
    func testWholeCallbackURL() throws {
        let (code, state) = try ClaudeLogin.parse(
            "https://platform.claude.com/oauth/code/callback?code=abc123&state=xyz789")
        XCTAssertEqual(code, "abc123")
        XCTAssertEqual(state, "xyz789")
    }

    func testURLWithoutACodeIsRejected() {
        XCTAssertThrowsError(try ClaudeLogin.parse("https://platform.claude.com/oauth/code/callback"))
    }

    func testEmptyPasteIsRejected() {
        XCTAssertThrowsError(try ClaudeLogin.parse("   "))
    }

    /// A `#` with nothing before it is not a code.
    func testMissingCodeBeforeTheSeparatorIsRejected() {
        XCTAssertThrowsError(try ClaudeLogin.parse("#xyz789"))
    }
}

final class ClaudeLoginAttemptTests: XCTestCase {
    private func query(_ attempt: ClaudeLogin.Attempt) -> [String: String] {
        let items = URLComponents(url: attempt.url, resolvingAgainstBaseURL: false)?
            .queryItems ?? []
        return Dictionary(items.compactMap { item in
            item.value.map { (item.name, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    func testAuthorizeURLCarriesThePKCEChallenge() throws {
        let attempt = try ClaudeLogin.begin()
        let parameters = query(attempt)

        XCTAssertEqual(attempt.url.host, "claude.com")
        XCTAssertEqual(parameters["client_id"], Claude.clientID)
        XCTAssertEqual(parameters["response_type"], "code")
        XCTAssertEqual(parameters["redirect_uri"], ClaudeLogin.redirectURI)
        XCTAssertEqual(parameters["code_challenge_method"], "S256")
        XCTAssertEqual(parameters["state"], attempt.state)
        XCTAssertEqual(parameters["scope"], ClaudeLogin.scopes.joined(separator: " "))

        // The challenge must be the verifier's SHA-256, or the exchange fails.
        let expected = ClaudeLogin.base64URL(
            Data(SHA256.hash(data: Data(attempt.verifier.utf8))))
        XCTAssertEqual(parameters["code_challenge"], expected)
    }

    /// base64url: no padding, and none of the characters that would need
    /// escaping in a query string.
    func testTokensAreURLSafe() throws {
        let attempt = try ClaudeLogin.begin()
        for token in [attempt.verifier, attempt.state] {
            XCTAssertFalse(token.contains("="))
            XCTAssertFalse(token.contains("+"))
            XCTAssertFalse(token.contains("/"))
            XCTAssertGreaterThanOrEqual(token.count, 43)
        }
    }

    func testEachAttemptIsFresh() throws {
        let first = try ClaudeLogin.begin()
        let second = try ClaudeLogin.begin()
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertNotEqual(first.state, second.state)
    }

    func testLoginHintIsOmittedWhenThereIsNoEmail() throws {
        XCTAssertNil(query(try ClaudeLogin.begin())["login_hint"])
        XCTAssertNil(query(try ClaudeLogin.begin(email: ""))["login_hint"])
        XCTAssertEqual(
            query(try ClaudeLogin.begin(email: "you@example.com"))["login_hint"],
            "you@example.com")
    }
}
