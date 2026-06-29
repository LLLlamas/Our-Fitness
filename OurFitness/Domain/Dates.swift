// All date math lives here so timezone handling is in exactly one place.
// Day boundaries are local-calendar by design.

import Foundation

public enum Dates {

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.calendar = Calendar(identifier: .iso8601)
        return f
    }()

    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    private static let shortMonthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let timeAgoFallbackFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()

    /// Local YYYY-MM-DD for a given Date (defaults to now).
    public static func dayKey(_ date: Date = Date()) -> String {
        dayFormatter.string(from: date)
    }

    /// Parse a YYYY-MM-DD back to a local-midnight Date. Returns nil on bad input.
    public static func date(fromDayKey key: String) -> Date? {
        dayFormatter.date(from: key)
    }

    /// Converts a "yyyy-MM-dd" dayKey to a localized long date string (e.g. "June 1, 2026").
    /// Lexicographic sort on yyyy-MM-dd keys is chronologically correct — no Date conversion needed for ordering.
    public static func formatLong(_ key: String) -> String {
        guard let d = date(fromDayKey: key) else { return key }
        return longDateFormatter.string(from: d)
    }

    /// Short month+day label for a dayKey, e.g. "Jun 1". Used for compact UI chips.
    public static func formatShort(_ key: String) -> String {
        guard let d = date(fromDayKey: key) else { return key }
        return shortMonthDayFormatter.string(from: d)
    }

    /// Inclusive array of dayKeys ending at `end` (default today), `days` long, oldest first.
    public static func lastNDays(_ days: Int, end: Date = Date()) -> [String] {
        guard days > 0 else { return [] }
        let cal = Calendar.current
        let endStart = cal.startOfDay(for: end)
        var out: [String] = []
        out.reserveCapacity(days)
        for i in stride(from: days - 1, through: 0, by: -1) {
            if let d = cal.date(byAdding: .day, value: -i, to: endStart) {
                out.append(dayKey(d))
            }
        }
        return out
    }

    /// Local start of yesterday for the supplied clock time.
    public static func startOfYesterday(now: Date = Date()) -> Date {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        return cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
    }

    /// True when `date` falls in today's or yesterday's local calendar day.
    public static func isTodayOrYesterday(_ date: Date, now: Date = Date()) -> Bool {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)
        let yesterdayStart = startOfYesterday(now: now)
        let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart) ?? now
        return date >= yesterdayStart && date < tomorrowStart
    }

    /// Whole days between two dayKeys.
    public static func daysBetween(_ a: String, _ b: String) -> Int {
        guard let da = date(fromDayKey: a), let db = date(fromDayKey: b) else { return 0 }
        let comps = Calendar.current.dateComponents([.day], from: da, to: db)
        return comps.day ?? 0
    }

    /// "just now", "5m ago", "3h ago", or "Mon 3:42 PM".
    public static func formatTimeAgo(_ ts: Date, now: Date = Date()) -> String {
        let diff = max(0, now.timeIntervalSince(ts))
        let minutes = Int(diff / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return timeAgoFallbackFormatter.string(from: ts)
    }
}
