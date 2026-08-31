import XCTest
@testable import UsageCollector

final class MoneyTests: XCTestCase {
    /// Values arrive in minor units with the scale in decimal_places.
    func testKnownCurrenciesUseTheirSymbol() {
        XCTAssertEqual(Claude.money(1234, currency: "USD", places: 2), "$12.34")
        XCTAssertEqual(Claude.money(1234, currency: "brl", places: 2), "R$12.34")
        XCTAssertEqual(Claude.money(1234, currency: "EUR", places: 2), "€12.34")
        XCTAssertEqual(Claude.money(1234, currency: "GBP", places: 2), "£12.34")
    }

    /// An unknown currency is spelled out, uppercased, with a trailing space.
    func testUnknownCurrencyFallsBackToItsCode() {
        XCTAssertEqual(Claude.money(1234, currency: "jpy", places: 2), "JPY 12.34")
    }

    func testNoCurrencyMeansNoPrefix() {
        XCTAssertEqual(Claude.money(1234, currency: "", places: 2), "12.34")
    }

    /// places drives both the scale and the printed precision.
    func testZeroDecimalPlaces() {
        XCTAssertEqual(Claude.money(1234, currency: "USD", places: 0), "$1234")
    }
}

final class ExtraUsageTests: XCTestCase {
    /// No credits field at all means the account has no extra usage.
    func testNilWhenUsedCreditsIsAbsent() {
        XCTAssertNil(Claude.extraUsageDetail([:]))
    }

    /// Disabled AND nothing spent is the ordinary case; say nothing.
    func testNilWhenDisabledAndNothingSpent() {
        XCTAssertNil(Claude.extraUsageDetail(["used_credits": 0, "is_enabled": false]))
    }

    /// Credits already spent keep showing after extra usage is turned off.
    func testSpentCreditsSurviveBeingDisabled() {
        XCTAssertEqual(
            Claude.extraUsageDetail([
                "used_credits": 500, "is_enabled": false,
                "decimal_places": 2, "currency": "USD",
            ]),
            "Extra usage: $5.00 · off")
    }

    func testEnabledWithoutACapShowsOnlyWhatWasSpent() {
        XCTAssertEqual(
            Claude.extraUsageDetail([
                "used_credits": 750, "is_enabled": true,
                "decimal_places": 2, "currency": "USD",
            ]),
            "Extra usage: $7.50")
    }

    func testMonthlyCapAddsTheLimitAndPercentage() {
        XCTAssertEqual(
            Claude.extraUsageDetail([
                "used_credits": 2500, "monthly_limit": 10_000, "utilization": 25,
                "is_enabled": true, "decimal_places": 2, "currency": "USD",
            ]),
            "Extra usage: $25.00 / $100.00 (25%)")
    }

    /// With pay-as-you-go credits `utilization` comes back null, so the
    /// percentage has to be derived from what was spent against the cap.
    func testPercentageIsDerivedWhenUtilizationIsMissing() {
        XCTAssertEqual(
            Claude.extraUsageDetail([
                "used_credits": 5000, "monthly_limit": 10_000,
                "is_enabled": true, "decimal_places": 2, "currency": "USD",
            ]),
            "Extra usage: $50.00 / $100.00 (50%)")
    }
}

final class ExpiryTests: XCTestCase {
    private func credential(expiresInMS: Double) -> [String: Any] {
        ["claudeAiOauth": ["expiresAt": Claude.nowMS() + expiresInMS]]
    }

    func testTokenComfortablyAheadIsNotExpiring() {
        XCTAssertFalse(Claude.expiring(credential(expiresInMS: 3_600_000)))
    }

    /// Inside the two minute window it counts as expiring, so a reading never
    /// begins with a token that dies mid-request.
    func testTokenInsideTheRefreshWindowIsExpiring() {
        XCTAssertTrue(Claude.expiring(credential(expiresInMS: 60_000)))
    }

    func testAlreadyExpiredIsExpiring() {
        XCTAssertTrue(Claude.expiring(credential(expiresInMS: -1)))
    }

