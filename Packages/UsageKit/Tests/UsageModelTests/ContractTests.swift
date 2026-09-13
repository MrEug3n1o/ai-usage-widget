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

final class PrimaryMeterTests: XCTestCase {
    /// The ring must show the session even when the weekly figure is higher —
    /// which it is for most of the week, so picking the larger number would
    /// hide the meter that actually gates the next prompt.
    func testSessionWinsOverAHigherWeekly() {
        let provider = Provider(name: "Claude", account: "work", meters: [
            Meter(label: "Session", percent: 9),
            Meter(label: "Weekly", percent: 22),
        ])
        XCTAssertEqual(provider.primaryMeter?.label, "Session")
        XCTAssertEqual(provider.primaryMeter?.percent, 9)
    }

    /// Order in the array must not decide it either.
    func testSessionWinsRegardlessOfPosition() {
        let provider = Provider(name: "Claude", account: "work", meters: [
            Meter(label: "Weekly", percent: 22),
            Meter(label: "Weekly Sonnet", percent: 40),
            Meter(label: "Session", percent: 9),
        ])
        XCTAssertEqual(provider.primaryMeter?.label, "Session")
    }

    /// Cursor bills monthly and has no session; fall back to its first meter
    /// rather than showing nothing.
    func testProviderWithoutASessionUsesItsFirstMeter() {
        let provider = Provider(name: "Cursor", account: "Business", meters: [
            Meter(label: "Total usage", percent: 30),
            Meter(label: "Auto", percent: 12),
        ])
        XCTAssertEqual(provider.primaryMeter?.label, "Total usage")
    }

    func testNoMetersMeansNoRing() {
        XCTAssertNil(Provider(name: "Codex", account: "ChatGPT").primaryMeter)
    }
}

final class IdentityTests: XCTestCase {
    /// The domain says which account it is — work or personal — so the label
    /// keeps it rather than showing only the local part.
    func testLabelKeepsTheWholeEmail() {
        let provider = Provider(name: "Claude", account: "erick.menezes",
                                email: "erick.menezes@revelo.com")
        XCTAssertEqual(provider.shortLabel, "erick.menezes@revelo.com")
    }

    /// Providers with no email fall back to the profile directory name.
    func testLabelFallsBackToTheAccount() {
        XCTAssertEqual(Provider(name: "Codex", account: "ChatGPT").shortLabel, "ChatGPT")
    }
}

final class WidgetSelectionTests: XCTestCase {
    func testRemainingFractionInvertsUsedPercent() {
        let meter = Meter(label: "Session", percent: 82)
        XCTAssertEqual(WidgetSelection.remainingFraction(of: meter), 0.18, accuracy: 1e-9)
    }

    func testRemainingFractionClamps() {
        XCTAssertEqual(WidgetSelection.remainingFraction(of: Meter(label: "x", percent: -5)), 1)
        XCTAssertEqual(WidgetSelection.remainingFraction(of: Meter(label: "x", percent: 150)), 0)
        XCTAssertNil(WidgetSelection.remainingFraction(of: Meter(label: "x")))
    }

    /// Most restrictive = lowest remaining, not session preference.
    func testTightestWindowPicksLowestRemaining() {
        let meters = [
            Meter(label: "Session", percent: 29, resetAt: "session"),
            Meter(label: "Weekly", percent: 82, resetAt: "weekly"),
        ]
        let tightest = WidgetSelection.tightestWindow(from: meters)
        XCTAssertEqual(tightest?.label, "Weekly")
        XCTAssertEqual(tightest?.percent, 82)
    }

    func testTightestWindowIgnoresMetersWithoutPercent() {
        let meters = [
            Meter(label: "Session"),
            Meter(label: "Weekly", percent: 40),
        ]
        XCTAssertEqual(WidgetSelection.tightestWindow(from: meters)?.label, "Weekly")
    }

    func testIndicatorsAlwaysReturnThreeInOrder() {
        let indicators = WidgetSelection.indicators(from: [])
        XCTAssertEqual(indicators.map(\.kind), [.cursor, .codex, .claude])
        XCTAssertTrue(indicators.allSatisfy { !$0.isAvailable })
    }

    func testIndicatorUsesTightestMeterAndParsesReset() {
        let reset = "2026-09-20T12:00:00Z"
        let providers = [
            Provider(name: "Codex", account: "ChatGPT", meters: [
                Meter(label: "Session", percent: 29, resetAt: "2026-09-13T14:00:00Z"),
                Meter(label: "Weekly", percent: 82, resetAt: reset),
            ]),
        ]
        let codex = WidgetSelection.indicator(for: .codex, from: providers)
        XCTAssertEqual(codex.remainingFraction!, 0.18, accuracy: 1e-9)
        XCTAssertEqual(codex.resetAt, Formatting.parseISO(reset))
    }

    func testUnconfiguredProviderIsUnavailable() {
        let providers = [
            Provider(name: "Cursor", account: "-", error: "set it up with cursor-admin"),
        ]
        let cursor = WidgetSelection.indicator(for: .cursor, from: providers)
        XCTAssertNil(cursor.remainingFraction)
        XCTAssertNil(cursor.resetAt)
    }

    func testRemainingSeverityThresholds() {
        XCTAssertEqual(RemainingSeverity(remainingFraction: 0.26), .normal)
        XCTAssertEqual(RemainingSeverity(remainingFraction: 0.25), .low)
        XCTAssertEqual(RemainingSeverity(remainingFraction: 0.11), .low)
        XCTAssertEqual(RemainingSeverity(remainingFraction: 0.10), .critical)
        XCTAssertEqual(RemainingSeverity(remainingFraction: nil), .unavailable)
    }
}

final class CompactResetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    func testCompactOmitsZeroParts() {
        XCTAssertEqual(
            Formatting.compactResetRemaining(until: now.addingTimeInterval(4 * 86_400), now: now),
            "4d")
        XCTAssertEqual(
            Formatting.compactResetRemaining(until: now.addingTimeInterval(2 * 3600), now: now),
            "2h")
        XCTAssertEqual(
            Formatting.compactResetRemaining(
                until: now.addingTimeInterval(2 * 3600 + 14 * 60), now: now),
            "2h 14m")
        XCTAssertEqual(
            Formatting.compactResetRemaining(until: now.addingTimeInterval(47 * 60), now: now),
            "47m")
        XCTAssertEqual(
            Formatting.compactResetRemaining(
                until: now.addingTimeInterval(1 * 86_400 + 4 * 3600), now: now),
            "1d 4h")
    }

    func testCompactUnknownIsEmDash() {
        XCTAssertEqual(Formatting.compactResetRemaining(until: nil, now: now), "—")
    }
}

