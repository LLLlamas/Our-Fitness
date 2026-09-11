// The medication record: every logged dose across every medication, grouped by
// the day it happened on.
//
// MedicationPattern answers "when does this one medication usually happen".
// This file answers the record-keeping question instead — "what was taken, on
// which day, at what time" — across the whole medication group at once, which
// is what a person reads back to a doctor or pharmacist.
//
// Nothing here is stored. Events are already an append-only log
// (`ReminderEventDTO`), so the history is a projection of that log and can
// never drift from it; deleting an event removes it from every surface at once.
//
// Two ordering rules, and they are deliberately different:
//   - DAYS come back newest first, because "did I take it today" is the
//     question being asked most of the time.
//   - DOSES INSIDE a day come back earliest first, because a day's doses read
//     as a sequence — 8am, 2pm, 9pm — the way a medication chart is written.
//
// `calendar` is injectable on every entry point for deterministic tests (see
// CLAUDE.md CI rules) — never `Dates.dayKey`, which is pinned to
// TimeZone.current and would make tests depend on the machine running them.

import Foundation

/// One logged dose, joined to the medication it belongs to. Carries the
/// medication's name and set time so a history row can be rendered without a
/// second lookup, and keeps `dosageTaken` distinct from `recommendedDosage` —
/// the whole point of the event-level field (see `ReminderEventDTO`).
public struct MedicationLogEntry: Equatable, Sendable, Identifiable {
    /// The underlying event's id, so deleting from a history row addresses the
    /// same row the rest of the app does.
    public var id: UUID
    public var reminderId: UUID
    public var medicationName: String
    public var timestamp: Date
    public var dosageTaken: String?
    public var recommendedDosage: String?
    public var scheduledMinutesOfDay: [Int]

    public init(id: UUID, reminderId: UUID, medicationName: String, timestamp: Date,
                dosageTaken: String? = nil, recommendedDosage: String? = nil,
                scheduledMinutesOfDay: [Int] = []) {
        self.id = id
        self.reminderId = reminderId
        self.medicationName = medicationName
        self.timestamp = timestamp
        self.dosageTaken = dosageTaken
        self.recommendedDosage = recommendedDosage
        self.scheduledMinutesOfDay = scheduledMinutesOfDay
    }
}

/// One local calendar day's doses, earliest first.
public struct MedicationLogDay: Equatable, Sendable, Identifiable {
    /// Start of the local day — also the sort key.
    public var id: Date
    public var entries: [MedicationLogEntry]

    public init(id: Date, entries: [MedicationLogEntry]) {
        self.id = id
        self.entries = entries
    }

    public var doseCount: Int { entries.count }

    /// How many DIFFERENT medications were logged that day — distinct from
    /// `doseCount`, which counts every dose including repeats of the same one.
    public var medicationCount: Int {
        Set(entries.map(\.reminderId)).count
    }
}

public enum MedicationHistory {

    // MARK: - Joining

    /// Joins raw events to the medications they belong to.
    ///
    /// `medications` is the medication group's reminders — anything else is
    /// simply absent from the lookup, so plant waterings and custom-reminder
    /// completions drop out here rather than needing a filter at every call
    /// site. An event whose reminder has been deleted drops out for the same
    /// reason (though `Repos.deleteReminder` cascades, so that should not
    /// normally happen).
    public static func entries(events: [ReminderEventDTO],
                               medications: [ReminderDTO]) -> [MedicationLogEntry] {
        let byId = Dictionary(medications.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return events.compactMap { e -> MedicationLogEntry? in
            guard let med = byId[e.reminderId] else { return nil }
            return MedicationLogEntry(
                id: e.id,
                reminderId: e.reminderId,
                medicationName: med.name,
                timestamp: e.timestamp,
                dosageTaken: e.dosageTaken,
                recommendedDosage: med.dosage,
                scheduledMinutesOfDay: med.scheduledMinutesOfDay
            )
        }
    }

    // MARK: - Grouping

    /// Groups into local calendar days: newest day first, doses inside a day
    /// earliest first. Input order does not matter — both levels are sorted
    /// here, so a caller can hand over a newest-first fetch or an arbitrary
    /// merge of several and get the same answer.
    public static func byDay(_ entries: [MedicationLogEntry], calendar: Calendar) -> [MedicationLogDay] {
        var byDay: [Date: [MedicationLogEntry]] = [:]
        for e in entries {
            byDay[calendar.startOfDay(for: e.timestamp), default: []].append(e)
        }
        return byDay
            .map { MedicationLogDay(id: $0.key, entries: $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.id > $1.id }
    }

    /// The same grouping for a single medication — the per-medication history
    /// on the detail sheet, so both surfaces order identically.
    public static func byDay(_ entries: [MedicationLogEntry], reminderId: UUID,
                             calendar: Calendar) -> [MedicationLogDay] {
        byDay(entries.filter { $0.reminderId == reminderId }, calendar: calendar)
    }

    // MARK: - Reading a dose against its set time

    /// Signed minutes between when a dose was logged and the set time it reads
    /// against; nil when that medication has no set times. See
    /// `MedicationPattern.minutesFromNearest` for the nearest-time and
    /// wrap-around rules.
    public static func minutesFromScheduled(_ entry: MedicationLogEntry,
                                            calendar: Calendar) -> Int? {
        MedicationPattern.minutesFromNearest(
            logged: entry.timestamp, times: entry.scheduledMinutesOfDay, calendar: calendar
        )
    }

    /// "12 min after 8:00 AM" for one history row, read against whichever set
    /// time is closest; nil when the medication has no set times, which means
    /// the row renders the logged time alone.
    public static func timingLabel(_ entry: MedicationLogEntry, calendar: Calendar) -> String? {
        MedicationPattern.timingLabel(
            loggedAt: entry.timestamp, times: entry.scheduledMinutesOfDay, calendar: calendar
        )
    }

    // MARK: - Day headings

    /// "Today" / "Yesterday" / a weekday name inside the last week / an
    /// abbreviated date beyond it. The question a history scan answers is
    /// "which day", and for the recent past a weekday name carries that faster
    /// than a date does.
    ///
    /// Lives here rather than in a view so the per-medication history and the
    /// all-medications history can never label the same day differently.
    public static func dayTitle(_ day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        let today = calendar.startOfDay(for: now)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
        let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: today).day ?? 0
        if daysAgo > 0 && daysAgo < 7 { return day.formatted(.dateTime.weekday(.wide)) }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Totals

    /// Doses logged, and how many distinct days carry at least one — the two
    /// numbers a history header states. Counted off the grouped days so it can
    /// never disagree with the list underneath it.
    public static func totals(_ days: [MedicationLogDay]) -> (doses: Int, days: Int) {
        (days.reduce(0) { $0 + $1.doseCount }, days.count)
    }
}
