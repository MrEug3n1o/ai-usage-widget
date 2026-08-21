import Foundation
import UsageModel

/// Codex limits. Tries the `app-server` over JSON-RPC on stdio and, on failure,
/// falls back to the local session cache — flagging the downgrade in `details`,
/// like the Python collector. Port of `collect_codex`.
enum Codex {
    static func collect() async -> Provider {
        var downgrade: String?
        let raw: [String: Any]
        do {
            raw = try live()
        } catch {
            let liveError = error.localizedDescription
            do {
                raw = try cached()
                downgrade = liveError
            } catch {
                return Provider.failed(
                    name: "Codex", account: "ChatGPT",
                    error: "\(liveError); cache: \(error.localizedDescription)")
            }
        }

        let limits = raw.dict("rateLimits") ?? [:]
        var provider = Provider(
            name: "Codex", account: "ChatGPT",
            plan: Text.titleCase(planName(limits).replacingOccurrences(of: "_", with: " ")),
            email: email())
        if let downgrade {
            provider.details.append("⚠ local cache · app-server: \(downgrade)")
        }

        for key in ["primary", "secondary"] {
            guard let block = limits.dict(key), !block.isEmpty else { continue }
            let minutes = block.number("windowDurationMins") ?? block.number("window_minutes")
            let percent = block.number("usedPercent") ?? block.number("used_percent")
            var resetAt: String?
            if let epoch = block.number("resetsAt") ?? block.number("resets_at") {
                // Epoch seconds become ISO-8601 UTC.
                resetAt = Dates.epochToISO(epoch)
            } else {
                resetAt = block.string("resetsAt") ?? block.string("resets_at")
            }
            provider.meters.append(
                Meter(label: meterLabel(minutes: minutes, fallback: key),
                      percent: percent, resetAt: resetAt))
        }

        let credits = limits.dict("credits") ?? [:]
        if credits.bool("hasCredits") == true || credits.bool("has_credits") == true {
            provider.details.append("Credits: \(pythonStr(credits["balance"] ?? "?"))")
        }
        return provider
    }

    /// The window a limit covers, named. 300 min is the 5h session, 10080 the
    /// week; anything else is shown as its own duration.
    static func meterLabel(minutes: Double?, fallback: String) -> String {
        switch minutes {
        case 300: return "Session"
        case 10_080: return "Weekly"
        case .some(let m): return "\(Formatting.displayNumber(m)) min"
        case nil: return fallback
        }
    }

    /// The plan tier, or "" when the provider did not report one.
    ///
    /// Codex commonly sends planType as an explicit null. Both this and the
    /// reference used to stringify that to the literal "None" and put it on
    /// screen as the plan; treating null as absent is the fix, applied to
    /// cli/usage_monitor.py at the same time so the two stay in step.
    static func planName(_ limits: [String: Any]) -> String {
        for key in ["planType", "plan_type"] {
            guard let value = limits[key], !(value is NSNull) else { continue }
            let text = pythonStr(value)
            if !text.isEmpty { return text }
        }
        return ""
    }

    /// Python's `str()` for the JSON values that reach it.
    static func pythonStr(_ value: Any) -> String {
        switch value {
        case is NSNull: return "None"
        case let text as String: return text
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "True" : "False" }
            return Formatting.displayNumber(number.doubleValue)
        default: return "\(value)"
        }
    }
}
