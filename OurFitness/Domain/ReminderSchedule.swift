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

    // MARK: - Repeat interval

    /// Generic bounds for how often a reminder repeats: daily through yearly.
    ///
    /// `PlantCatalog` keeps its own narrower 2...60 range, which governs the
    /// seeded-watering math (baseline x light multiplier) and nothing else.
    /// These are the bounds every reminder control and every sync-path clamp
    /// should use — a sourdough starter is fed daily and a smoke-alarm battery
    /// is changed yearly, neither of which fits a houseplant's range.
    public static let minIntervalDays = 1
    public static let maxIntervalDays = 365

    public static func clampInterval(_ days: Int) -> Int {
        min(maxIntervalDays, max(minIntervalDays, days))
    }

    /// A named cadence offered as a one-tap choice, so reaching "yearly" isn't
    /// 364 stepper taps. `days` remains the only thing stored on a reminder —
    /// a preset is purely a UI shortcut, and an interval matching none of them
    /// is equally valid.
    public struct IntervalPreset: Identifiable, Equatable, Sendable {
        public let days: Int
        public let label: String
        public var id: Int { days }

        public init(days: Int, label: String) {
            self.days = days
            self.label = label
        }
    }

    public static let intervalPresets: [IntervalPreset] = [
        IntervalPreset(days: 1, label: "Daily"),
        IntervalPreset(days: 2, label: "Every 2 days"),
        IntervalPreset(days: 3, label: "Every 3 days"),
        IntervalPreset(days: 7, label: "Weekly"),
        IntervalPreset(days: 14, label: "Every 2 weeks"),
        IntervalPreset(days: 30, label: "Monthly"),
        IntervalPreset(days: 90, label: "Every 3 months"),
        IntervalPreset(days: 180, label: "Every 6 months"),
        IntervalPreset(days: 365, label: "Yearly")
    ]

    /// "Daily" / "Weekly" / "Every 5 days" — the preset's name when one
    /// matches, otherwise a plain day count. Lives here for the same reason
    /// `dueLabel` does: this file compiles into both the iOS and watch targets,
    /// so a cadence can't end up worded one way on the phone and another on the
    /// wrist. Also the single fix for the "Every 1 days" plural bug that
    /// hand-rolled interpolation kept reintroducing at each call site.
    public static func intervalLabel(days: Int) -> String {
        if let preset = intervalPresets.first(where: { $0.days == days }) { return preset.label }
        // Pluralised in the fallback too, the same way `dueLabel` does it below.
        // A bare "Every \(days) days" would be correct only because 1 happens to
        // be a preset — renaming or dropping "Daily" would silently reintroduce
        // the very bug this function exists to prevent.
        return "Every \(days) day\(days == 1 ? "" : "s")"
    }

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
