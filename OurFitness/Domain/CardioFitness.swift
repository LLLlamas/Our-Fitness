// Cardio fitness (VO₂ max) and cardio minutes: pure helpers for the two
// Progress trackers and the Health reads behind them. Plan:
// docs/cardio-fitness-plan.md §4 (steps 1–6), §7 Q5 b + Q7, §10.
//
// The estimate is read-only — Apple Watch writes it to Health, we only read it —
// so nothing here classifies, targets or rates the number (plan §1.3–1.4). The
// trend compares the user with their own earlier estimates only.
//
// Phone-only pure Domain (Foundation only). NOT in the watch's source list.
// `now` is injected everywhere; never read the wall clock here.

import Foundation

public enum CardioFitness {

    /// How far back the history read goes when no estimate is stored yet.
    public static let historyYears = 2

    /// The trend compares the latest estimate with the newest one at least
    /// this many days before it (8 weeks): the estimate moves slowly.
    public static let trendGapDays = 56

    /// A change of this much or less reads "about the same". Not a sourced
    /// figure: it is the plan's copy rule that a change of a point or two is
    /// noise for this estimate (plan §2, accuracy).
    public static let noiseBand = 2.0

    /// Range Apple Watch supports, in ml/kg/min. Apple Support 108790 ("Apple
    /// Watch supports a VO2 max range of 14-65 mL/kg/min"), opened 2026-11-20.
    public static let supportedRange: ClosedRange<Double> = 14...65

    // MARK: - Health history sync

    /// One VO₂ max sample from Health: its end date and value in ml/kg/min.
    public struct Reading: Equatable, Sendable {
        public let date: Date
        public let value: Double
        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Where every sync's VO₂ max read starts: the newest stored `vo2_max` day
    /// (inclusive — that day is deduped below), or `historyYears` back when none
    /// is stored. Deliberately no one-shot flag: a read made before the user
    /// re-ran Connect returns nothing (a denied read looks empty), so the next
    /// sync after they reconnect must still reach the whole history (plan §9.2).
    public static func historyStart(existing: [HealthMarkerDTO], now: Date,
                                    calendar: Calendar = .current) -> Date {
        if let newest = existing.lazy.filter({ $0.kind == .vo2Max }).map(\.date).max(),
           let day = Dates.date(fromDayKey: newest) {
            return day
        }
        return calendar.date(byAdding: .year, value: -historyYears, to: now) ?? now
    }

