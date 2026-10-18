// Reps at a weight, over an exercise's whole history (pure Swift).
//
// Progress is "how many reps, at what weight" — set structure is ignored. The
// append-only `WorkoutSetDTO` rows for one exercise are folded per day and per
// Monday ISO week into reps PER EXACT WEIGHT (50 lb and 52.5 lb are different
// weights; nil = no weight / bodyweight). Everything here is derived on read, so
// editing or back-filling a row changes every comparison automatically.
//
// Shape-aware via `ExerciseDTO`, never goal-aware:
//   • rep exercise      → amount = reps
//   • `.duration` kind  → amount = minutes (the row's `reps` field holds minutes)
//   • isometric hold    → amount = seconds held (`holdSeconds`); the longest single
//                         hold is tracked alongside the total
// A fixed-load exercise (`loadLb`, e.g. Lifted Baby) reads a row with a nil
// `weightLb` as the exercise's current load (legacy rows from before the load was
// stamped); a stamped `weightLb` always wins.
//
// Phone-only: deliberately NOT in the watch source list (hard rule 7).
// Rule: Foundation only — never SwiftData or SwiftUI.

import Foundation

public enum RepHistory {

    // MARK: - Vocabulary

    /// What an exercise's amount is counted in.
    public enum Measure: Equatable, Sendable {
        case reps
        case minutes
        case holdSeconds
    }

    public static func measure(for exercise: ExerciseDTO) -> Measure {
        if exercise.isIsometric { return .holdSeconds }
        return exercise.kind == .duration ? .minutes : .reps
    }

    /// A rep exercise in the weekly-reps sense: counted in reps, not a hold.
    /// Holds and duration exercises are excluded from weekly rep totals.
    public static func isRepExercise(_ exercise: ExerciseDTO) -> Bool {
        exercise.kind == .reps && !exercise.isIsometric
    }

    /// A weight rounded to 0.01 lb. Weights match EXACTLY, but "exact" has to
    /// survive a unit round trip: 22.68 kg is 50.000841 lb and 50 lb back to kg is
    /// 49.9999999989, which would otherwise split one displayed weight into two
    /// lines. 0.01 lb is far below any plate, so 50 and 52.5 stay distinct.
    public static func canonicalLb(_ lb: Double) -> Double {
        guard lb.isFinite else { return lb }
        return (lb * 100).rounded() / 100
    }

    /// Exact-weight key. `lb == nil` means "no weight" (bodyweight). A zero or
    /// negative weight is also "no weight". The weight is held at `canonicalLb`
    /// precision, so every grouping and comparison goes through the one rounding.
    public struct WeightKey: Hashable, Comparable, Sendable {
        public let lb: Double?
        public init(_ lb: Double?) {
            if let lb, lb.isFinite, RepHistory.canonicalLb(lb) > 0 {
                self.lb = RepHistory.canonicalLb(lb)
            } else {
                self.lb = nil
            }
        }
        public static let bodyweight = WeightKey(nil)

        /// Bodyweight first, then ascending by weight.
        public static func < (a: WeightKey, b: WeightKey) -> Bool {
            switch (a.lb, b.lb) {
            case (nil, nil): return false
            case (nil, _): return true
            case (_, nil): return false
            case let (x?, y?): return x < y
            }
        }
    }

    /// The amount (reps, minutes or hold seconds) done at one weight.
    public struct WeightLine: Equatable, Sendable, Identifiable {
        public let weight: WeightKey
        public let amount: Int
        public var id: Double { weight.lb ?? -1 }
    }

    /// One day's (or one ISO week's) work on one exercise, folded per weight.
    /// `DayTally` / `WeekTally` are the same type; `key` is the day's `Dates.dayKey`
    /// or the week's Monday as a dayKey.
    public struct Tally: Equatable, Sendable, Identifiable {
        public let key: String
        public let measure: Measure
        /// Bodyweight first, then ascending by weight.
        public let lines: [WeightLine]
        /// Sum of every line (reps, minutes or hold seconds).
        public let totalAmount: Int
        /// Longest single hold in seconds; non-nil only for holds.
        public let longestHoldSeconds: Int?
        /// Underlying `WorkoutSetDTO` rows (informational — progress ignores sets).
        public let rowCount: Int
        /// Distinct calendar days with a row (1 for a day tally).
        public let daysTrained: Int
        public var id: String { key }

        public func amount(at weight: WeightKey) -> Int? {
            lines.first { $0.weight == weight }?.amount
        }

