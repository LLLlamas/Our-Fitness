// The per-exercise progress view — THE one place an exercise's whole history is
// read (docs/progress-tracking-plan.md §3.3). Hosted on `StatDetailSheet`, like
// every other tracker detail; the chart rides the `chartOverride` slot and the
// comparison / bests / day list ride the `footer` slot.
//
// Progress here is REPS AT A WEIGHT, never sets: `RepHistory` folds the
// exercise's append-only rows per day and per Monday ISO week into amounts per
// EXACT weight (50 lb and 52.5 lb are different weights). Holds read as seconds
// held, duration exercises as minutes. Nothing in this file does that math — it
// only lays out what `RepHistory` returns.
//
//   • chart      — amount per day (or week), one series per weight so the line
//                  steps when the weight changes; holds chart the longest hold.
//   • compare    — the latest day against "last time" and against "same day last
//                  week", or any day / week actually trained (a Menu that lists
//                  only logged days, like MealHistoryList). Decreases print
//                  plainly in the same neutral colour as increases: no red, no
//                  warning icon — a lower number is information, not failure.
//   • bests      — all-time, per weight, so going heavier for fewer reps is never
//                  a step back. Hidden until there are 2+ days of history.
//   • day list   — every day trained, newest first; a tap opens `SetHistorySheet`
//                  (the ONE set editor) on that day.
//
// Opened from the "Your progress" row in `ExerciseInfoSheet` and from the
// Strength card in Progress. Never write a second per-exercise history sheet.
//
// Performance: one predicate-scoped @Query for this exercise's full history,
// folded once per data change (`ExerciseHistoryMemo`), not once per body pass.
//
// No figure here is an estimate (everything is summed from logged rows). The
// estimated max stays on the Strength card, where it is labelled as one.

import SwiftUI
import SwiftData
import Charts

// MARK: - Shared fold + formatting (also used by ExerciseInfoSheet)

/// An exercise's full history folded by `RepHistory`, once.
struct ExerciseHistoryFold {
    /// Newest first.
    let days: [RepHistory.DayTally]
    /// Newest first (Monday ISO weeks).
    let weeks: [RepHistory.WeekTally]
    let bests: RepHistory.Bests

    static let empty = ExerciseHistoryFold(days: [], weeks: [], bests: RepHistory.bests(from: []))

    static func make(exercise: ExerciseDTO, rows: [WorkoutSetDTO]) -> ExerciseHistoryFold {
        let days = RepHistory.days(for: exercise, rows: rows)
        return ExerciseHistoryFold(
            days: days,
            weeks: RepHistory.weeks(for: exercise, rows: rows),
            bests: RepHistory.bests(from: days)
        )
    }

    /// A cheap fingerprint of everything the fold reads (O(n) over one exercise's
    /// rows, far cheaper than folding). It covers row count, ids and every field
    /// a fold depends on, so an EDIT to an old row invalidates it too — a count +
    /// newest-timestamp key would miss that.
    static func signature(models: [WorkoutSetModel], exercise: ExerciseDTO) -> Int {
        var h = Hasher()
        h.combine(exercise.id)
        h.combine(exercise.loadLb)
        h.combine(models.count)
        for m in models {
            h.combine(m.id)
            h.combine(m.reps)
            h.combine(m.weightLb)
            h.combine(m.holdSeconds)
            h.combine(m.timestamp)
        }
        return h.finalize()
    }
}

/// Holds the last fold. A reference type on purpose: it is read inside `body`
/// and refreshed there, and mutating a class property doesn't invalidate the
/// view the way `@State` writes during body would.
final class ExerciseHistoryMemo {
    private var lastSignature: Int?
    private var cached = ExerciseHistoryFold.empty

    func fold(for signature: Int, make: () -> ExerciseHistoryFold) -> ExerciseHistoryFold {
        if lastSignature != signature {
            cached = make()
            lastSignature = signature
        }
        return cached
    }
}