    /// The readings to store: one per day (the newest sample of that day),
    /// skipping any day that already holds a `vo2_max` marker. Ascending by day.
    /// `existing` is the profile's markers, fetched ONCE by the caller, so a
    /// two-year backfill isn't one fetch per sample (plan §9.6).
    public static func newDailyReadings(_ samples: [Reading],
                                        existing: [HealthMarkerDTO]) -> [Trends.Point] {
        let stored = Set(existing.lazy.filter { $0.kind == .vo2Max }.map(\.date))
        var newestByDay: [String: Reading] = [:]
        for sample in samples {
            let day = Dates.dayKey(sample.date)
            guard !stored.contains(day) else { continue }
            if let kept = newestByDay[day], kept.date >= sample.date { continue }
            newestByDay[day] = sample
        }
        return newestByDay
            .map { Trends.Point(date: $0.key, value: $0.value.value) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Trend (own history only)

    public enum Trend: Equatable, Sendable {
        /// No estimate 8+ weeks before the latest yet. One reading gets no verdict.
        case tooSoon
        case aboutTheSame(since: String)
        /// Rounded to 0.1, always positive.
        case up(Double, since: String)
        /// Rounded to 0.1, always positive. Shown plainly, never as a warning.
        case down(Double, since: String)
    }

    /// Latest estimate vs the newest estimate at least `trendGapDays` before it.
    /// `samples` are day-keyed points (any order); days after `now` are ignored.
    public static func vo2Trend(samples: [Trends.Point], now: Date) -> Trend {
        let today = Dates.dayKey(now)
        let past = samples.filter { $0.date <= today }.sorted { $0.date < $1.date }
        guard let latest = past.last,
              let baseline = past.last(where: { Dates.daysBetween($0.date, latest.date) >= trendGapDays })
        else { return .tooSoon }
        let delta = ((latest.value - baseline.value) * 10).rounded() / 10
        if abs(delta) <= noiseBand { return .aboutTheSame(since: baseline.date) }
        return delta > 0 ? .up(delta, since: baseline.date) : .down(-delta, since: baseline.date)
    }

    /// Short chip for the Progress card. nil until there is a comparison.
    public static func chipText(_ trend: Trend) -> String? {
        switch trend {
        case .tooSoon:                    return nil
        case .aboutTheSame(let since):    return "≈ same vs \(Dates.formatShort(since))"
        case .up(let d, let since):       return String(format: "+%.1f vs %@", d, Dates.formatShort(since))
        case .down(let d, let since):     return String(format: "−%.1f vs %@", d, Dates.formatShort(since))
        }
    }

    /// One plain sentence for the detail sheet, comparing with the user's own past.
    public static func noteText(_ trend: Trend) -> String {
        switch trend {
        case .tooSoon:
            return "One estimate says little on its own. Once there is one from 8 or more weeks earlier, this compares the two."
        case .aboutTheSame(let since):
            return "Your estimate is about the same as on \(Dates.formatShort(since))."
        case .up(let d, let since):
            return String(format: "Your estimate is %.1f higher than on %@.", d, Dates.formatShort(since))
        case .down(let d, let since):
            return String(format: "Your estimate is %.1f lower than on %@.", d, Dates.formatShort(since))
        }
    }

    /// "as of Nov 18". Date only: a marker's date is a day key, so there is no
    /// time to show (`Freshness.label` takes a `Date` and prints one; plan §9.5).
    public static func asOfLabel(dayKey: String) -> String {
        "as of " + Dates.formatShort(dayKey)
    }

    // MARK: - Tracker visibility (one-time migration)

    /// The stored Progress tracker CSV with `raw` added, everything else kept as
    /// is. Used once per profile (one flag per tracker) to put the VO₂ max and
    /// cardio-minutes trackers in front of people who had already customized
    /// their trackers (owner decisions, plan §10 and 2026-11-20).
    /// Empty = still on the defaults, which already include it; "none" (the
    /// "show nothing" sentinel) becomes just this tracker.
    public static func enabledTrackers(_ csv: String, adding raw: String) -> String {
        if csv.isEmpty { return csv }
        if csv == "none" { return raw }
        if csv.split(separator: ",").contains(where: { $0 == raw }) { return csv }
        return csv + "," + raw
    }

    // MARK: - Cardio minutes (plan §4 step 5, §7 Q5 b + Q7, §9 "Phase 2 must")

    /// Weeks the cardio-minutes tracker shows, and how far back each sync reads
    /// Health workouts (from the Monday `historyWeeks - 1` weeks before this one).
    public static let historyWeeks = 12

    /// Logged activities that count as cardio minutes. An explicit allow-list:
    /// an activity added to `ActivityCatalog` counts only once it is placed here
    /// or in `nonCardioActivityIds` (a test fails until it is). Ids that are in
    /// neither (an unknown or retired id) don't count.
    public static let cardioActivityIds: Set<String> = [
        "activity-basketball-game", "activity-basketball-shooting", "activity-soccer", "activity-tennis",
        "activity-running", "activity-cycling", "activity-swimming", "activity-rowing",
        "activity-jump-rope", "activity-hiking", ActivityCatalog.walkingId,
        "activity-ice-skating", "activity-inline-skating", "activity-dancing",
        // "Other" is the catalog's moderate-effort catch-all (figure.mixed.cardio).
        ActivityCatalog.otherId,
    ]

    /// Logged activities that are deliberately NOT cardio minutes: mobility and
    /// strength-endurance work. (Pilates is normally its own `PilatesSessionDTO`,
    /// which this tracker doesn't read at all.)
    public static let nonCardioActivityIds: Set<String> = [
        ActivityCatalog.pilatesId, ActivityCatalog.yogaId, ActivityCatalog.stretchingId,
    ]

    public static func countsAsCardio(activityId: String) -> Bool {
        cardioActivityIds.contains(activityId)
    }

    /// Legacy `CardioSessionDTO` rows (read-only, older installs) are all cardio
    /// by type. Exhaustive so a new type has to decide.
    public static func countsAsCardio(_ type: CardioType) -> Bool {
        switch type {
        case .walk, .run, .bike, .swim, .elliptical, .other: return true
        }
    }

    /// A Health workout's activity, reduced to what this tracker needs. The
    /// HealthKit service maps `HKWorkoutActivityType` onto it (Domain stays free
    /// of HealthKit); anything it doesn't map is `.other` and doesn't count.
    public enum WorkoutKind: String, CaseIterable, Sendable {
        // Cardio
        case walking, running, hiking, cycling, swimming, rowing, elliptical, stairs
        case jumpRope, dance, mixedCardio, intervals, skating, skiing, paddling
        case wheelchair, ballSports, multisport
        // Not cardio
        case yoga, pilates, flexibility, other

        public var countsAsCardio: Bool {
            switch self {
            case .walking, .running, .hiking, .cycling, .swimming, .rowing, .elliptical, .stairs,
                 .jumpRope, .dance, .mixedCardio, .intervals, .skating, .skiing, .paddling,
                 .wheelchair, .ballSports, .multisport:
                return true
            case .yoga, .pilates, .flexibility, .other:
                return false
            }
        }
    }

    /// One workout read from Health: wall-clock start/end, active duration
    /// (`HKWorkout.duration`, pauses excluded) and the bundle id of the app that
    /// saved it.
    public struct HealthWorkout: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let durationSeconds: Double
        public let kind: WorkoutKind
        public let sourceBundleId: String
        public init(start: Date, end: Date, durationSeconds: Double, kind: WorkoutKind, sourceBundleId: String) {
            self.start = start
            self.end = end
            self.durationSeconds = durationSeconds
            self.kind = kind
            self.sourceBundleId = sourceBundleId
        }
    }

    /// This app and its watch app. Workouts they saved to Health are already in
    /// the logs (the watch runner saves an `HKWorkout` and the phone logs the same
    /// session). Which of the two HealthKit stamps on a watch-saved workout is not
    /// verified (Apple's `HKSource.bundleIdentifier` docs only say "the app's
    /// bundle identifier"), so both are dropped and the service logs the one seen.
    public static let ownBundleIds: Set<String> = ["com.ourfitness.app", "com.ourfitness.app.watchkitapp"]

    /// Where every sync's Health workout read starts: Monday of the oldest week
    /// the tracker shows. Read in full each sync — no one-shot flag (plan §9.2).
    public static func healthWindowStart(now: Date) -> Date {
        Dates.startOfISOWeek(now, weeksAgo: historyWeeks - 1)
    }

    /// One counted stretch of cardio: when it started and its minutes.
    public struct Block: Equatable, Sendable {
        public let start: Date
        public let end: Date
        public let minutes: Int
        public let fromHealth: Bool
    }

    /// Logged sessions that count. A session's `date` is its start
    /// (`ActivitySessionDTO`), so it spans `date … date + minutes`. A session
    /// logged after the fact in `LogPastSessionSheet` carries the time it was
    /// logged instead, so the overlap rule can't match it; the ⓘ says not to
    /// re-log Apple Workout sessions.
    public static func loggedBlocks(activities: [ActivitySessionDTO], legacy: [CardioSessionDTO]) -> [Block] {
        let live = activities
            .filter { countsAsCardio(activityId: $0.activityId) && $0.durationMinutes > 0 }
            .map { Block(start: $0.date, end: $0.date.addingTimeInterval(Double($0.durationMinutes) * 60),
                         minutes: $0.durationMinutes, fromHealth: false) }
        let old = legacy
            .filter { countsAsCardio($0.type) && $0.durationMinutes > 0 }
            .map { Block(start: $0.date, end: $0.date.addingTimeInterval(Double($0.durationMinutes) * 60),
                         minutes: $0.durationMinutes, fromHealth: false) }
        return live + old
    }

    /// True when a logged block covers more than half of the workout's wall-clock
    /// length (plan §7 Q7): the same walk recorded twice.
    public static func overlapsLoggedSession(_ workout: HealthWorkout, logged: [Block]) -> Bool {
        let length = workout.end.timeIntervalSince(workout.start)
        guard length > 0 else { return false }
        return logged.contains { block in
            let overlap = min(workout.end, block.end).timeIntervalSince(max(workout.start, block.start))
            return overlap > length / 2
        }
    }

    /// Health workouts that count: a cardio kind, not saved by this app or its
    /// watch app, and not mostly overlapping a logged session. Minutes come from
    /// the active duration (wall-clock length if a source left it at 0).
    public static func healthBlocks(_ workouts: [HealthWorkout], logged: [Block]) -> [Block] {
        workouts.compactMap { w in
            guard w.kind.countsAsCardio,
                  !ownBundleIds.contains(w.sourceBundleId),
                  !overlapsLoggedSession(w, logged: logged) else { return nil }
            let seconds = w.durationSeconds > 0 ? w.durationSeconds : w.end.timeIntervalSince(w.start)
            let minutes = Int((seconds / 60).rounded())
            guard minutes > 0 else { return nil }
            return Block(start: w.start, end: w.end, minutes: minutes, fromHealth: true)
        }
    }

    /// The single own-history note under the number. No "best week": the app
    /// never pushes for more (plan §1).
    public enum MinutesNote: Equatable, Sendable {
        /// This week is at least 75% of last week but still below it.
        case approaching(remaining: Int)
        /// This week has passed last week by `by` minutes.
        case passed(by: Int)
        /// First week with minutes after a week or more without; no comparison.
        case firstWeekBack
        case none
    }

    public struct WeeklyMinutes: Equatable, Sendable {
        public let thisWeek: Int
        public let lastWeek: Int
        public var delta: Int { thisWeek - lastWeek }
        public let note: MinutesNote
        /// This week's split by where the minutes came from.
        public let loggedThisWeek: Int
        public let healthThisWeek: Int
        /// Minutes per ISO week (key = Monday's day key) for the last
        /// `historyWeeks` weeks, oldest first; weeks with nothing are absent.
        public let series: [Trends.Point]

        public static let empty = WeeklyMinutes(thisWeek: 0, lastWeek: 0, note: .none,
                                                loggedThisWeek: 0, healthThisWeek: 0, series: [])
    }

    /// Cardio minutes per Monday ISO week, each session in the week it STARTED.
    /// `health` should be the workouts read since `healthWindowStart(now:)`.
    public static func weeklyMinutes(activities: [ActivitySessionDTO], legacy: [CardioSessionDTO],
                                     health: [HealthWorkout], now: Date) -> WeeklyMinutes {
        let logged = loggedBlocks(activities: activities, legacy: legacy)
        let blocks = logged + healthBlocks(health, logged: logged)
        let thisKey = Dates.dayKey(Dates.startOfISOWeek(now))
        let lastKey = Dates.dayKey(Dates.startOfISOWeek(now, weeksAgo: 1))
        let cutoffKey = Dates.dayKey(healthWindowStart(now: now))

        var totals: [String: Int] = [:]
        var loggedThis = 0, healthThis = 0
        for b in blocks {
            let key = Dates.dayKey(Dates.startOfISOWeek(b.start))
            guard key <= thisKey else { continue }   // ignore anything dated after this week
            totals[key, default: 0] += b.minutes
            if key == thisKey {
                if b.fromHealth { healthThis += b.minutes } else { loggedThis += b.minutes }
            }
        }
        let this = totals[thisKey] ?? 0
        let last = totals[lastKey] ?? 0
        let hasEarlier = totals.contains { $0.key < thisKey && $0.value > 0 }

        let note: MinutesNote
        if this == 0 {
            note = .none
        } else if last == 0 {
            note = hasEarlier ? .firstWeekBack : .none
        } else if this > last {
            note = .passed(by: this - last)
        } else if this < last, this * 4 >= last * 3 {
            note = .approaching(remaining: last - this)
        } else {
            note = .none
        }

        let series = totals
            .filter { $0.key >= cutoffKey }
            .map { Trends.Point(date: $0.key, value: Double($0.value)) }
            .sorted { $0.date < $1.date }
        return WeeklyMinutes(thisWeek: this, lastWeek: last, note: note,
                             loggedThisWeek: loggedThis, healthThisWeek: healthThis, series: series)
    }

    /// "10 min to match last week" / "+8 vs last week" / "First week back"; nil for `.none`.
    public static func minutesNoteText(_ note: MinutesNote) -> String? {
        switch note {
        case .approaching(let n): return "\(n) min to match last week"
        case .passed(let n):      return "+\(n) vs last week"
        case .firstWeekBack:      return "First week back"
        case .none:               return nil
        }
    }
}