        /// The heaviest weight in the tally, nil when nothing was weighted.
        public var heaviestWeightLb: Double? { lines.compactMap(\.weight.lb).max() }

        /// The line at the heaviest weight (else the only/bodyweight line).
        public var topLine: WeightLine? { lines.last }
    }

    public typealias DayTally = Tally
    public typealias WeekTally = Tally

    // MARK: - Folding

    /// The weight a row counts at: its stamped weight, else the exercise's fixed
    /// load, else none.
    public static func weightKey(of row: WorkoutSetDTO, exercise: ExerciseDTO) -> WeightKey {
        if let w = row.weightLb, w > 0 { return WeightKey(w) }
        return WeightKey(exercise.loadLb)
    }

    private static func amount(of row: WorkoutSetDTO, measure: Measure) -> Int {
        switch measure {
        case .reps, .minutes: return max(0, row.reps)
        case .holdSeconds: return max(0, row.holdSeconds ?? 0)
        }
    }

    private struct Entry {
        let row: WorkoutSetDTO
        let dayKey: String
    }

    private static func entries(_ rows: [WorkoutSetDTO], exercise: ExerciseDTO) -> [Entry] {
        rows.compactMap { $0.exerciseId == exercise.id ? Entry(row: $0, dayKey: Dates.dayKey($0.timestamp)) : nil }
    }

    private static func tally(key: String, entries: [Entry], exercise: ExerciseDTO) -> Tally {
        let measure = measure(for: exercise)
        var byWeight: [WeightKey: Int] = [:]
        var longest: Int?
        for e in entries {
            byWeight[weightKey(of: e.row, exercise: exercise), default: 0] += amount(of: e.row, measure: measure)
            if measure == .holdSeconds, let h = e.row.holdSeconds, h > 0 {
                longest = max(longest ?? 0, h)
            }
        }
        let lines = byWeight
            .map { WeightLine(weight: $0.key, amount: $0.value) }
            .sorted { $0.weight < $1.weight }
        return Tally(
            key: key, measure: measure, lines: lines,
            totalAmount: lines.reduce(0) { $0 + $1.amount },
            longestHoldSeconds: longest,
            rowCount: entries.count,
            daysTrained: Set(entries.map(\.dayKey)).count
        )
    }

    /// One day's tally from rows already known to belong to that day (rows for
    /// other exercises are ignored). For callers that group rows themselves.
    public static func dayTally(for exercise: ExerciseDTO, rows: [WorkoutSetDTO], dayKey: String) -> DayTally {
        tally(key: dayKey, entries: entries(rows, exercise: exercise), exercise: exercise)
    }

    /// Every day this exercise was trained, newest first. Rows for other
    /// exercises in `rows` are ignored.
    public static func days(for exercise: ExerciseDTO, rows: [WorkoutSetDTO]) -> [DayTally] {
        let grouped = Dictionary(grouping: entries(rows, exercise: exercise), by: \.dayKey)
        return grouped
            .map { tally(key: $0.key, entries: $0.value, exercise: exercise) }
            .sorted { $0.key > $1.key }
    }

    /// Every Monday ISO week this exercise was trained, newest first; `key` is
    /// the week's Monday as a dayKey.
    public static func weeks(for exercise: ExerciseDTO, rows: [WorkoutSetDTO]) -> [WeekTally] {
        let grouped = Dictionary(grouping: entries(rows, exercise: exercise)) {
            Dates.dayKey(Dates.startOfISOWeek($0.row.timestamp))
        }
        return grouped
            .map { tally(key: $0.key, entries: $0.value, exercise: exercise) }
            .sorted { $0.key > $1.key }
    }

    /// The weight most recently used with a weight on this exercise (newest row
    /// that resolves to a weight), for pre-filling the weight field. Nil when it
    /// has never been weighted.
    public static func lastWeightLb(for exercise: ExerciseDTO, rows: [WorkoutSetDTO]) -> Double? {
        rows
            .filter { $0.exerciseId == exercise.id }
            .sorted { $0.timestamp > $1.timestamp }
            .lazy
            .compactMap { weightKey(of: $0, exercise: exercise).lb }
            .first
    }

    // MARK: - Reference days ("last time", "same day last week")

    /// The most recent day trained strictly before `dayKey`. `days` as returned
    /// by `days(for:rows:)` (any order is fine).
    public static func lastTime(before dayKey: String, days: [DayTally]) -> DayTally? {
        days.filter { $0.key < dayKey }.max { $0.key < $1.key }
    }

