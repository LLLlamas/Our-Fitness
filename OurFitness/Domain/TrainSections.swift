// Optional Train-tab sections (Pilates, Yoga, Stretching).
//
// Each section is one weekly-goal card (`ActivitySectionCard`) the user adds or
// removes on the Train tab. Which ones are shown is stored per profile as a CSV
// of section ids under `storageKey(profileId:)`:
//   - "" (never set)  → the sections the user already has logged sessions for,
//                       so an existing Pilates user keeps the Pilates card and a
//                       new profile starts with none
//   - "none"          → explicitly emptied (same sentinel as `progressStats.*`)
//   - "pilates,yoga"  → exactly those
// Removing a section only hides the card; logged sessions are never touched.
//
// Pure Domain: no SwiftUI/SwiftData. Not in the watch source list.

import Foundation

public enum TrainSection: String, CaseIterable, Identifiable, Sendable {
    // Declaration order IS the render order on the Train tab. Raw values are
    // persisted in the CSV — never rename one.
    case pilates
    case yoga
    case stretching

    public var id: String { rawValue }

    /// The catalog activity this section logs. Pilates sessions are stored as
    /// `PilatesSessionDTO`; the others as `ActivitySessionDTO` with this id.
    public var activityId: String {
        switch self {
        case .pilates:    return ActivityCatalog.pilatesId
        case .yoga:       return ActivityCatalog.yogaId
        case .stretching: return ActivityCatalog.stretchingId
        }
    }

    /// Display name and SF Symbol come from the catalog so the section, the
    /// activity picker and the session list never disagree.
    public var title: String {
        ActivityCatalog.activity(id: activityId)?.name ?? rawValue.capitalized
    }

    public var symbol: String {
        ActivityCatalog.activity(id: activityId)?.symbol ?? "figure.mixed.cardio"
    }

    /// Sessions per week a new goal starts at (the long-standing Pilates default).
    public var defaultWeeklyGoal: Int { 3 }

    /// Per-profile weekly-goal key. Pilates keeps the key it shipped with so
    /// existing users keep the goal they set.
    public func goalKey(profileId: UUID) -> String {
        "\(rawValue)WeeklyGoal.\(profileId.uuidString)"
    }

    /// One-line hint under the "Log <title>" button.
    public var logHint: String {
        switch self {
        case .pilates:    return "Duration + focus areas. Takes 10 seconds."
        case .yoga, .stretching: return "Duration + day. Takes 10 seconds."
        }
    }
}

public enum TrainSections {

    /// Stored value meaning "the user removed every section".
    public static let noneSentinel = "none"

    public static func storageKey(profileId: UUID) -> String {
        "trainSections.\(profileId.uuidString)"
    }

    /// The sections to render, in `TrainSection` order. `withData` is only
    /// consulted while nothing has been stored yet.
    public static func enabled(raw: String, withData: Set<TrainSection>) -> [TrainSection] {
        let chosen: Set<TrainSection>
        if raw.isEmpty {
            chosen = withData
        } else if raw == noneSentinel {
            chosen = []
        } else {
            chosen = Set(raw.split(separator: ",").compactMap {
                TrainSection(rawValue: $0.trimmingCharacters(in: .whitespaces))
            })
        }
        return TrainSection.allCases.filter { chosen.contains($0) }
    }

    /// Sections not yet on the tab, in `TrainSection` order.
    public static func available(enabled: [TrainSection]) -> [TrainSection] {
        TrainSection.allCases.filter { !enabled.contains($0) }
    }

    /// CSV to store. Never returns "" — that would read back as "never set" and
    /// bring data-backed sections back after the user removed them.
    public static func encode(_ sections: [TrainSection]) -> String {
        let set = Set(sections)
        let ordered = TrainSection.allCases.filter { set.contains($0) }
        return ordered.isEmpty ? noneSentinel : ordered.map(\.rawValue).joined(separator: ",")
    }

    // MARK: - Weekly progress

    /// Sessions whose date falls in the ISO (Monday) week containing `now`.
    public static func countThisWeek(
        _ dates: [Date],
        now: Date = Date(),
        calendar: Calendar = Dates.isoCalendar
    ) -> Int {
        var cal = calendar
        cal.firstWeekday = 2
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return dates.filter { week.contains($0) }.count
    }

    /// Consecutive weeks at or above `goalSessions`, with the current week as a
    /// grace zone. Delegates to `Movement.pilatesWeeklyStreak` so every section
    /// shares one streak rule; only session dates matter to it.
    public static func weeklyStreak(
        _ dates: [Date],
        goalSessions: Int,
        now: Date = Date(),
        calendar: Calendar = Dates.isoCalendar
    ) -> Int {
        let placeholder = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let sessions = dates.map {
            PilatesSessionDTO(profileId: placeholder, date: $0, durationMinutes: 0, focusAreas: [])
        }
        return Movement.pilatesWeeklyStreak(sessions: sessions, goalSessions: goalSessions,
                                            now: now, calendar: calendar)
    }
}
