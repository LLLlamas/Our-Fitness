// Habit inference for medication reminders: "you usually take this around
// 8am — it hasn't been logged yet today."
//
// Two kinds of timing live here and they are handled in deliberately different
// ways:
//
//   SET times (`ReminderDTO.scheduledMinutesOfDay`, stated by the user) are
//   alarms. Each becomes a daily repeating notification at that clock time, so
//   nothing in this file computes a fire instant for them and nothing has to
//   re-arm them — see ReminderNotificationService. What this file offers them
//   is clock formatting and reading a log back against them.
//
//   The OBSERVED time (`typicalMinuteOfDay`) is inferred from the log for a
//   medication with no set times, and DOES need a computed next-fire instant,
//   which is what `nextFireDate` is for. That path is unchanged.
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

    /// "8:00 AM, 8:00 PM" — every set time in order, for a card or a stats row.
    /// Empty string when there are none, which callers treat as "show nothing".
    public static func clockList(_ times: [Int], calendar: Calendar = .current) -> String {
        normalizedTimes(times)
            .map { clockLabel(minuteOfDay: $0, calendar: calendar) }
            .joined(separator: ", ")
    }

    /// Doses logged within this many minutes of their set time read as "on
    /// time" rather than as a number — the picker stores whole minutes, and a
    /// 3-minute gap is noise, not information.
    public static let onTimeToleranceMinutes = 5

    /// "12 min after 8:00 AM" / "20 min before 8:00 AM" / "On time", read
    /// against the closest set time. A plain statement of when the LOG happened
    /// relative to a time the user set — never a judgement about the dose
    /// itself, which the app cannot make (see the safety note in
    /// ReminderNotificationService).
    ///
    /// nil when there are no set times, which is the signal to render nothing
    /// at all rather than a placeholder.
    public static func timingLabel(loggedAt: Date, times: [Int], calendar: Calendar) -> String? {
        guard let time = nearestTime(to: loggedAt, times: times, calendar: calendar),
              let delta = minutesFromNearest(logged: loggedAt, times: times, calendar: calendar)
        else { return nil }
        if abs(delta) <= onTimeToleranceMinutes { return "On time" }
        let gap = durationLabel(minutes: abs(delta))
        let clock = clockLabel(minuteOfDay: time, calendar: calendar)
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

    // MARK: - Set times

    /// Clamped, de-duplicated and sorted. Every stored list goes through this,
    /// so nothing downstream has to cope with 8:00 appearing twice or the
    /// evening dose sitting before the morning one.
    public static func normalizedTimes(_ times: [Int]) -> [Int] {
        Array(Set(times.map(clampMinuteOfDay))).sorted()
    }

    /// Signed minutes between a logged dose and the set time it belongs to —
    /// positive = logged after, negative = logged before. nil when there are no
    /// set times.
    ///
    /// The dose is matched to the CLOSEST set time, which is what makes this
    /// work for a twice-daily medication: a log at 20:14 reads against the 20:00
    /// dose, not the 08:00 one. Distance wraps around midnight, so an 11pm dose
    /// logged at 12:20am is 80 minutes late rather than 22 hours early.
    public static func minutesFromNearest(logged: Date, times: [Int],
                                          calendar: Calendar) -> Int? {
        guard let time = nearestTime(to: logged, times: times, calendar: calendar) else { return nil }
        return wrapped(minuteOfDay(of: logged, calendar: calendar) - time)
    }

    /// Which set time a logged dose reads against — the closest one, wrapping
    /// around midnight. nil when there are no set times.
    public static func nearestTime(to logged: Date, times: [Int], calendar: Calendar) -> Int? {
        let times = normalizedTimes(times)
        guard !times.isEmpty else { return nil }
        let loggedMinute = minuteOfDay(of: logged, calendar: calendar)
        return times.min { abs(wrapped(loggedMinute - $0)) < abs(wrapped(loggedMinute - $1)) }
    }

    /// Shifts a raw minute difference into -720..<720, i.e. reports it against
    /// the nearest occurrence rather than the same calendar day's.
    private static func wrapped(_ delta: Int) -> Int {
        var d = delta
        if d > minutesPerDay / 2 { d -= minutesPerDay }
        if d < -minutesPerDay / 2 { d += minutesPerDay }
        return d
    }

    /// How many of today's set times have come round already — the count of
    /// doses the day has called for so far. Compared against the number logged
    /// today to decide whether anything is outstanding; deliberately a count
    /// rather than a per-slot matching, because which physical dose a given log
    /// was meant to be is not something the app can know.
    public static func timesReached(_ times: [Int], now: Date, calendar: Calendar) -> Int {
        let nowMinute = minuteOfDay(of: now, calendar: calendar)
        return normalizedTimes(times).filter { $0 <= nowMinute }.count
    }

    // MARK: - Today

    public static func hasLogToday(_ timestamps: [Date], now: Date, calendar: Calendar) -> Bool {
        timestamps.contains { calendar.isDate($0, inSameDayAs: now) }
    }

    // MARK: - Scheduling

    /// When to fire the "hasn't been logged yet" nudge for a medication with NO
    /// set times: the typical time plus a grace period. Today if nothing is
    /// logged yet today and that instant is still ahead; otherwise the same
    /// clock time tomorrow. nil when there's no usable history.
    ///
    /// One day of history is enough to schedule (that is the spec's
    /// yesterday-based reminder, as the degenerate median). Set times never come
    /// through here — they are daily repeating alarms with no instant to
    /// compute and no grace period, because the user picked the minute.
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
