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

    /// Reproduces `str(raw.get("planType", raw.get("plan_type", "")))`.
    ///
    /// KNOWN QUIRK, kept for parity: when the key is present but JSON null,
    /// Python yields the literal string "None" and the UI shows a plan called
    /// "None". The Rust collector yielded "" instead. Python is the reference,
    /// so this matches Python — but it is a bug in both, and fixing it belongs
    /// in cli/usage_monitor.py first. See PLAN.md.
    static func planName(_ limits: [String: Any]) -> String {
        if let value = limits["planType"] { return pythonStr(value) }
        if let value = limits["plan_type"] { return pythonStr(value) }
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
