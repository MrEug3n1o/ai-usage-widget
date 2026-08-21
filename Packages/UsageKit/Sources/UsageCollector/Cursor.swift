import Foundation
import UsageModel

/// Cursor Business limits. Two methods in cursor.json: `admin_key` (team admin
/// API, preferred) or `dashboard_cookie` (internal dashboard endpoint, which
/// may break whenever Cursor changes it). Port of `collect_cursor`.
enum Cursor {
    static func collect() async -> Provider {
        guard FileManager.default.fileExists(atPath: Config.cursorConfig.path) else {
            // Python fills plan="Team" on this path; the Rust port left it
            // empty. Python is the reference.
            return Provider(
                name: "Cursor", account: "Business", plan: "Team",
                error: "set it up with: ai-usage cursor-cookie or cursor-admin")
        }
        do {
            guard let config = try Config.readJSON(Config.cursorConfig) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            return config.string("method") == "dashboard_cookie"
                ? try await byCookie(config)
                : try await byAdminKey(config)
        } catch {
            return Provider.failed(name: "Cursor", account: "Business",
                                   error: error.localizedDescription)
        }
    }

    private struct MissingField: Error, LocalizedError {
        let name: String
        var errorDescription: String? { "cursor.json has no \(name)" }
    }

    private static func byCookie(_ config: [String: Any]) async throws -> Provider {
        guard let token = config.string("session_cookie") else {
            throw MissingField(name: "session_cookie")
        }
        let headers = [
            "Cookie": "WorkosCursorSessionToken=\(token)",
            "User-Agent": "ai-usage-monitor",
        ]
        let data = try await HTTP.json(
            HTTP.request("https://cursor.com/api/usage-summary", headers: headers)
        ) as? [String: Any] ?? [:]

        // Identity is a nicety: a failure here must not lose the usage numbers.
        let email = (try? await HTTP.json(
            HTTP.request("https://cursor.com/api/auth/me", headers: headers)
        ) as? [String: Any])??.string("email") ?? ""

        var provider = Provider(
            name: "Cursor", account: "Business",
            plan: Text.titleCase(data.string("membershipType") ?? "Team"),
            email: email)

        let plan = data.dict("individualUsage")?.dict("plan") ?? [:]
        let rawUsed = plan.number("used") ?? 0
        let rawLimit = plan.number("limit") ?? 0
        let percent = rawLimit > 0 ? rawUsed * 100 / rawLimit : nil

        // The team dashboard shows request units at 1/4 of the internal values
        // returned by usage-summary (576/2000 -> 144/500).
        let scale: Double = data.string("limitType") == "team" ? 4 : 1
        let billingEnd = data.string("billingCycleEnd")
        provider.meters.append(Meter(
            label: "Usage",
            percent: percent,
            resetAt: billingEnd,
            // Round up: a partially consumed unit still counts as used.
            used: Formatting.displayNumber((rawUsed / scale).rounded(.up)),
            limit: Formatting.displayNumber(rawLimit / scale)))

        if let auto = plan.number("autoPercentUsed"), auto != 0 {
            provider.meters.append(Meter(label: "Auto usage", percent: auto, resetAt: billingEnd))
        }
        let demand = data.dict("individualUsage")?.dict("onDemand") ?? [:]
        if demand.bool("enabled") == true {
            let used = (demand.number("used") ?? 0) / 100
            provider.details.append(String(format: "On demand: $%.2f", used))
        }
        return provider
    }

    private static func byAdminKey(_ config: [String: Any]) async throws -> Provider {
        guard let key = config.string("admin_key") else { throw MissingField(name: "admin_key") }
        let email = config.string("email") ?? ""
        let auth = Data("\(key):".utf8).base64EncodedString()

        let data = try await HTTP.json(HTTP.request(
            "https://api.cursor.com/teams/spend",
            method: "POST",
            headers: ["Authorization": "Basic \(auth)", "Accept": "application/json"],
            jsonBody: ["searchTerm": email, "page": 1, "pageSize": 10]
        )) as? [String: Any] ?? [:]

        let members = (data.array("teamMemberSpend") ?? []).compactMap { $0 as? [String: Any] }
        guard let member = members.first(where: {
            $0.string("email")?.caseInsensitiveCompare(email) == .orderedSame
        }) ?? members.first else {
            throw SimpleError("user not found in the team response")
        }

        let reset = data.number("subscriptionCycleStart").map(Dates.nextMonthISO)
        var provider = Provider(name: "Cursor", account: "Business", plan: "Team", email: email)
        for (field, label) in [("totalPercentUsed", "Total usage"), ("autoPercentUsed", "Auto")] {
            if let percent = member.number(field) {
                provider.meters.append(Meter(label: label, percent: percent, resetAt: reset))
            }
        }
        let spent = (member.number("spendCents") ?? 0) / 100
        let limit = member.number("monthlyLimitDollars") ?? member.number("hardLimitOverrideDollars")
        provider.details.append(
            String(format: "Spend: $%.2f", spent)
                + (limit.map { String(format: " / $%.2f", $0) } ?? ""))
        return provider
    }
}

struct SimpleError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