    /// A malformed credential must read as expiring, not as valid forever.
    func testMissingExpiryIsExpiring() {
        XCTAssertTrue(Claude.expiring([:]))
        XCTAssertTrue(Claude.expiring(["claudeAiOauth": [:]]))
    }
}

final class ClaudeSourceTests: XCTestCase {
    /// The service name Claude Code derives for a CLAUDE_CONFIG_DIR: the bare
    /// name for ~/.claude, else an 8-hex-char sha256 of the dir path.
    func testKeychainServiceForTheDefaultDir() {
        let dir = Config.home.appendingPathComponent(".claude")
        XCTAssertEqual(ClaudeSource.keychainService(for: dir), "Claude Code-credentials")
    }

    func testKeychainServiceForACustomDir() {
        let dir = URL(fileURLWithPath: "/tmp/custom-claude")
        let service = ClaudeSource.keychainService(for: dir)
        XCTAssertTrue(service.hasPrefix("Claude Code-credentials-"))
        XCTAssertEqual(service.dropFirst("Claude Code-credentials-".count).count, 8)
    }

    /// Pinned against Python: hashlib.sha256(str(path).encode()).hexdigest()[:8]
    func testKeychainHashMatchesThePythonReference() {
        XCTAssertEqual(ClaudeSource.keychainHash(URL(fileURLWithPath: "/tmp/custom-claude")),
                       "5204cebd")
    }

    func testFileSourceResolvesToItsParentDirectory() {
        let dir = ClaudeSource.sourceConfigDir("file:/home/x/.claude/.credentials.json")
        XCTAssertEqual(dir?.path, "/home/x/.claude")
    }

    func testBareKeychainSourceResolvesToTheDefaultDir() {
        let dir = ClaudeSource.sourceConfigDir("keychain:Claude Code-credentials")
        XCTAssertEqual(dir?.path, Config.home.appendingPathComponent(".claude").path)
    }

    func testUnknownSourceResolvesToNothing() {
        XCTAssertNil(ClaudeSource.sourceConfigDir("nonsense:whatever"))
    }

    func testReadingAnUnknownSourceThrows() {
        XCTAssertThrowsError(try ClaudeSource.read("nonsense:whatever"))
        // Guards against a source id pointing the Keychain read anywhere else.
        XCTAssertThrowsError(try ClaudeSource.read("keychain:Some Other Service"))
    }
}

final class AdoptionGateTests: XCTestCase {
    /// The first look at a source is always allowed; a second look at the same
    /// version is not. That is what keeps a profile waiting on the CLI from
    /// re-reading the Keychain — and re-prompting — once a minute.
    func testSameVersionIsReadOnlyOnce() async {
        let gate = AdoptionGate()
        var read = await gate.shouldRead(profile: "/p", version: "1")
        XCTAssertTrue(read)
        read = await gate.shouldRead(profile: "/p", version: "1")
        XCTAssertFalse(read)
    }

    /// A CLI refresh bumps the source's modification date, so the next poll
    /// picks the new token up.
    func testANewVersionIsReadAgain() async {
        let gate = AdoptionGate()
        _ = await gate.shouldRead(profile: "/p", version: "1")
        let read = await gate.shouldRead(profile: "/p", version: "2")
        XCTAssertTrue(read)
    }

    /// A source we cannot even stat is one version, not a fresh one each time.
    func testUnknownVersionIsStillOnlyReadOnce() async {
        let gate = AdoptionGate()
        _ = await gate.shouldRead(profile: "/p", version: nil)
        let read = await gate.shouldRead(profile: "/p", version: nil)
        XCTAssertFalse(read)
    }

    func testProfilesAreGatedIndependently() async {
        let gate = AdoptionGate()
        _ = await gate.shouldRead(profile: "/a", version: "1")
        let read = await gate.shouldRead(profile: "/b", version: "1")
        XCTAssertTrue(read)
    }

    /// Relaunching the app is how a denied read is retried; forget() is the
    /// same reset, without the relaunch.
    func testForgetAllowsAnotherRead() async {
        let gate = AdoptionGate()
        _ = await gate.shouldRead(profile: "/p", version: "1")
        await gate.forget(profile: "/p")
        let read = await gate.shouldRead(profile: "/p", version: "1")
        XCTAssertTrue(read)
    }
}