/// Weight / amount / day wording shared by the progress sheet and the info
/// sheet's "Your progress" row, so the two never print the same fact differently.
enum ProgressFormat {
    /// "50", "52.5" — no unit; whole numbers drop the decimal.
    static func weightNumber(_ lb: Double, system: UnitSystem) -> String {
        let v = Units.weightValue(lb: lb, system: system)
        let whole = abs(v - v.rounded()) < 0.05
        return Units.formatWeight(lb: lb, system: system, decimals: whole ? 0 : 1)
    }

    /// "50 lb" / "22.7 kg".
    static func weight(_ lb: Double, system: UnitSystem) -> String {
        "\(weightNumber(lb, system: system)) \(Units.weightUnit(system))"
    }

    static func weightLabel(_ key: RepHistory.WeightKey, system: UnitSystem) -> String {
        key.lb.map { weight($0, system: system) } ?? "Bodyweight"
    }

    /// "34 reps" / "12 min" / "50 s".
    static func amount(_ n: Int, measure: RepHistory.Measure) -> String {
        switch measure {
        case .reps: return "\(n) \(n == 1 ? "rep" : "reps")"
        case .minutes: return "\(n) min"
        case .holdSeconds: return RepHistory.durationText(seconds: n)
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// "Tue Oct 14".
    static func dayLabel(_ key: String) -> String {
        guard let d = Dates.date(fromDayKey: key) else { return key }
        return "\(weekdayFormatter.string(from: d)) \(Dates.formatShort(key))"
    }

    /// "Today" / "Yesterday" / "Tue Oct 14".
    static func relativeDayLabel(_ key: String, now: Date = Date()) -> String {
        if key == Dates.dayKey(now) { return "Today" }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        if key == Dates.dayKey(yesterday) { return "Yesterday" }
        return dayLabel(key)
    }

    /// Monday-of-the-week dayKey for any dayKey (the key `RepHistory.weeks` uses).
    static func weekKey(ofDay key: String) -> String {
        guard let d = Dates.date(fromDayKey: key) else { return key }
        return Dates.dayKey(Dates.startOfISOWeek(d))
    }
}

// MARK: - Sheet

private enum ProgressGranularity: Hashable {
    case day
    case week
}

/// Which reference the second comparison column uses.
private enum CompareChoice: Hashable {
    case sameDayLastWeek
    case day(String)
    case week(String)
}

private struct ProgressDayTarget: Identifiable {
    let dayKey: String
    var id: String { dayKey }
}

private struct ChartPoint: Identifiable {
    let id: String
    let date: Date
    let series: String
    let value: Double
}

/// One comparison column: the reference it reads against, and the tally on the
/// "now" side (the latest day, or that day's week-so-far for a week reference).
private struct CompareColumn {
    let title: String
    let subtitle: String
    let current: RepHistory.Tally
    /// Nil = nothing to compare with ("not logged").
    let reference: RepHistory.Tally?
    /// Short label inside the delta text: "+4 vs Oct 14".
    let refLabel: String
}

struct ExerciseProgressSheet: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO

    @Environment(\.theme) private var theme
    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    // Profile + exercise scoped at the query level — this exercise's whole history.
    @Query private var setModels: [WorkoutSetModel]

    @State private var memo = ExerciseHistoryMemo()
    @State private var granularity: ProgressGranularity = .day
    @State private var compareChoice: CompareChoice = .sameDayLastWeek
    @State private var dayTarget: ProgressDayTarget?
    /// How many days of the list are drawn; "Show older days" pages it.
    @State private var dayLimit = 30

    init(profile: ProfileDTO, exercise: ExerciseDTO) {
        self.profile = profile
        self.exercise = exercise
        let uid = profile.id
        let exId = exercise.id
        _setModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid && $0.exerciseId == exId },
            sort: \.timestamp, order: .reverse
        )
    }

    private var measure: RepHistory.Measure { RepHistory.measure(for: exercise) }

    private func weightText(_ lb: Double) -> String { ProgressFormat.weight(lb, system: unitSystem) }

    private func summaryText(_ tally: RepHistory.Tally) -> String {
        RepHistory.summary(tally, formatWeight: weightText)
    }

    private var unitLine: String {
        let per = granularity == .day ? "day" : "week"
        switch measure {
        case .reps: return "Reps per \(per), by weight"
        case .minutes: return "Minutes per \(per)"
        case .holdSeconds: return "Longest hold per \(per), seconds"
        }
    }

    var body: some View {
        let fold = memo.fold(for: ExerciseHistoryFold.signature(models: setModels, exercise: exercise)) {
            ExerciseHistoryFold.make(exercise: exercise, rows: setModels.map(\.snapshot))
        }
        let tallies = granularity == .day ? fold.days : fold.weeks
        let series = tallies.reversed().map {
            Trends.Point(date: $0.key, value: Double($0.totalAmount))
        }
        StatDetailSheet(
            title: exercise.name,
            unit: unitLine,
            series: series,
            canLog: false,
            showsEntries: false,
            minChartPoints: 2,
            emptyChartText: fold.days.isEmpty ? "Nothing logged yet." : "Not enough to chart yet.",
            emptyChartDetail: fold.days.isEmpty
                ? "Log it once and your history starts here."
                : (granularity == .day
                    ? "A chart appears once this is logged on two different days."
                    : "A chart appears once this is logged in two different weeks."),
            detents: [.large],
            headline: { headline(fold) },
            chartOverride: { chart(tallies) },
            footer: { footer(fold) }
        )
        .sheet(item: $dayTarget) { target in
            SetHistorySheet(profile: profile, exercise: exercise, dayKey: target.dayKey)
        }
    }

    // MARK: - Headline

    @ViewBuilder
    private func headline(_ fold: ExerciseHistoryFold) -> some View {
        if let latest = fold.days.first {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Latest · \(ProgressFormat.relativeDayLabel(latest.key))")
                    Text(summaryText(latest))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Picker("Chart by", selection: $granularity) {
                    Text("By day").tag(ProgressGranularity.day)
                    Text("By week").tag(ProgressGranularity.week)
                }
                .pickerStyle(.segmented)
                .onChange(of: granularity) { _, _ in Haptics.selection() }
            }
        }
    }

    // MARK: - Chart

    /// Oldest first. A hold charts its longest hold (one series); everything else
    /// gets one series per weight, so the line steps when the weight changes.
    private func chartPoints(_ tallies: [RepHistory.Tally]) -> [ChartPoint] {
        var out: [ChartPoint] = []
        for t in tallies.reversed() {
            guard let date = Dates.date(fromDayKey: t.key) else { continue }
            if t.measure == .holdSeconds {
                out.append(ChartPoint(id: "hold|\(t.key)", date: date, series: "Longest hold",
                                      value: Double(t.longestHoldSeconds ?? 0)))
            } else {
                // Two weights that print identically (52.04 / 52.0 lb) share a series.
                var order: [String] = []
                var sums: [String: Int] = [:]
                for l in t.lines {
                    let name = ProgressFormat.weightLabel(l.weight, system: unitSystem)
                    if sums[name] == nil { order.append(name) }
                    sums[name, default: 0] += l.amount
                }
                for name in order {
                    out.append(ChartPoint(id: "\(name)|\(t.key)", date: date, series: name,
                                          value: Double(sums[name] ?? 0)))
                }
            }
        }
        return out
    }

    /// Series names in weight order (bodyweight first) so colours stay stable.
    private func seriesNames(_ tallies: [RepHistory.Tally]) -> [String] {
        if measure == .holdSeconds { return ["Longest hold"] }
        let keys = Set(tallies.flatMap { $0.lines.map(\.weight) }).sorted()
        var seen = Set<String>()
        return keys.map { ProgressFormat.weightLabel($0, system: unitSystem) }.filter { seen.insert($0).inserted }
    }

    @ViewBuilder
    private func chart(_ tallies: [RepHistory.Tally]) -> some View {
        let points = chartPoints(tallies)
        let names = seriesNames(tallies)
        let palette = [theme.accent, theme.accent2, theme.ok, theme.dim]
        let colors = names.indices.map { palette[$0 % palette.count] }
        let top = max(1, points.map(\.value).max() ?? 1) * 1.15
        Chart(points) { p in
            LineMark(x: .value("Date", p.date), y: .value("Amount", p.value))
                .foregroundStyle(by: .value("Weight", p.series))
            PointMark(x: .value("Date", p.date), y: .value("Amount", p.value))
                .foregroundStyle(by: .value("Weight", p.series))
        }
        .chartForegroundStyleScale(domain: names, range: colors)
        .chartLegend(names.count > 1 ? .visible : .hidden)
        .chartYScale(domain: 0...top)
        .frame(height: 180)
        .accessibilityLabel("\(exercise.name) history chart")
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(_ fold: ExerciseHistoryFold) -> some View {
        if let latest = fold.days.first {
            VStack(alignment: .leading, spacing: 20) {
                comparisonCard(fold: fold, latest: latest)
                bestsCard(fold)
                daysList(fold)
                Text("Totals are summed per weight, so how you split them into sets doesn't matter. Day-to-day numbers move around; read the pattern, not one day.")
                    .font(.caption2).foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption).tracking(2).textCase(.uppercase)
            .foregroundStyle(theme.dim)
    }

    private func cardStyle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    // MARK: Comparison

    private func compareColumns(
        fold: ExerciseHistoryFold, latest: RepHistory.DayTally
    ) -> (a: CompareColumn, b: CompareColumn) {
        let lastTime = RepHistory.lastTime(before: latest.key, days: fold.days)
        let a = CompareColumn(
            title: "Last time",
            subtitle: lastTime.map { ProgressFormat.dayLabel($0.key) } ?? "no earlier day",
            current: latest,
            reference: lastTime,
            refLabel: lastTime.map { Dates.formatShort($0.key) } ?? ""
        )

        let b: CompareColumn
        switch compareChoice {
        case .day(let key) where key != latest.key && fold.days.contains(where: { $0.key == key }):
            let ref = fold.days.first { $0.key == key }
            b = CompareColumn(
                title: "That day", subtitle: ProgressFormat.dayLabel(key),
                current: latest, reference: ref, refLabel: Dates.formatShort(key))
        case .week(let key) where fold.weeks.contains(where: { $0.key == key })
            && key != ProgressFormat.weekKey(ofDay: latest.key):
            let ref = fold.weeks.first { $0.key == key }
            let now = fold.weeks.first { $0.key == ProgressFormat.weekKey(ofDay: latest.key) } ?? latest
            b = CompareColumn(
                title: "Week of \(Dates.formatShort(key))", subtitle: "vs this week so far",
                current: now, reference: ref, refLabel: "wk of \(Dates.formatShort(key))")
        default:
            let ref = RepHistory.sameDayLastWeek(for: latest.key, days: fold.days)
            let nearest = ref.map { !$0.isSameWeekday } ?? false
            b = CompareColumn(
                title: "Same day last week",
                subtitle: ref.map { ProgressFormat.dayLabel($0.tally.key) + (nearest ? " · nearest" : "") }
                    ?? "not logged",
                current: latest,
                reference: ref?.tally,
                refLabel: ref.map { Dates.formatShort($0.tally.key) } ?? ""
            )
        }
        return (a, b)
    }

    private var compareTitle: String {
        switch compareChoice {
        case .sameDayLastWeek: return "Same day last week"
        case .day(let key): return ProgressFormat.dayLabel(key)
        case .week(let key): return "Week of \(Dates.formatShort(key))"
        }
    }

    private func choose(_ choice: CompareChoice) {
        guard choice != compareChoice else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { compareChoice = choice }
        Haptics.selection()
    }

    @ViewBuilder
    private func choiceButton(_ title: String, _ choice: CompareChoice) -> some View {
        Button { choose(choice) } label: {
            if compareChoice == choice {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    /// Lists only days / weeks actually trained, newest first.
    @ViewBuilder
    private func compareMenu(fold: ExerciseHistoryFold, latest: RepHistory.DayTally) -> some View {
        let otherDays = fold.days.filter { $0.key != latest.key }
        let latestWeek = ProgressFormat.weekKey(ofDay: latest.key)
        let otherWeeks = fold.weeks.filter { $0.key != latestWeek }
        Menu {
            choiceButton("Same day last week", .sameDayLastWeek)
            if !otherDays.isEmpty {
                Section("Days") {
                    ForEach(otherDays) { d in
                        choiceButton("\(ProgressFormat.dayLabel(d.key)) · \(summaryText(d))", .day(d.key))
                    }
                }
            }
            if !otherWeeks.isEmpty {
                Section("Weeks") {
                    ForEach(otherWeeks) { w in
                        choiceButton("Week of \(Dates.formatShort(w.key)) · \(summaryText(w))", .week(w.key))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(compareTitle)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(theme.accent)
        }
        .accessibilityLabel("Compare with \(compareTitle)")
    }

    private let leadingColumnWidth: CGFloat = 88

    @ViewBuilder
    private func comparisonCard(fold: ExerciseHistoryFold, latest: RepHistory.DayTally) -> some View {
        let cols = compareColumns(fold: fold, latest: latest)
        cardStyle {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    sectionLabel("Compare")
                    Spacer()
                    if fold.days.count > 1 { compareMenu(fold: fold, latest: latest) }
                }
                if cols.a.reference == nil && cols.b.reference == nil {
                    Text(fold.days.count > 1
                         ? "Nothing to line up with yet. Pick a day from the menu above."
                         : "First day logged. Comparisons start from your second day.")
                        .font(.callout).foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        Color.clear.frame(width: leadingColumnWidth, height: 1)
                        columnHeader(cols.a)
                        columnHeader(cols.b)
                    }
                    Divider().background(theme.line)
                    if measure == .holdSeconds {
                        holdRows(cols, latest: latest)
                    } else {
                        weightRows(cols, latest: latest)
                    }
                }
            }
        }
    }

    private func columnHeader(_ col: CompareColumn) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(col.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.text)
            Text(col.subtitle)
                .font(.caption2)
                .foregroundStyle(theme.dim)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deltaCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "+4 vs Oct 14" / "4 fewer than Oct 14" / "same as Oct 14" / "new weight" /
    /// "not done · 12 reps then" / "—".
    private func cellText(_ col: CompareColumn, weight: RepHistory.WeightKey) -> String {
        guard let ref = col.reference else { return "not logged" }
        let cur = col.current.amount(at: weight)
        let was = ref.amount(at: weight)
        guard let outcome = RepHistory.outcome(current: cur, reference: was) else { return "—" }
        if outcome == .notDone, let was {
            return "not done · \(ProgressFormat.amount(was, measure: measure)) then"
        }
        return RepHistory.deltaText(outcome, reference: col.refLabel) ?? "—"
    }

    @ViewBuilder
    private func weightRows(_ cols: (a: CompareColumn, b: CompareColumn), latest: RepHistory.DayTally) -> some View {
        let keys = Set(
            [cols.a.current, cols.b.current, cols.a.reference, cols.b.reference]
                .compactMap { $0 }
                .flatMap { $0.lines.map(\.weight) }
        ).sorted()
        ForEach(keys, id: \.self) { key in
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ProgressFormat.weightLabel(key, system: unitSystem))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text(latest.amount(at: key).map { ProgressFormat.amount($0, measure: measure) } ?? "—")
                        .font(.caption).foregroundStyle(theme.dim)
                }
                .frame(width: leadingColumnWidth, alignment: .leading)
                deltaCell(cellText(cols.a, weight: key))
                deltaCell(cellText(cols.b, weight: key))
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "+5 s vs Oct 14" / "5 s shorter than Oct 14" (longest) or "less than" (total).
    private func secondsDeltaText(_ delta: Int, label: String, shorterWord: String) -> String {
        if delta == 0 { return "same as \(label)" }
        let span = RepHistory.durationText(seconds: abs(delta))
        return delta > 0 ? "+\(span) vs \(label)" : "\(span) \(shorterWord) than \(label)"
    }

    @ViewBuilder
    private func holdRows(_ cols: (a: CompareColumn, b: CompareColumn), latest: RepHistory.DayTally) -> some View {
        holdRow(
            title: "Longest hold",
            value: latest.longestHoldSeconds.map { RepHistory.durationText(seconds: $0) } ?? "—",
            cells: [cols.a, cols.b].map { col -> String in
                guard let ref = col.reference else { return "not logged" }
                guard let c = col.current.longestHoldSeconds, let r = ref.longestHoldSeconds else { return "—" }
                return secondsDeltaText(c - r, label: col.refLabel, shorterWord: "shorter")
            }
        )
        holdRow(
            title: "Total hold time",
            value: RepHistory.durationText(seconds: latest.totalAmount),
            cells: [cols.a, cols.b].map { col -> String in
                guard let ref = col.reference else { return "not logged" }
                return secondsDeltaText(col.current.totalAmount - ref.totalAmount,
                                        label: col.refLabel, shorterWord: "less")
            }
        )
    }

    private func holdRow(title: String, value: String, cells: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(value).font(.caption).foregroundStyle(theme.dim)
            }
            .frame(width: leadingColumnWidth, alignment: .leading)
            ForEach(Array(cells.enumerated()), id: \.offset) { _, text in deltaCell(text) }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Bests

    @ViewBuilder
    private func bestsCard(_ fold: ExerciseHistoryFold) -> some View {
        let bests = fold.bests
        // The first days are the baseline — no "best" until there's 2+ of them.
        if bests.dayCount >= RepHistory.minHistoryDaysForBest {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Bests · all time")
                if measure == .holdSeconds {
                    if let hold = bests.longestHold {
                        StatDetailRow(label: "Longest hold · \(Dates.formatShort(hold.dayKey))",
                                      value: RepHistory.durationText(seconds: hold.amount))
                    }
                    if let day = bests.bestDay {
                        StatDetailRow(label: "Most hold time in a day · \(Dates.formatShort(day.dayKey))",
                                      value: RepHistory.durationText(seconds: day.amount))
                    }
                } else {
                    let onlyBodyweight = bests.byWeight.count == 1 && bests.byWeight[0].weight.lb == nil
                    ForEach(bests.byWeight) { b in
                        StatDetailRow(
                            label: (onlyBodyweight
                                    ? "Best day"
                                    : ProgressFormat.weightLabel(b.weight, system: unitSystem))
                                + " · \(Dates.formatShort(b.dayKey))",
                            value: ProgressFormat.amount(b.amount, measure: measure))
                    }
                    if bests.byWeight.count > 1 {
                        if let heaviest = bests.heaviest {
                            StatDetailRow(label: "Heaviest · \(Dates.formatShort(heaviest.dayKey))",
                                          value: weightText(heaviest.lb))
                        }
                        if let day = bests.bestDay {
                            StatDetailRow(label: "Biggest day, all weights · \(Dates.formatShort(day.dayKey))",
                                          value: ProgressFormat.amount(day.amount, measure: measure))
                        }
                    }
                }
                Text("Bests are kept per weight, so going heavier for fewer reps is never a step back.")
                    .font(.caption2).foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Day list

    @ViewBuilder
    private func daysList(_ fold: ExerciseHistoryFold) -> some View {
        let shown = Array(fold.days.prefix(dayLimit))
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Days trained · \(fold.days.count)")
            ForEach(shown) { day in
                Button {
                    Haptics.tap()
                    dayTarget = ProgressDayTarget(dayKey: day.key)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ProgressFormat.relativeDayLabel(day.key))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(theme.text)
                            Text(summaryText(day))
                                .font(.caption).foregroundStyle(theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.dim)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this day's entries to edit")
            }
            if fold.days.count > shown.count {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { dayLimit += 60 }
                    Haptics.selection()
                } label: {
                    Text("Show older days (\(fold.days.count - shown.count) more)")
                }
                .tactile(.secondary, fullWidth: true)
            }
        }
    }
}