    /// The most recent day before `dayKey` that included `weight`.
    public static func lastTime(at weight: WeightKey, before dayKey: String, days: [DayTally]) -> DayTally? {
        days.filter { $0.key < dayKey && $0.amount(at: weight) != nil }.max { $0.key < $1.key }
    }

    public struct Reference: Equatable, Sendable {
        public let tally: DayTally
        /// True when the exercise was done on the same weekday 7 days earlier;
        /// false when this is the nearest trained day inside that ISO week.
        public let isSameWeekday: Bool
    }

    /// Same weekday one week earlier; if the exercise wasn't done that day, the
    /// nearest trained day inside that same ISO week (a tie goes to the earlier
    /// day); else nil ("not logged").
    public static func sameDayLastWeek(for dayKey: String, days: [DayTally]) -> Reference? {
        guard let date = Dates.date(fromDayKey: dayKey),
              let target = Dates.isoCalendar.date(byAdding: .day, value: -7, to: date) else { return nil }
        let targetKey = Dates.dayKey(target)
        if let exact = days.first(where: { $0.key == targetKey }) {
            return Reference(tally: exact, isSameWeekday: true)
        }
        let weekKey = Dates.dayKey(Dates.startOfISOWeek(target))
        let nearest = days
            .filter { d in
                guard let dd = Dates.date(fromDayKey: d.key) else { return false }
                return Dates.dayKey(Dates.startOfISOWeek(dd)) == weekKey
            }
            .min { a, b in
                let da = abs(Dates.daysBetween(targetKey, a.key))
                let db = abs(Dates.daysBetween(targetKey, b.key))
                return da != db ? da < db : a.key < b.key
            }
        return nearest.map { Reference(tally: $0, isSameWeekday: false) }
    }

    // MARK: - Comparison

    public enum Outcome: Equatable, Sendable {
        /// More than the reference (positive count).
        case more(Int)
        /// Fewer than the reference (positive count of the shortfall).
        case fewer(Int)
        case same
        /// Done now at a weight the reference didn't include.
        case newWeight
        /// Done in the reference at this weight, not now.
        case notDone
    }

    public struct WeightComparison: Equatable, Sendable, Identifiable {
        public let weight: WeightKey
        /// Amount in `a` (nil = weight not done).
        public let current: Int?
        /// Amount in `b` (nil = weight not done).
        public let reference: Int?
        public let outcome: Outcome
        public var id: Double { weight.lb ?? -1 }
    }

    public struct Comparison: Equatable, Sendable {
        /// Union of both tallies' weights, bodyweight first then ascending.
        public let weights: [WeightComparison]
        public let currentTotal: Int
        public let referenceTotal: Int
        public var totalDelta: Int { currentTotal - referenceTotal }
        /// Longest-hold change in seconds; nil unless both tallies are holds.
        public let longestHoldDelta: Int?
    }

    public static func outcome(current: Int?, reference: Int?) -> Outcome? {
        switch (current, reference) {
        case (nil, nil): return nil
        case (_?, nil): return .newWeight
        case (nil, _?): return .notDone
        case let (c?, r?): return c > r ? .more(c - r) : (c < r ? .fewer(r - c) : .same)
        }
    }

    /// Per-weight deltas of `a` against the reference `b`, in both directions.
    public static func compare(_ a: Tally, to b: Tally) -> Comparison {
        let keys = Set(a.lines.map(\.weight)).union(b.lines.map(\.weight)).sorted()
        let rows = keys.compactMap { k -> WeightComparison? in
            let c = a.amount(at: k), r = b.amount(at: k)
            guard let o = outcome(current: c, reference: r) else { return nil }
            return WeightComparison(weight: k, current: c, reference: r, outcome: o)
        }
        var holdDelta: Int?
        if let la = a.longestHoldSeconds, let lb = b.longestHoldSeconds { holdDelta = la - lb }
        return Comparison(weights: rows, currentTotal: a.totalAmount,
                          referenceTotal: b.totalAmount, longestHoldDelta: holdDelta)
    }

    /// "+4 vs Tue", "4 fewer than Tue", "same as Tue", "new weight". Nil for
    /// `.notDone` (the row shows the reference figure instead). `reference` is the
    /// caller's label for the other side ("last time", "Tue", "Oct 8").
    public static func deltaText(_ outcome: Outcome, reference: String) -> String? {
        switch outcome {
        case .more(let n): return "+\(n) vs \(reference)"
        case .fewer(let n): return "\(n) fewer than \(reference)"
        case .same: return "same as \(reference)"
        case .newWeight: return "new weight"
        case .notDone: return nil
        }
    }

