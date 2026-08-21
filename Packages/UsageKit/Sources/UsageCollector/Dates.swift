import Foundation

/// UTC date helpers for the reset fields. Output shape is
/// `YYYY-MM-DDTHH:MM:SS+00:00`, matching Python's `datetime.isoformat()` on a
/// UTC-aware value — the collectors' output is diffed against it.
enum Dates {
    private static var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    static func iso(_ date: Date) -> String {
        let p = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d+00:00",
                      p.year!, p.month!, p.day!, p.hour!, p.minute!, p.second!)
    }

    static func epochToISO(_ seconds: Double) -> String {
        iso(Date(timeIntervalSince1970: seconds))
    }

    /// Same day next month, clamped to that month's last day, from an epoch in
    /// **milliseconds**. Port of `next_month` — Cursor's billing cycle.
    static func nextMonthISO(_ epochMS: Double) -> String {
        let date = Date(timeIntervalSince1970: (epochMS / 1000).rounded(.down))
        var p = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var year = p.year!, month = p.month! + 1
        if month == 13 { year += 1; month = 1 }
        var target = DateComponents()
        target.year = year; target.month = month; target.day = 1
        let lastDay = utc.range(of: .day, in: .month, for: utc.date(from: target)!)!.count
        p.year = year; p.month = month; p.day = min(p.day!, lastDay)
        return iso(utc.date(from: p)!)
    }
}

enum Text {
    /// Python's `str.title()`: first letter of every alphabetic run uppercased,
    /// the rest lowercased. The Rust collector only uppercased the very first
    /// character, which differs on values like "team_pro" ("Team_Pro" vs
    /// "Team_pro"). Python is the reference.
    static func titleCase(_ value: String) -> String {
        var out = ""
        var startOfWord = true
        for ch in value {
            if ch.isLetter {
                out.append(startOfWord ? Character(ch.uppercased()) : Character(ch.lowercased()))
                startOfWord = false
            } else {
                out.append(ch)
                startOfWord = true
            }
        }
        return out
    }
}
