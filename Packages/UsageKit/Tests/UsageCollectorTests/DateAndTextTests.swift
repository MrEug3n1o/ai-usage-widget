import XCTest
@testable import UsageCollector

/// Expectations produced by running the Python reference, not by reasoning
/// about what the output ought to be.
final class DatesTests: XCTestCase {
    /// Cursor's subscriptionCycleStart is an epoch in MILLISECONDS.
    func testNextMonthKeepsTheDayAndTimeOfDay() {
        // 2026-01-15T10:30:00Z
        XCTAssertEqual(Dates.nextMonthISO(1_768_473_000_000), "2026-02-15T10:30:00+00:00")
    }

    /// Jan 31 has no counterpart in February — clamp to the last day.
    func testNextMonthClampsToShorterMonth() {
        // 2026-01-31T00:00:00Z
        XCTAssertEqual(Dates.nextMonthISO(1_769_817_600_000), "2026-02-28T00:00:00+00:00")
    }

    func testNextMonthRollsTheYear() {
        // 2026-12-10T00:00:00Z
        XCTAssertEqual(Dates.nextMonthISO(1_796_860_800_000), "2027-01-10T00:00:00+00:00")
    }

    /// Leap year, so February really does have a 29th.
    func testNextMonthClampsToLeapFebruary() {
        // 2028-01-31T00:00:00Z
        XCTAssertEqual(Dates.nextMonthISO(1_832_889_600_000), "2028-02-29T00:00:00+00:00")
    }

    func testISOShapeMatchesPythonIsoformat() {
        XCTAssertEqual(Dates.epochToISO(1_770_000_000), "2026-02-02T02:40:00+00:00")
    }
}

final class TextTests: XCTestCase {
    /// Python's str.title(), which capitalizes after every non-letter. The Rust
    /// collector only touched the first character and disagreed here.
    func testTitleCaseMatchesPython() {
        XCTAssertEqual(Text.titleCase("team"), "Team")
        XCTAssertEqual(Text.titleCase("TEAM"), "Team")
        XCTAssertEqual(Text.titleCase("team_pro"), "Team_Pro")
        XCTAssertEqual(Text.titleCase("free trial"), "Free Trial")
        XCTAssertEqual(Text.titleCase(""), "")
    }
}
