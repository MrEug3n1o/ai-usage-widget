import XCTest
@testable import UsageCollector

final class CodexTests: XCTestCase {
    func testMeterLabels() {
        XCTAssertEqual(Codex.meterLabel(minutes: 300, fallback: "primary"), "Session")
        XCTAssertEqual(Codex.meterLabel(minutes: 10_080, fallback: "secondary"), "Weekly")
        XCTAssertEqual(Codex.meterLabel(minutes: 60, fallback: "primary"), "60 min")
        // Python renders a float minute count as-is; %.0f would round it away.
        XCTAssertEqual(Codex.meterLabel(minutes: 90.5, fallback: "primary"), "90.5 min")
        XCTAssertEqual(Codex.meterLabel(minutes: nil, fallback: "primary"), "primary")
    }

    /// Documented quirk: Python's `str(None)` yields the literal "None" and the
    /// UI shows a plan called "None". Reproduced deliberately for parity — the
    /// fix belongs in cli/usage_monitor.py first. If this test starts failing
    /// because the reference was fixed, delete it rather than "restoring" it.
    func testNullPlanTypeBecomesTheStringNone() {
        XCTAssertEqual(Codex.planName(["planType": NSNull()]), "None")
    }

    func testPlanNamePrefersCamelCaseThenSnakeThenEmpty() {
        XCTAssertEqual(Codex.planName(["planType": "plus", "plan_type": "pro"]), "plus")
        XCTAssertEqual(Codex.planName(["plan_type": "pro"]), "pro")
        XCTAssertEqual(Codex.planName([:]), "")
    }

    /// JSON booleans bridge to NSNumber and must not print as 1/0.
    func testPythonStrMatchesPythonsStr() {
        XCTAssertEqual(Codex.pythonStr("plus"), "plus")
        XCTAssertEqual(Codex.pythonStr(NSNull()), "None")
        XCTAssertEqual(Codex.pythonStr(NSNumber(value: true)), "True")
        XCTAssertEqual(Codex.pythonStr(NSNumber(value: false)), "False")
        XCTAssertEqual(Codex.pythonStr(NSNumber(value: 42)), "42")
    }

    /// The JWT payload is base64url and usually unpadded; decoding must add the
    /// padding back or the claims silently vanish and the email goes blank.
    func testEmailDecodesUnpaddedBase64URL() throws {
        let claims = #"{"email":"someone@example.com"}"#
        var payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        payload = payload.replacingOccurrences(of: "=", with: "")   // strip padding
        let token = "header.\(payload).signature"

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".codex"),
                                                withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["tokens": ["id_token": token]])
            .write(to: dir.appendingPathComponent(".codex/auth.json"))
        defer { try? FileManager.default.removeItem(at: dir) }

        setenv("HOME", dir.path, 1)
        defer { unsetenv("HOME") }
        XCTAssertEqual(Codex.email(), "someone@example.com")
    }

    func testEmailIsEmptyWhenThereIsNoAuthFile() {
        setenv("HOME", NSTemporaryDirectory() + UUID().uuidString, 1)
        defer { unsetenv("HOME") }
        XCTAssertEqual(Codex.email(), "")
    }
}
