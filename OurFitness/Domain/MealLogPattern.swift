// Learned meal-logging times: "you usually log lunch around 12:30 — it isn't
// logged yet today."
//
// The meal counterpart of MedicationPattern's OBSERVED path, and built the
// same way: the median of each day's earliest log for a slot, today excluded,
// read off the log on demand (nothing stored — deleting entries erases the
// inference with them, and a drifting routine re-settles on its own).
//
// Differences from medication, each deliberate:
//   - Only breakfast / lunch / dinner are learned. Snacks, pre/post-workout and
//     "other" are irregular by nature; a "your snack isn't logged" ping is nagging.
//   - A slot needs `minDays` logged days in a 14-day window before it is
//     trusted at all — for scheduling too, not just for display. Skipping a meal
//     is normal, so one stray lunch log must not start daily lunch pings.
//   - No fallback default times. Before history exists there is no nudge; a
//     stock "12:00 lunch" ping for someone who never logs lunch is noise.
//   - Only REAL-TIME logs count: an entry whose timestamp falls on a different
//     day than its `date` key was back-filled from the day strip ("yesterday's
//     dinner", logged this morning) and says nothing about when that meal happens.
//   - Quiet hours: nothing is planned from 22:00 to 06:00 local.
//
// `now`/`calendar` are injectable on every entry point (see CLAUDE.md CI rules).
// Day keys are built from the injected calendar rather than `Dates.dayKey`,
// which is pinned to TimeZone.current; for the app's Calendar.current the two
// agree (both yyyy-MM-dd local).

import Foundation

public enum MealLogPattern {

    /// Slots that get a learned nudge, in day order.
    public static let trackedSlots: [Slot] = [.breakfast, .lunch, .dinner]

    /// Two weeks: long enough to see weekday + weekend habits at least twice,
    /// short enough that a changed routine takes over within a week or so.
    public static let lookbackDays = 14

    /// Distinct logged days (in the window, today excluded) before a slot's time
    /// is trusted — for scheduling AND display.
    public static let minDays = 4

    /// Minutes after the typical time before nudging. People log after eating,
    /// and someone whose lunch is "12:30" is not late at 12:45.
    public static let defaultGraceMinutes = 60

    /// Nothing is planned whose fire time lands at or after 22:00 or before
    /// 06:00 local — a learned 21:30 dinner should not ping at 22:30.
    public static let quietStartMinute = 22 * 60
    public static let quietEndMinute = 6 * 60

    /// Today plus the next two days. One-shot requests are only re-armed when
    /// the app runs, so this is how many days of nudges survive the app not
    /// being opened — after that they stop, which is the polite failure mode.
    public static let defaultHorizonDays = 3

    // MARK: - Day keys

    /// "yyyy-MM-dd" for `date` in `calendar`'s time zone — the same shape as
    /// `FoodLogEntryDTO.date`.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whether the entry was logged on the day it is filed under.
    static func isRealTime(_ entry: FoodLogEntryDTO, calendar: Calendar) -> Bool {
        dayKey(entry.timestamp, calendar: calendar) == entry.date
    }

    // MARK: - Recent history

    /// Earliest real-time log per local day for `slot`, across the last
    /// `lookbackDays` days EXCLUDING today, oldest first. Earliest-per-day so a
    /// second item added to lunch an hour later can't drag the time later.
    public static func recentDailyFirstLogs(_ entries: [FoodLogEntryDTO], slot: Slot,
                                            now: Date, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return [] }

        // Today is excluded for the same reason as MedicationPattern: today's
        // log is what the nudge checks FOR, not evidence about the routine.
        var firstByDay: [String: Date] = [:]
        for e in entries where e.slot == slot
            && e.timestamp >= windowStart && e.timestamp < today
            && isRealTime(e, calendar: calendar) {
            if let existing = firstByDay[e.date], existing <= e.timestamp { continue }
            firstByDay[e.date] = e.timestamp
        }
        return firstByDay.values.sorted()
    }

    // MARK: - Typical time

    /// Median minute-of-day of `recentDailyFirstLogs`, or nil below `minDays`.
    /// Median, not mean, so one late Sunday brunch doesn't move a steady 8am
    /// breakfast. Even counts average the two middle values.
    public static func typicalMinuteOfDay(_ entries: [FoodLogEntryDTO], slot: Slot,
                                          now: Date, calendar: Calendar) -> Int? {
        let logs = recentDailyFirstLogs(entries, slot: slot, now: now, calendar: calendar)
        guard logs.count >= minDays else { return nil }
        let minutes = logs.map { MedicationPattern.minuteOfDay(of: $0, calendar: calendar) }.sorted()
        let mid = minutes.count / 2
        if minutes.count % 2 == 1 { return minutes[mid] }
        return Int((Double(minutes[mid - 1] + minutes[mid]) / 2).rounded())
    }

    /// Every tracked slot with a trusted time, in day order. Empty = nothing
    /// learned yet (the Settings caption says so rather than inventing times).
    public static func learnedTimes(_ entries: [FoodLogEntryDTO], now: Date,
                                    calendar: Calendar) -> [(slot: Slot, minuteOfDay: Int)] {
        trackedSlots.compactMap { slot in
            typicalMinuteOfDay(entries, slot: slot, now: now, calendar: calendar).map { (slot, $0) }
        }
    }

    // MARK: - Planning

    public struct Nudge: Equatable, Sendable {
        public let slot: Slot
        /// The meal's day ("yyyy-MM-dd") — what "already logged" is checked against.
        public let dayKey: String
        /// Learned minute-of-day, for the notification copy.
        public let typicalMinuteOfDay: Int
        public let fireDate: Date
    }

    /// Every nudge that should be pending right now, across `horizonDays` days
    /// starting today, ordered by fire date. A slot is skipped on a day where it
    /// already has ANY entry (real-time or back-filled — either way it's logged),
    /// when its fire instant has passed, or when it falls in quiet hours.
    public static func plan(_ entries: [FoodLogEntryDTO], now: Date, calendar: Calendar,
                            horizonDays: Int = defaultHorizonDays,
                            graceMinutes: Int = defaultGraceMinutes) -> [Nudge] {
        let learned = learnedTimes(entries, now: now, calendar: calendar)
        guard !learned.isEmpty, horizonDays > 0 else { return [] }

        let logged = Set(entries.map { "\($0.date)|\($0.slot.rawValue)" })
        let today = calendar.startOfDay(for: now)
        var out: [Nudge] = []

        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            let key = dayKey(dayStart, calendar: calendar)
            for (slot, minute) in learned {
                guard !logged.contains("\(key)|\(slot.rawValue)") else { continue }
                let total = minute + graceMinutes
                // Spilling past midnight always lands in quiet hours (it is
                // before 06:00 by construction), so it is simply not planned.
                guard total < quietStartMinute, total >= quietEndMinute else { continue }
                // Wall-clock components, never an elapsed offset — on the
                // 23-hour spring-forward day an offset lands an hour early.
                guard let fire = calendar.date(bySettingHour: total / 60, minute: total % 60,
                                               second: 0, of: dayStart),
                      fire > now else { continue }
                out.append(Nudge(slot: slot, dayKey: key, typicalMinuteOfDay: minute, fireDate: fire))
            }
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }
}
