// Habit inference for medication reminders: "you usually take this around
// 8am — it hasn't been logged yet today."
//
// Unlike ReminderSchedule, which answers "which calendar DAY is this due",
// this file answers "at what TIME OF DAY does this user actually do it", read
// off the completion log rather than configured by hand. The two compose: the
// schedule decides the day, the pattern decides the moment within it.
//
// Everything is derived from timestamps on demand — nothing here is stored, so
// a pattern re-settles on its own as habits drift, and deleting events erases
// the inference with them.
//
// `now`/`calendar` are injectable on every entry point for deterministic tests
// (never read the wall clock in time-sensitive Domain logic — see CLAUDE.md CI
// rules). Day-scoping goes through the injected `calendar` rather than
// `Dates.dayKey`, which is pinned to TimeZone.current and would make tests
// depend on the machine running them.

import Foundation

public enum MedicationPattern {

    /// How far back the routine is read. A week is long enough to average out
    /// one late day and short enough that a changed schedule takes over quickly.
    public static let lookbackDays = 7

    /// How long after the typical time we wait before nudging. Someone whose
    /// routine is "8am" is not late at 8:01.
    public static let defaultGraceMinutes = 30

    /// Below this many recent days we don't claim a pattern in the UI.
    public static let minDaysForDisplay = 2

    // MARK: - Recent history

    /// Earliest log per local calendar day across the last `lookbackDays` days,
    /// EXCLUDING today, oldest first. Earliest-per-day so a second or third dose
    /// on a multi-dose day can't drag the routine later.
    public static func recentDailyFirstLogs(_ timestamps: [Date], now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return [] }

        // Today is excluded because a log made today is exactly what the nudge
        // is checking FOR — folding it into the pattern would let the pattern
        // chase itself later and later each day.
        var firstByDay: [Date: Date] = [:]
        for ts in timestamps.sorted() where ts >= windowStart && ts < today {
            let day = calendar.startOfDay(for: ts)
            if let existing = firstByDay[day], existing <= ts { continue }
            firstByDay[day] = ts
        }
        return firstByDay.values.sorted()
    }

    /// How many distinct recent days have a log (excluding today).
    public static func dayCount(_ timestamps: [Date], now: Date, calendar: Calendar) -> Int {
        recentDailyFirstLogs(timestamps, now: now, calendar: calendar).count
    }

    // MARK: - Typical time

    /// Median minute-of-day (0..<1440) of `recentDailyFirstLogs`; nil with no
    /// recent history. Median, not mean, so one 11:42am outlier doesn't move a
    /// steady 8am routine. Even counts average the two middle values.
    public static func typicalMinuteOfDay(_ timestamps: [Date], now: Date, calendar: Calendar) -> Int? {
        let logs = recentDailyFirstLogs(timestamps, now: now, calendar: calendar)
        guard !logs.isEmpty else { return nil }

        let minutes = logs.map { ts -> Int in
            let parts = calendar.dateComponents([.hour, .minute], from: ts)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }.sorted()

        let mid = minutes.count / 2
        if minutes.count % 2 == 1 { return minutes[mid] }
        return Int((Double(minutes[mid - 1] + minutes[mid]) / 2).rounded())
    }

    /// Whether a pattern is settled enough to state in the UI (>= minDaysForDisplay).
    ///
    /// Scheduling is happy with a single day of history; *claiming* a routine in
    /// copy is not — "you usually take this at 8am" off one data point reads as
    /// the app making things up.
    public static func hasDisplayablePattern(_ timestamps: [Date], now: Date, calendar: Calendar) -> Bool {
        dayCount(timestamps, now: now, calendar: calendar) >= minDaysForDisplay
    }

    // MARK: - Today

    public static func hasLogToday(_ timestamps: [Date], now: Date, calendar: Calendar) -> Bool {
        timestamps.contains { calendar.isDate($0, inSameDayAs: now) }
    }

    // MARK: - Scheduling

    /// When to fire the "hasn't been logged yet" nudge: the typical time plus a
    /// grace period. Today if nothing is logged yet today and that instant is
    /// still ahead; otherwise the same clock time tomorrow. nil when there's no
    /// usable history. One day of history is enough to schedule (that is the
    /// spec's yesterday-based reminder, as the degenerate median).
    public static func nextFireDate(_ timestamps: [Date], now: Date, calendar: Calendar,
                                    graceMinutes: Int = defaultGraceMinutes) -> Date? {
        guard let minuteOfDay = typicalMinuteOfDay(timestamps, now: now, calendar: calendar) else { return nil }

        let today = calendar.startOfDay(for: now)
        if !hasLogToday(timestamps, now: now, calendar: calendar),
           let todayFire = fireInstant(dayStart: today, minuteOfDay: minuteOfDay,
                                       graceMinutes: graceMinutes, calendar: calendar),
           todayFire > now {
            return todayFire
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
        return fireInstant(dayStart: calendar.startOfDay(for: tomorrow), minuteOfDay: minuteOfDay,
                           graceMinutes: graceMinutes, calendar: calendar)
    }

    /// Offsetting from the day's start by minutes through the calendar (rather
    /// than adding a time interval to a Date) is what makes a grace period that
    /// spills past midnight, and a DST day that is 23 or 25 hours long, land on
    /// the wall-clock time a person would expect.
    private static func fireInstant(dayStart: Date, minuteOfDay: Int, graceMinutes: Int,
                                    calendar: Calendar) -> Date? {
        calendar.date(byAdding: .minute, value: minuteOfDay + graceMinutes, to: dayStart)
    }
}
