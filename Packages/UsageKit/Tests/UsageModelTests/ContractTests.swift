import XCTest
@testable import UsageModel

/// The JSON shape is a contract shared with cli/usage_monitor.py in the
/// ai-usage-monitor repo. These tests exist to catch drift, not to prove Codable
/// works.
final class ContractTests: XCTestCase {
    private func encodeToObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Python's asdict emits `"percent": null`; Swift's synthesized Codable
    /// would omit the key entirely. The parity diff would fail on it.
    func testNilFieldsAreEncodedAsNullNotOmitted() throws {
        let object = try encodeToObject(Meter(label: "Session"))
        for key in ["percent", "reset_at", "used", "limit"] {
            XCTAssertTrue(object.keys.contains(key), "\(key) must be present as null, not omitted")
            XCTAssertTrue(object[key] is NSNull, "\(key) must encode as null")
        }
    }

    func testMeterUsesSnakeCaseKeys() throws {
        let object = try encodeToObject(Meter(label: "Session", percent: 42, resetAt: "2026-08-21T18:00:00Z"))
        XCTAssertEqual(object["reset_at"] as? String, "2026-08-21T18:00:00Z")
        XCTAssertNil(object["resetAt"])
    }

    func testProviderEncodesEveryContractField() throws {
        let object = try encodeToObject(Provider(name: "Claude", account: "work"))
        XCTAssertEqual(
            Set(object.keys),
            ["name", "account", "plan", "email", "standby", "meters", "details", "error"]
        )
    }

    func testUnconfiguredMatchesTheTauriRule() {
        let cursor = Provider(name: "Cursor", account: "-", error: "set it up with cursor-admin")
        XCTAssertTrue(cursor.isUnconfigured)

        let codex = Provider(
            name: "Codex", account: "-",
            error: "app-server did not start; no local session found either")
        XCTAssertTrue(codex.isUnconfigured)

        // A provider that WAS set up and then broke must keep showing its error.
        let broken = Provider(name: "Cursor", account: "team", error: "HTTP 401")
        XCTAssertFalse(broken.isUnconfigured)

        // Meters present means it is working, whatever the error says.
        let partial = Provider(
            name: "Codex", account: "-",
            meters: [Meter(label: "Session", percent: 10)],
            error: "app-server did not start; no local session found either")
        XCTAssertFalse(partial.isUnconfigured)
    }
}

final class FormattingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)
    private func iso(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(offset))
    }

    func testResetRemainingBuckets() {
        XCTAssertEqual(Formatting.resetRemaining(iso(2 * 86_400 + 3 * 3600), now: now), "2d 3h")
        XCTAssertEqual(Formatting.resetRemaining(iso(3 * 3600 + 40 * 60), now: now), "3h 40m")
        XCTAssertEqual(Formatting.resetRemaining(iso(12 * 60), now: now), "12m")
    }

    /// A window that has already rolled over reads "0m", never a negative.
    func testResetRemainingClampsToZero() {
        XCTAssertEqual(Formatting.resetRemaining(iso(-3600), now: now), "0m")
    }

    /// Missing or unparseable timestamps render as nothing at all — a
    /// placeholder would read as a real value.
    func testResetRemainingIsEmptyWhenUnusable() {
        XCTAssertEqual(Formatting.resetRemaining(nil, now: now), "")
        XCTAssertEqual(Formatting.resetRemaining("", now: now), "")
        XCTAssertEqual(Formatting.resetRemaining("not a date", now: now), "")
    }

    func testResetRemainingAcceptsFractionalSeconds() {
        XCTAssertEqual(Formatting.resetRemaining("2026-02-02T02:00:00.500Z",
                                                 now: Formatting.parseISO("2026-02-02T01:00:00Z")!),
                       "1h 0m")
    }

    /// Expectations taken from running cli/usage_monitor.py's display_number,
    /// not from what looks reasonable.
    func testDisplayNumber() {
        XCTAssertEqual(Formatting.displayNumber(12), "12")
        XCTAssertEqual(Formatting.displayNumber(12.25), "12.25")
        XCTAssertEqual(Formatting.displayNumber(0.05), "0.05")
        // %g collapses float noise; a shortest-round-trip formatter would not.
        XCTAssertEqual(Formatting.displayNumber(0.1 + 0.2), "0.3")
    }

    func testSeverityThresholds() {
        XCTAssertEqual(Severity(percent: nil), .unknown)
        XCTAssertEqual(Severity(percent: 64.9), .normal)
        XCTAssertEqual(Severity(percent: 65), .warning)
        XCTAssertEqual(Severity(percent: 84.9), .warning)
        XCTAssertEqual(Severity(percent: 85), .critical)
    }
}

/// Which providers are worth showing. A provider that was never set up is
/// noise; one that was set up and then broke must keep showing its error.
final class UnconfiguredTests: XCTestCase {
    private let authError =
        "⚠ local cache · app-server: {\"code\":-32600,\"message\":\"codex account "
        + "authentication required to read rate limits\"} (rateLimits phase, exit=None)"

    /// Codex installed but with no account signed in: the app-server answers,
    /// says it needs authentication, and there is nothing to report.
    func testCodexInstalledWithoutAnAccountIsUnconfigured() {
        let codex = Provider(name: "Codex", account: "ChatGPT", details: [authError])
        XCTAssertTrue(codex.isUnconfigured)
    }

    /// Codex not installed at all.
    func testCodexMissingEntirelyIsUnconfigured() {
        let codex = Provider(
            name: "Codex", account: "ChatGPT",
            error: "app-server did not start: No such file; cache: no local session found")
        XCTAssertTrue(codex.isUnconfigured)
    }

    /// Signed in and reporting: shown, even though the live call was downgraded
    /// to the session cache.
    func testCodexWithMetersIsShownEvenWhenDowngraded() {
        let codex = Provider(
            name: "Codex", account: "ChatGPT",
            meters: [Meter(label: "Session", percent: 12)],
            details: [authError])
        XCTAssertFalse(codex.isUnconfigured)
    }

    /// A genuine failure on a configured account must not be hidden — silently
    /// dropping it would read as "no limits" when the truth is "unknown".
    func testCodexFailingForAnotherReasonIsStillShown() {
        let codex = Provider(name: "Codex", account: "ChatGPT",
                             error: "app-server did not start: connection reset")
        XCTAssertFalse(codex.isUnconfigured)
    }

    func testCursorWithoutAKeyIsUnconfigured() {
        XCTAssertTrue(Provider(name: "Cursor", account: "Business", plan: "Team",
                               error: "set it up with: ai-usage cursor-cookie").isUnconfigured)
    }

    func testClaudeIsNeverHidden() {
        XCTAssertFalse(Provider(name: "Claude", account: "work",
                                error: "session revoked").isUnconfigured)
    }
}
