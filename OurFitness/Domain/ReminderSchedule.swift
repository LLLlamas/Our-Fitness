// Due-date math for recurring reminders (plant watering and, later, other
// reminder categories). Fully generic — knows nothing about plants.
//
// Day semantics are calendar-day (local `startOfDay`), not 24-hour multiples,
// matching the `Dates` local-day convention used elsewhere: a reminder is
// "due Thursday", not "due 21:14 Wednesday". This keeps behavior honest across
// DST transitions and lets the notification trigger express "the due day at
// the preferred hour" directly via a calendar trigger.
//
// `now`/`calendar` are injectable for deterministic tests (never read the wall
// clock in time-sensitive Domain logic — see CLAUDE.md CI rules).

import Foundation

public enum ReminderSchedule {

    public static let defaultReminderHour = 9

    /// The due DAY (local midnight) for a reminder. Anchor is the last
    /// completion, falling back to when the reminder was created if it has
    /// never been done. A snooze pushes the due day later — never earlier —
    /// via `max`, so a stale snooze from before the natural due date is a no-op.
    public static func nextDueDay(
        lastDone: Date?,
        createdAt: Date,
        intervalDays: Int,
        snoozedUntil: Date? = nil,
        calendar: Calendar = .current
    ) -> Date {
        let anchor = calendar.startOfDay(for: lastDone ?? createdAt)
        let natural = calendar.date(byAdding: .day, value: intervalDays, to: anchor) ?? anchor
        guard let snoozedUntil else { return natural }
        let snoozeDay = calendar.startOfDay(for: snoozedUntil)
        return max(natural, snoozeDay)
    }

    /// Signed calendar-day distance from `now` to the due day. 0 = due today,
    /// negative = overdue by that many days, positive = due in that many days.
    public static func daysUntilDue(dueDay: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: dueDay)
        return calendar.dateComponents([.day], from: today, to: due).day ?? 0
    }

    public static func isDue(dueDay: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        daysUntilDue(dueDay: dueDay, now: now, calendar: calendar) <= 0
    }

    /// How many whole days overdue (0 if not overdue).
    public static func overdueDays(dueDay: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        max(0, -daysUntilDue(dueDay: dueDay, now: now, calendar: calendar))
    }

    /// The concrete instant to fire a notification for a due day: that day at
    /// `preferredHour`. If that instant has already passed (an overdue
    /// reminder, or a due-today reminder whose hour already elapsed), floors
    /// to the next occurrence of `preferredHour` strictly after `now` — a
    /// notification is never scheduled in the past.
    public static func fireDate(dueDay: Date, preferredHour: Int, now: Date = Date(), calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: dueDay))
        comps.hour = preferredHour
        comps.minute = 0
        comps.second = 0
        let candidate = calendar.date(from: comps) ?? dueDay

        guard candidate <= now else { return candidate }

        var nextComps = calendar.dateComponents([.year, .month, .day], from: now)
        nextComps.hour = preferredHour
        nextComps.minute = 0
        nextComps.second = 0
        let todayAtHour = calendar.date(from: nextComps) ?? now
        if todayAtHour > now { return todayAtHour }
        return calendar.date(byAdding: .day, value: 1, to: todayAtHour) ?? todayAtHour
    }

    /// "Snooze 1 day" target: tomorrow at the preferred hour.
    public static func snoozeDate(now: Date = Date(), preferredHour: Int, calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        var comps = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = preferredHour
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps) ?? tomorrow
    }

    /// Human due-status label from a signed days-until-due value: "Due today"
    /// / "N days overdue" / "in N days". Shared by both the iOS and watch UIs
    /// (this file compiles directly into both targets) so wording can't drift
    /// between phone and wrist.
    public static func dueLabel(daysUntilDue: Int) -> String {
        if daysUntilDue > 0 {
            return "in \(daysUntilDue) day\(daysUntilDue == 1 ? "" : "s")"
        }
        let overdue = -daysUntilDue
        return overdue == 0 ? "Due today" : "\(overdue) day\(overdue == 1 ? "" : "s") overdue"
    }
}
