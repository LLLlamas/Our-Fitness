// Habit inference for medication reminders: "you usually take this around
// 8am — it hasn't been logged yet today."
//
// Two timings can exist for one medication and they are not the same thing: a
// SET time (`ReminderDTO.scheduledMinuteOfDay`, stated by the user) and an
// OBSERVED one (`typicalMinuteOfDay`, read off the log). A set time always
// wins where both exist — it needs no history, so it works from day one, and
// history is read against it. The observed pattern remains the only timing for
// medications with no set time, exactly as before.
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

    public static let minutesPerDay = 24 * 60

    /// Valid range for a stated dose time. Clamped rather than failable: a
    /// nonsense stored value should degrade to a real clock time, not drop the
    /// medication's schedule on the floor.
    public static func clampMinuteOfDay(_ minute: Int) -> Int {
        min(max(minute, 0), minutesPerDay - 1)
    }

    /// Minute-of-day (0..<1440) of an instant.
    public static func minuteOfDay(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The inverse: an instant on `day` at that minute-of-day, for seeding a
    /// time picker from a stored minute. Set as wall-clock components, never
    /// added as an offset — see `fireInstant` for why that distinction matters.
    public static func date(minuteOfDay minute: Int, on day: Date, calendar: Calendar) -> Date? {
        let m = clampMinuteOfDay(minute)
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day)
    }

    /// "8:00 AM" for a minute-of-day, in the user's locale.
    ///
    /// Built on a fixed reference day rather than today, because only the clock
    /// face matters: rendering through a real date would let a daylight-saving
    /// boundary shift the label by an hour from the number that was stored.
    public static func clockLabel(minuteOfDay minute: Int, calendar: Calendar = .current) -> String {
        let m = clampMinuteOfDay(minute)
        var comps = DateComponents()
        comps.year = 2000
        comps.month = 1
        comps.day = 1
        comps.hour = m / 60
        comps.minute = m % 60
        guard let date = calendar.date(from: comps) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Doses logged within this many minutes of their set time read as "on
    /// time" rather than as a number — the picker stores whole minutes, and a
    /// 3-minute gap is noise, not information.
    public static let onTimeToleranceMinutes = 5

    /// "12 min after 8:00 AM" / "20 min before 8:00 AM" / "On time". A plain
    /// statement of when the LOG happened relative to the time the user set —
    /// never a judgement about the dose itself, which the app cannot make (see
    /// the safety note in ReminderNotificationService).
    ///
    /// nil when the medication has no set time, which is the signal to render
    /// nothing at all rather than a placeholder.
    public static func timingLabel(loggedAt: Date, scheduled: Int?, calendar: Calendar) -> String? {
        guard let scheduled,
              let delta = minutesFromScheduled(logged: loggedAt, scheduled: scheduled, calendar: calendar)
        else { return nil }
        let clock = clockLabel(minuteOfDay: scheduled, calendar: calendar)
        if abs(delta) <= onTimeToleranceMinutes { return "On time" }
        let gap = durationLabel(minutes: abs(delta))
        return delta > 0 ? "\(gap) after \(clock)" : "\(gap) before \(clock)"
    }

    /// "45 min" / "1 hr" / "2 hr 10 min". Minutes are dropped once the gap is
    /// whole hours, so the common cases stay short enough for a history row.
    public static func durationLabel(minutes: Int) -> String {
        let total = max(minutes, 0)
        let hours = total / 60
        let mins = total % 60
        if hours == 0 { return "\(mins) min" }
        if mins == 0 { return "\(hours) hr" }
        return "\(hours) hr \(mins) min"
    }

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

        let minutes = logs.map { minuteOfDay(of: $0, calendar: calendar) }.sorted()

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

    // MARK: - Set vs observed time

    /// The minute-of-day this medication's timing should key off: the stated
    /// dose time when there is one, otherwise the median of the recent log.
    /// nil only when neither exists.
    public static func effectiveMinuteOfDay(scheduled: Int?, timestamps: [Date],
                                            now: Date, calendar: Calendar) -> Int? {
        if let scheduled { return clampMinuteOfDay(scheduled) }
        return typicalMinuteOfDay(timestamps, now: now, calendar: calendar)
    }

    /// Signed minutes between a logged dose and the time it was set for —
    /// positive = logged after, negative = logged before. nil with no set time.
    ///
    /// Normalised to the NEAREST occurrence of the set time rather than the
    /// same calendar day's: a 11pm medication logged at 12:20am reads as 80
    /// minutes late, not 1,360 minutes early. Anything more than half a day
    /// either side is therefore reported against the adjacent day, which is the
    /// only reading that makes sense for a once-daily dose.
    public static func minutesFromScheduled(logged: Date, scheduled: Int?,
                                            calendar: Calendar) -> Int? {
        guard let scheduled else { return nil }
        var delta = minuteOfDay(of: logged, calendar: calendar) - clampMinuteOfDay(scheduled)
        if delta > minutesPerDay / 2 { delta -= minutesPerDay }
        if delta < -minutesPerDay / 2 { delta += minutesPerDay }
        return delta
    }

    // MARK: - Today

    public static func hasLogToday(_ timestamps: [Date], now: Date, calendar: Calendar) -> Bool {
        timestamps.contains { calendar.isDate($0, inSameDayAs: now) }
    }

    // MARK: - Scheduling

    /// When to fire the "hasn't been logged yet" nudge: the effective dose time
    /// plus a grace period. Today if nothing is logged yet today and that
    /// instant is still ahead; otherwise the same clock time tomorrow. nil when
    /// there is neither a set time nor usable history.
    ///
    /// A set time schedules from the very first day. Without one, a single day
    /// of history is enough (that is the spec's yesterday-based reminder, as the
    /// degenerate median). The grace period applies either way — someone whose
    /// dose is set for 8am is not late at 8:01.
    public static func nextFireDate(_ timestamps: [Date], scheduled: Int? = nil,
                                    now: Date, calendar: Calendar,
                                    graceMinutes: Int = defaultGraceMinutes) -> Date? {
        guard let minuteOfDay = effectiveMinuteOfDay(scheduled: scheduled, timestamps: timestamps,
                                                     now: now, calendar: calendar) else { return nil }

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

    /// The instant `minuteOfDay + graceMinutes` after the start of `dayStart`,
    /// expressed as a WALL-CLOCK time rather than an elapsed one.
    ///
    /// The distinction is the whole point. Adding the total as minutes would be
    /// an elapsed offset, and on the 23-hour spring-forward day that lands an
    /// 06:35 routine at 07:35 — an hour early by the clock the person actually
    /// reads. So the day part is added as calendar DAYS (letting the calendar
    /// absorb the short or long day) and the remainder is SET as an hour and
    /// minute. A grace period that spills past midnight is exactly the case
    /// where the total exceeds a day, which is why the split exists at all.
    private static func fireInstant(dayStart: Date, minuteOfDay: Int, graceMinutes: Int,
                                    calendar: Calendar) -> Date? {
        let total = minuteOfDay + graceMinutes
        guard let targetDay = calendar.date(byAdding: .day, value: total / minutesPerDay, to: dayStart) else {
            return nil
        }
        let remainder = total % minutesPerDay
        // A wall-clock time that doesn't exist on a spring-forward day (02:30)
        // resolves forward to the next real instant, which is the behaviour a
        // person expects from an alarm set for a skipped hour.
        return calendar.date(bySettingHour: remainder / 60, minute: remainder % 60,
                             second: 0, of: targetDay)
    }
}