    /// Live running-tally wording while logging: the shortfall reads as a target,
    /// "12 to match last time", and flips to "+2 vs last week" once passed.
    public static func liveDeltaText(_ outcome: Outcome, reference: String) -> String? {
        switch outcome {
        case .fewer(let n): return "\(n) to match \(reference)"
        case .same: return "matches \(reference)"
        default: return deltaText(outcome, reference: reference)
        }
    }

    // MARK: - Bests

    /// Rows needed on EARLIER days before any "new best" is announced; the first
    /// days are the baseline.
    public static let minHistoryDaysForBest = 2

    public struct WeightBest: Equatable, Sendable, Identifiable {
        public let weight: WeightKey
        public let amount: Int
        public let dayKey: String
        public var id: Double { weight.lb ?? -1 }
    }

    public struct DayBest: Equatable, Sendable {
        public let amount: Int
        public let dayKey: String
    }

    public struct WeightMark: Equatable, Sendable {
        public let lb: Double
        public let dayKey: String
    }

    /// All-time bests derived from day tallies. Ties keep the EARLIEST day.
    public struct Bests: Equatable, Sendable {
        /// Most reps (or minutes / hold seconds) in one day at each weight.
        public let byWeight: [WeightBest]
        /// Heaviest weight ever used.
        public let heaviest: WeightMark?
        /// Longest single hold (holds only).
        public let longestHold: DayBest?
        /// Biggest day total across weights (most reps / minutes / hold seconds in a day).
        public let bestDay: DayBest?
        public let dayCount: Int

        public func best(at weight: WeightKey) -> WeightBest? {
            byWeight.first { $0.weight == weight }
        }
    }

    public static func bests(from days: [DayTally]) -> Bests {
        var perWeight: [WeightKey: WeightBest] = [:]
        var heaviest: WeightMark?
        var longest: DayBest?
        var bestDay: DayBest?
        for d in days.sorted(by: { $0.key < $1.key }) {
            for l in d.lines {
                if l.amount > (perWeight[l.weight]?.amount ?? 0) {
                    perWeight[l.weight] = WeightBest(weight: l.weight, amount: l.amount, dayKey: d.key)
                }
                if let lb = l.weight.lb, lb > (heaviest?.lb ?? 0) {
                    heaviest = WeightMark(lb: lb, dayKey: d.key)
                }
            }
            if let h = d.longestHoldSeconds, h > (longest?.amount ?? 0) {
                longest = DayBest(amount: h, dayKey: d.key)
            }
            if d.totalAmount > (bestDay?.amount ?? 0) {
                bestDay = DayBest(amount: d.totalAmount, dayKey: d.key)
            }
        }
        return Bests(byWeight: perWeight.values.sorted { $0.weight < $1.weight },
                     heaviest: heaviest, longestHold: longest, bestDay: bestDay, dayCount: days.count)
    }

    public enum NewBest: Equatable, Sendable {
        /// The day's reps (or minutes) at this exact weight passed the best day at it.
        case atWeight(measure: Measure, weight: WeightKey, amount: Int, previousBest: Int, previousDayKey: String)
        /// A heavier weight than ever used.
        case heaviest(weightLb: Double, previousLb: Double, previousDayKey: String)
        /// A single hold longer than any before.
        case longestHold(seconds: Int, previousSeconds: Int, previousDayKey: String)
    }

    /// Does the just-logged `row` make a NEW best? Compared against history
    /// EXCLUDING `row` (so `rows` may or may not already contain it).
    ///
    /// Guards: nil until at least `minHistoryDaysForBest` EARLIER days exist; nil
    /// for a back-filled row (any history on a later day); per-weight, so going
    /// heavier for fewer reps is never "worse"; "heaviest yet" is a separate case
    /// and needs an earlier weighted day. Fires only on the row that crosses the
    /// line, so a run of +1 taps toasts once. Callers still skip edits, watch logs
    /// and back-fills (rule: those never toast).
    public static func newBest(
        after row: WorkoutSetDTO, exercise: ExerciseDTO, rows: [WorkoutSetDTO]
    ) -> NewBest? {
        guard row.exerciseId == exercise.id else { return nil }
        let history = rows.filter { $0.exerciseId == exercise.id && $0.id != row.id }
        let rowDay = Dates.dayKey(row.timestamp)
        let all = days(for: exercise, rows: history)
        guard !all.contains(where: { $0.key > rowDay }) else { return nil }
        let earlier = all.filter { $0.key < rowDay }
        guard earlier.count >= minHistoryDaysForBest else { return nil }
        let today = all.first { $0.key == rowDay }
        let past = bests(from: earlier)
        let measure = measure(for: exercise)

        if measure == .holdSeconds {
            let secs = row.holdSeconds ?? 0
            guard secs > 0, let prev = past.longestHold, secs > prev.amount,
                  secs > (today?.longestHoldSeconds ?? 0) else { return nil }
            return .longestHold(seconds: secs, previousSeconds: prev.amount, previousDayKey: prev.dayKey)
        }

        let amt = amount(of: row, measure: measure)
        guard amt > 0 else { return nil }
        let w = weightKey(of: row, exercise: exercise)

        if let lb = w.lb, let prevHeavy = past.heaviest, lb > prevHeavy.lb {
            // Announced once: not if something at least this heavy already went in today.
            guard lb > (today?.heaviestWeightLb ?? 0) else { return nil }
            return .heaviest(weightLb: lb, previousLb: prevHeavy.lb, previousDayKey: prevHeavy.dayKey)
        }
        if let best = past.best(at: w) {
            let before = today?.amount(at: w) ?? 0
            if before <= best.amount, before + amt > best.amount {
                return .atWeight(measure: measure, weight: w, amount: before + amt,
                                 previousBest: best.amount, previousDayKey: best.dayKey)
            }
        }
        return nil
    }

    // MARK: - Weekly reps

    /// The single note shown with the weekly-reps tracker (and toasted once a week).
    public enum WeeklyNote: Equatable, Sendable {
        /// This week is at least 75% of last week's total but still below it.
        case approaching(remaining: Int)
        /// This week has passed last week's total by `by` reps.
        case passed(by: Int)
        /// Most reps in a week yet (needs 3+ earlier logged weeks).
        case bestWeek
        /// First logged week after a gap of a week or more; no comparison.
        case firstWeekBack
        case none
    }

    public struct ExerciseReps: Equatable, Sendable, Identifiable {
        public let exerciseId: String
        public let name: String
        public let reps: Int
        public var id: String { exerciseId }
    }

    public struct WeeklyReps: Equatable, Sendable {
        public let thisWeek: Int
        public let lastWeek: Int
        public var delta: Int { thisWeek - lastWeek }
        public let note: WeeklyNote
        /// This week's reps per rep exercise, most reps first (name breaks ties).
        public let byExercise: [ExerciseReps]
    }

    /// Earlier logged weeks required before "most reps in a week yet" can show.
    public static let minWeeksForBestWeek = 3

    /// Reps per Monday ISO week (key = Monday's dayKey) across REP exercises only
    /// — holds, duration and unknown exercises are excluded.
    public static func weeklyRepTotals(sets: [WorkoutSetDTO], exercises: [ExerciseDTO]) -> [String: Int] {
        let repIds = Set(exercises.filter(isRepExercise).map(\.id))
        var totals: [String: Int] = [:]
        for s in sets where repIds.contains(s.exerciseId) && s.reps > 0 {
            totals[Dates.dayKey(Dates.startOfISOWeek(s.timestamp)), default: 0] += s.reps
        }
        return totals
    }

    public static func weeklyReps(
        sets: [WorkoutSetDTO], exercises: [ExerciseDTO], now: Date
    ) -> WeeklyReps {
        let totals = weeklyRepTotals(sets: sets, exercises: exercises)
        let thisKey = Dates.dayKey(Dates.startOfISOWeek(now))
        let lastKey = Dates.dayKey(Dates.startOfISOWeek(now, weeksAgo: 1))
        let this = totals[thisKey] ?? 0
        let last = totals[lastKey] ?? 0
        let earlier = totals.filter { $0.key < thisKey && $0.value > 0 }.map(\.value)

        let note: WeeklyNote
        if this == 0 {
            note = .none
        } else if last == 0 {
            note = earlier.isEmpty ? .none : .firstWeekBack
        } else if earlier.count >= minWeeksForBestWeek, this > (earlier.max() ?? 0) {
            note = .bestWeek
        } else if this > last {
            note = .passed(by: this - last)
        } else if this < last, this * 4 >= last * 3 {
            note = .approaching(remaining: last - this)
        } else {
            note = .none
        }

        let repExercises = Dictionary(
            exercises.filter(isRepExercise).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var perExercise: [String: Int] = [:]
        for s in sets where s.reps > 0 && repExercises[s.exerciseId] != nil
            && Dates.dayKey(Dates.startOfISOWeek(s.timestamp)) == thisKey {
            perExercise[s.exerciseId, default: 0] += s.reps
        }
        let breakdown = perExercise
            .compactMap { id, reps -> ExerciseReps? in
                repExercises[id].map { ExerciseReps(exerciseId: id, name: $0.name, reps: reps) }
            }
            .sorted { $0.reps != $1.reps ? $0.reps > $1.reps
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return WeeklyReps(thisWeek: this, lastWeek: last, note: note, byExercise: breakdown)
    }

    /// One line for the tracker's note ("40 reps to match last week"); nil for `.none`.
    public static func noteText(_ note: WeeklyNote) -> String? {
        switch note {
        case .approaching(let n): return "\(n) \(n == 1 ? "rep" : "reps") to match last week"
        case .passed(let n): return "+\(n) \(n == 1 ? "rep" : "reps") vs last week"
        case .bestWeek: return "Most reps in a week yet"
        case .firstWeekBack: return "First week back"
        case .none: return nil
        }
    }

    /// Once-per-week gate for the weekly-reps toast. `stored` is the last value this
    /// returned ("<Monday dayKey>|kind,kind"); the result is the value to store
    /// when the current note has not been announced yet this ISO week, nil when
    /// there is nothing to say or it already went out. A new week starts clean.
    public static func weeklyNoteAnnouncement(_ weekly: WeeklyReps, now: Date, stored: String) -> String? {
        let kind: String
        switch weekly.note {
        case .approaching: kind = "approaching"
        case .passed: kind = "passed"
        case .bestWeek: kind = "best"
        case .firstWeekBack: kind = "back"
        case .none: return nil
        }
        let weekKey = Dates.dayKey(Dates.startOfISOWeek(now))
        let parts = stored.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        var kinds: [String] = []
        if parts.count == 2, String(parts[0]) == weekKey {
            kinds = parts[1].split(separator: ",").map(String.init)
        }
        guard !kinds.contains(kind) else { return nil }
        return "\(weekKey)|" + (kinds + [kind]).joined(separator: ",")
    }

    // MARK: - Formatting

    /// "50 s", "2 min", "2 min 10 s".
    public static func durationText(seconds: Int) -> String {
        let s = max(0, seconds)
        guard s >= 60 else { return "\(s) s" }
        let m = s / 60, r = s % 60
        return r == 0 ? "\(m) min" : "\(m) min \(r) s"
    }

    /// The ONE reps-at-weight line every list prints: "50 lb × 30 · 55 lb × 8".
    /// `formatWeight` returns the full weight text with its unit ("50 lb"), so the
    /// caller owns unit conversion. Unweighted: "42 reps" (alone) or
    /// "bodyweight × 12" (beside weighted lines); minutes read "30 lb × 12 min" /
    /// "12 min"; a hold reads "50 s" for one hold, else "longest 50 s · total 2 min 10 s".
    public static func summary(_ tally: Tally, formatWeight: (Double) -> String) -> String {
        guard !tally.lines.isEmpty else { return "" }
        switch tally.measure {
        case .holdSeconds:
            let total = durationText(seconds: tally.totalAmount)
            guard let longest = tally.longestHoldSeconds, tally.rowCount > 1,
                  longest != tally.totalAmount else { return total }
            return "longest \(durationText(seconds: longest)) · total \(total)"
        case .reps, .minutes:
            let unit = tally.measure == .minutes ? "min" : nil
            let allBodyweight = tally.lines.allSatisfy { $0.weight.lb == nil }
            return tally.lines.map { line -> String in
                guard let lb = line.weight.lb else {
                    if allBodyweight {
                        if let unit { return "\(line.amount) \(unit)" }
                        return "\(line.amount) \(line.amount == 1 ? "rep" : "reps")"
                    }
                    return "bodyweight × \(line.amount)" + (unit.map { " \($0)" } ?? "")
                }
                return "\(formatWeight(lb)) × \(line.amount)" + (unit.map { " \($0)" } ?? "")
            }
            .joined(separator: " · ")
        }
    }
}
