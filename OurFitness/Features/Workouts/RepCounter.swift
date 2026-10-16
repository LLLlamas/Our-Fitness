// Friction-free set counter for any exercise. Scroll a wheel to the set's reps
// (or minutes for a duration exercise), Save set commits a WorkoutSet. Shows a weight field only
// for a lift that tracks per-set weight. For isometric exercises, shows a
// hold timer instead. Calories go through `Repos.setCaloriesEstimate`, the
// same function a set edit recomputes with.
//
// Progress is reps at a weight over the exercise's WHOLE history (docs/progress-tracking-plan.md):
// both screens read the exercise's rows with one predicate-scoped @Query, fold them with
// `RepHistory`, and show "Last time" / "Last week" reference lines at the weight now in the
// field plus a running tally for today. Observation only, no targets or advice. A fixed-load
// movement (Lifted Baby…) stamps its current load on every row it logs; a hold stores the
// seconds actually held. A new best toasts through `ToastCenter.newBest`.

import SwiftUI
import SwiftData

// MARK: - Entry point sheet (branches on isometric flag)

struct RepCounterSheet: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO

    @Environment(\.theme) private var theme

    var body: some View {
        if exercise.isIsometric {
            IsometricTimerView(profile: profile, exercise: exercise)
        } else {
            RepCounterView(profile: profile, exercise: exercise)
        }
    }
}

// MARK: - Shared history reads (file-private)

/// The exercise's full history folded once per data change. Rows are newest-first
/// (the @Query order). Re-folding on every body pass would re-format a day key per
/// row on each keystroke in the weight field, so the fold is memoised on a cheap
/// signature: row count, newest timestamp, the amounts, and the fixed load (which
/// decides what a legacy nil-weight row counts at).
private final class HistoryFold {
    private struct Signature: Equatable {
        let count: Int
        let newest: Date?
        let amountSum: Int
        let weightSum: Double
        let loadLb: Double?
    }

    private var signature: Signature?
    private(set) var rows: [WorkoutSetDTO] = []
    private(set) var days: [RepHistory.DayTally] = []

    func refresh(_ models: [WorkoutSetModel], exercise: ExerciseDTO) {
        let next = Signature(
            count: models.count,
            newest: models.first?.timestamp,
            amountSum: models.reduce(0) { $0 &+ $1.reps &+ ($1.holdSeconds ?? 0) },
            weightSum: models.reduce(0) { $0 + ($1.weightLb ?? 0) },
            loadLb: exercise.loadLb
        )
        guard next != signature else { return }
        signature = next
        rows = models.map(\.snapshot)
        days = RepHistory.days(for: exercise, rows: rows)
    }
}

/// One "Last time" / "Last week" row. `value` is nil for a line that is only a label
/// ("Last week · not logged"); `note` is the small caption under it.
private struct ReferenceLine: Identifiable {
    let id: String
    let label: String
    let value: String?
    let note: String?
}

/// Day label and number formatting for the reference lines. Weights convert at the
/// UI boundary only (canonical storage is lb) and keep up to two decimals, because
/// matching is by EXACT weight: rounding 52.5 lb to "52" would make the field
/// disagree with the history it is being compared to.
private enum ReferenceFormat {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    static func dayLabel(_ key: String) -> String {
        guard let d = Dates.date(fromDayKey: key) else { return key }
        return dayFormatter.string(from: d)
    }

    /// "50", "52.5", "22.68" — no unit, trailing zeros trimmed.
    static func trimmedWeight(lb: Double, system: UnitSystem) -> String {
        var s = String(format: "%.2f", Units.weightValue(lb: lb, system: system))
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    static func weight(lb: Double, system: UnitSystem) -> String {
        "\(trimmedWeight(lb: lb, system: system)) \(Units.weightUnit(system))"
    }

    static func amount(_ n: Int, measure: RepHistory.Measure) -> String {
        switch measure {
        case .reps: return "\(n) \(n == 1 ? "rep" : "reps")"
        case .minutes: return "\(n) min"
        case .holdSeconds: return RepHistory.durationText(seconds: n)
        }
    }

    /// "30 reps @ 50 lb", or just "42 reps" for bodyweight.
    static func value(_ n: Int, at key: RepHistory.WeightKey, measure: RepHistory.Measure,
                      system: UnitSystem) -> String {
        let base = amount(n, measure: measure)
        guard let lb = key.lb else { return base }
        return "\(base) @ \(weight(lb: lb, system: system))"
    }

    static func weightName(_ key: RepHistory.WeightKey, system: UnitSystem) -> String {
        key.lb.map { weight(lb: $0, system: system) } ?? "Bodyweight"
    }
}

/// Builds the reference rows and the running-tally strip from the folded days.
/// Pure formatting over `RepHistory`; the numbers all come from there.
private enum ReferenceBuilder {

    /// "Last time" and "Last week" for a rep or minutes exercise, at `key` (the
    /// weight now in the field). If a reference day didn't include that weight it
    /// shows the day's top weight, with a note for the last day this weight WAS done.
    static func lines(days: [RepHistory.DayTally], todayKey: String, key: RepHistory.WeightKey,
                      system: UnitSystem) -> [ReferenceLine] {
        guard let lastTime = RepHistory.lastTime(before: todayKey, days: days) else {
            return [ReferenceLine(id: "first", label: "First time here. See how it feels.",
                                  value: nil, note: nil)]
        }
        var out = [line(id: "time", title: "Last time", tally: lastTime, days: days,
                        todayKey: todayKey, key: key, system: system)]
        if let week = RepHistory.sameDayLastWeek(for: todayKey, days: days) {
            out.append(line(id: "week", title: "Last week", tally: week.tally, days: days,
                            todayKey: todayKey, key: key, system: system))
        } else {
            out.append(ReferenceLine(id: "week", label: "Last week · not logged", value: nil, note: nil))
        }
        return out
    }

    private static func line(id: String, title: String, tally: RepHistory.DayTally,
                             days: [RepHistory.DayTally], todayKey: String,
                             key: RepHistory.WeightKey, system: UnitSystem) -> ReferenceLine {
        let label = "\(title) · \(ReferenceFormat.dayLabel(tally.key))"
        if let n = tally.amount(at: key) {
            return ReferenceLine(id: id, label: label,
                                 value: ReferenceFormat.value(n, at: key, measure: tally.measure, system: system),
                                 note: nil)
        }
        guard let top = tally.topLine else {
            return ReferenceLine(id: id, label: label, value: nil, note: nil)
        }
        let who = ReferenceFormat.weightName(key, system: system)
        let note: String
        if let last = RepHistory.lastTime(at: key, before: todayKey, days: days),
           let n = last.amount(at: key) {
            note = "\(who): \(ReferenceFormat.amount(n, measure: last.measure)) on \(Dates.formatShort(last.key))"
        } else {
            note = "\(who): not done before"
        }
        return ReferenceLine(id: id, label: label,
                             value: ReferenceFormat.value(top.amount, at: top.weight, measure: tally.measure, system: system),
                             note: note)
    }

    /// The two comparison days, in the order the strips print them.
    private static func references(days: [RepHistory.DayTally], todayKey: String)
        -> [(tally: RepHistory.DayTally?, name: String)] {
        [
            (RepHistory.lastTime(before: todayKey, days: days), "last time"),
            (RepHistory.sameDayLastWeek(for: todayKey, days: days)?.tally, "last week"),
        ]
    }

    /// "Today 18 reps @ 50 lb · 12 to match last time · +2 vs last week". The weight is
    /// the first of `preferred` that was done today, else today's heaviest. Each delta
    /// flips from "N to match" to "+N" once passed; a shortfall is never a warning.
    static func todayStrip(days: [RepHistory.DayTally], todayKey: String,
                           preferred: [RepHistory.WeightKey], system: UnitSystem) -> String? {
        guard let today = days.first(where: { $0.key == todayKey }) else { return nil }
        guard let key = preferred.first(where: { today.amount(at: $0) != nil }) ?? today.topLine?.weight,
              let current = today.amount(at: key) else { return nil }
        var parts = ["Today \(ReferenceFormat.value(current, at: key, measure: today.measure, system: system))"]
        var seen = Set<String>()
        for ref in references(days: days, todayKey: todayKey) {
            guard let tally = ref.tally,
                  let outcome = RepHistory.outcome(current: current, reference: tally.amount(at: key)),
                  let text = RepHistory.liveDeltaText(outcome, reference: ref.name),
                  seen.insert(text).inserted else { continue }
            parts.append(text)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Holds

    private static func holdValue(_ t: RepHistory.DayTally) -> String {
        let longest = t.longestHoldSeconds ?? t.totalAmount
        let base = "longest \(RepHistory.durationText(seconds: longest))"
        guard t.rowCount > 1, t.totalAmount != longest else { return base }
        return "\(base) · total \(RepHistory.durationText(seconds: t.totalAmount))"
    }

    static func holdLines(days: [RepHistory.DayTally], todayKey: String) -> [ReferenceLine] {
        guard let lastTime = RepHistory.lastTime(before: todayKey, days: days) else {
            return [ReferenceLine(id: "first", label: "First time here. See how it feels.",
                                  value: nil, note: nil)]
        }
        var out = [ReferenceLine(id: "time",
                                 label: "Last time · \(ReferenceFormat.dayLabel(lastTime.key))",
                                 value: holdValue(lastTime), note: nil)]
        if let week = RepHistory.sameDayLastWeek(for: todayKey, days: days) {
            out.append(ReferenceLine(id: "week",
                                     label: "Last week · \(ReferenceFormat.dayLabel(week.tally.key))",
                                     value: holdValue(week.tally), note: nil))
        } else {
            out.append(ReferenceLine(id: "week", label: "Last week · not logged", value: nil, note: nil))
        }
        return out
    }

    /// "Today longest 55 s · total 2 min 10 s · +5 s vs last time".
    static func holdStrip(days: [RepHistory.DayTally], todayKey: String) -> String? {
        guard let today = days.first(where: { $0.key == todayKey }),
              let longest = today.longestHoldSeconds else { return nil }
        var text = "Today \(RepHistory.durationText(seconds: longest))"
        if today.rowCount > 1, today.totalAmount != longest {
            text = "Today longest \(RepHistory.durationText(seconds: longest)) · total \(RepHistory.durationText(seconds: today.totalAmount))"
        }
        var parts = [text]
        var seen = Set<String>()
        for ref in references(days: days, todayKey: todayKey) {
            guard let tally = ref.tally, let before = tally.longestHoldSeconds else { continue }
            let delta = longest - before
            let note = delta > 0 ? "+\(delta) s vs \(ref.name)"
                : delta < 0 ? "\(-delta) s to match \(ref.name)"
                : "matches \(ref.name)"
            if seen.insert(note).inserted { parts.append(note) }
        }
        return parts.joined(separator: " · ")
    }
}

/// The reference rows under the exercise name. A neutral card: dim labels, plain values.
private struct ReferenceBlock: View {
    let lines: [ReferenceLine]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(line.label)
                            .foregroundStyle(theme.dim)
                        if let value = line.value {
                            Spacer(minLength: 8)
                            Text(value)
                                .foregroundStyle(theme.text)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .font(.caption)
                    if let note = line.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(theme.dim)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - Rep counter (non-isometric)

private struct RepCounterView: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    // The exercise's FULL history for this profile, newest first (predicate-scoped,
    // never filtered client-side). Drives "last time", the running tally, the weight
    // pre-fill and the new-best check.
    @Query private var historyModels: [WorkoutSetModel]
    // The live exercise row: `exercise` is a copy taken when the sheet opened, so a
    // fixed load edited from the ⓘ sheet on top of this one would otherwise be
    // stamped at its old value.
    @Query private var exerciseModels: [ExerciseModel]

    @State private var fold = HistoryFold()
    @State private var reps: Int = 10
    @State private var weightStr: String = ""
    @State private var sessionAmount: Int = 0
    @State private var showInfo = false
    @State private var lastProjection: String?
    @State private var savedKey: RepHistory.WeightKey?
    @State private var prefilledWeight = false
    @State private var prefilledLb: Double?
    @State private var prefilledText = ""
    @State private var prefilledCount = false
    @FocusState private var weightFocused: Bool

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    init(profile: ProfileDTO, exercise: ExerciseDTO) {
        self.profile = profile
        self.exercise = exercise
        let uid = profile.id
        let exId = exercise.id
        _historyModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid && $0.exerciseId == exId },
            sort: \.timestamp, order: .reverse
        )
        _exerciseModels = Query(filter: #Predicate<ExerciseModel> { $0.id == exId })
    }

    private var live: ExerciseDTO { exerciseModels.first?.snapshot ?? exercise }
    private var tracksWeight: Bool { live.tracksPerSetWeight }
    private var info: ExerciseInfo.Meta { ExerciseInfo.meta(for: live) }
    /// A duration exercise stores minutes in `reps`, so the counter counts minutes.
    private var isMinutes: Bool { live.kind == .duration }
    private func unitWord(_ n: Int) -> String { isMinutes ? "min" : (n == 1 ? "rep" : "reps") }
    /// Wheel range: 1–100 reps, or 1–180 minutes for a duration exercise.
    private var countRange: ClosedRange<Int> { isMinutes ? 1...180 : 1...100 }

    /// The folded history, refreshed only when the rows actually changed.
    private var history: HistoryFold {
        fold.refresh(historyModels, exercise: live)
        return fold
    }

    /// The weight in the field, in canonical lb. An untouched pre-fill returns the
    /// exact stored value, so a unit round-trip can't turn 50 lb into 49.9995.
    private var fieldWeightLb: Double? {
        if let pre = prefilledLb, weightStr == prefilledText { return pre }
        guard let parsed = Units.parseWeightToLb(weightStr, system: unitSystem), parsed.isFinite else { return nil }
        // Canonical to 0.01 lb so a retyped "22.68" kg is the 50 lb already logged.
        let w = RepHistory.canonicalLb(parsed)
        return w > 0 ? w : nil
    }

    /// The weight the reference lines read against: the field for a lift that tracks
    /// weight, the exercise's own load for a fixed-load movement, else bodyweight.
    private var fieldKey: RepHistory.WeightKey {
        tracksWeight
            ? RepHistory.WeightKey(fieldWeightLb)
            : RepHistory.WeightKey(live.fixedLoadLb(forRowWeight: nil, holdSeconds: nil))
    }

    var body: some View {
        let days = history.days
        let todayKey = Dates.dayKey()
        let strip = ReferenceBuilder.todayStrip(
            days: days, todayKey: todayKey,
            preferred: [savedKey, fieldKey].compactMap { $0 }, system: unitSystem)
        ScrollView {
            VStack(spacing: 18) {
                header
                ReferenceBlock(lines: ReferenceBuilder.lines(
                    days: days, todayKey: todayKey, key: fieldKey, system: unitSystem))
                countPicker
                if tracksWeight {
                    weightField
                }
                actionRow
                if let strip {
                    ProjectionBar(text: strip)
                }
                if let projection = lastProjection {
                    ProjectionBar(text: projection)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The wheel + Save fit a half sheet; .large stays available for the reference
        // lines and the weight field with the keyboard up.
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .onAppear {
            prefillCount()
            prefillWeight()
        }
        .sheet(isPresented: $showInfo) {
            ExerciseInfoSheet(exercise: live, profile: profile)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
    }

    /// Carry the last weight ever used for this lift into the field (not just this
    /// week's). Same weight across sets is the common case, and re-typing it was the
    /// only typing left in the logging flow. Fills once, and only an empty field, so
    /// it can never overwrite what the user is typing. Keeps the stored value's
    /// precision: exact-weight matching means 52.5 must not become "52".
    private func prefillWeight() {
        guard tracksWeight, weightStr.isEmpty, !prefilledWeight else { return }
        prefilledWeight = true
        guard let last = RepHistory.lastWeightLb(for: live, rows: history.rows) else { return }
        let text = ReferenceFormat.trimmedWeight(lb: last, system: unitSystem)
        prefilledLb = last
        prefilledText = text
        weightStr = text
    }

    /// Start the wheel on the last logged count for this exercise (any earlier day),
    /// else 10 reps / 5 min. Runs once, so it never moves the wheel out from under
    /// the user.
    private func prefillCount() {
        guard !prefilledCount else { return }
        prefilledCount = true
        let last = history.rows.first(where: { $0.holdSeconds == nil && $0.reps > 0 })?.reps
        let fallback = isMinutes ? 5 : 10
        reps = min(max(last ?? fallback, countRange.lowerBound), countRange.upperBound)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(live.name)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.dim)
                }
                .tactile(.ghost)
            }
            Text(info.muscleGroups.prefix(3).joined(separator: " · "))
                .font(.system(size: 12, weight: .medium)).tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(theme.accent)
            Text("\(sessionAmount) \(unitWord(sessionAmount)) this session")
                .font(.caption).foregroundStyle(theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Same wheel idiom as the isometric hold picker.
    @ViewBuilder
    private var countPicker: some View {
        VStack(spacing: 8) {
            Text((isMinutes ? "Minutes this set" : "Reps this set").uppercased())
                .font(.system(size: 10)).tracking(2)
                .foregroundStyle(theme.dim)
            Picker(isMinutes ? "Minutes" : "Reps", selection: $reps) {
                ForEach(Array(countRange), id: \.self) { n in
                    Text("\(n) \(unitWord(n))").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            .clipped()
        }
    }

    @ViewBuilder
    private var weightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weight (\(Units.weightUnit(unitSystem))) · optional")
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            TextField("", text: $weightStr)
                .keyboardType(.decimalPad)
                .padding(10).background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
                .font(.system(.title3, design: .monospaced))
                .focused($weightFocused)
            Text("Dumbbells: the weight of one, not the pair. One-arm move? Log each arm as its own set. Leave blank for bodyweight.")
                .font(.caption).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                saveSet()
            } label: {
                Text("Save set")
            }
            .tactile(.primary, fill: theme.ok)

            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .tactile(.ghost)
        }
    }

    private func saveSet() {
        let ex = live
        // Field shows the active unit; persist canonical lb. A fixed-load movement
        // stamps its CURRENT load on the row (history keeps the weight each rep was
        // done at, even after the load is edited); a hold never gets a weight.
        let typed = tracksWeight ? fieldWeightLb : nil
        let rowWeight = tracksWeight ? typed : ex.fixedLoadLb(forRowWeight: nil, holdSeconds: nil)
        let kcal = Repos.setCaloriesEstimate(
            exercise: ex,
            reps: reps,
            holdSeconds: nil,
            bodyWeightLb: profile.weightLb
        )

        // Snapshot pre-save figures so the projection and the new-best check don't
        // depend on @Query refresh timing (SwiftData may not reflect the new set this tick).
        let rowsBefore = history.rows
        let caloriesTodayBefore = historyModels
            .filter { Calendar.current.isDateInToday($0.timestamp) }
            .reduce(0.0) { $0 + ($1.caloriesEst ?? 0) }

        let dto = WorkoutSetDTO(
            userId: profile.id,
            exerciseId: ex.id,
            weightLb: rowWeight,
            reps: reps,
            caloriesEst: kcal
        )
        guard Repos.addSet(ctx, dto) else { return }
        sessionAmount += reps
        savedKey = RepHistory.weightKey(of: dto, exercise: ex)

        // Same figure the set was stored with, so the strip matches the toast.
        lastProjection = EncouragementEngine.repProjection(
            setCalories: kcal,
            totalCaloriesToday: caloriesTodayBefore
        )

        // One toast: a new best outranks the plain confirmation. Judged against the
        // history WITHOUT this row; edits and back-fills never come through this view.
        let system = unitSystem
        if let best = RepHistory.newBest(after: dto, exercise: ex, rows: rowsBefore) {
            toasts.newBest(best) { ReferenceFormat.weight(lb: $0, system: system) }
        } else if RepHistory.isRepExercise(ex),
                  toasts.weeklyReps(Repos.weeklyReps(ctx, userId: profile.id), profileId: profile.id) {
            // The weekly-reps note (once per kind per week) stands in for "Set saved".
        } else {
            toasts.show(Toast(
                title: "Set saved",
                detail: typed.map { "\(ReferenceFormat.weight(lb: $0, system: system)) × \(reps)" }
                    ?? "\(reps) \(unitWord(reps)) · ~\(Int(kcal)) cal",
                accent: .win,
                symbol: "checkmark.seal.fill"
            ))
        }
        // The wheel keeps its value: the next set is usually the same count.
    }
}

// MARK: - Isometric timer

private struct IsometricTimerView: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var historyModels: [WorkoutSetModel]
    @Query private var exerciseModels: [ExerciseModel]

    @State private var fold = HistoryFold()
    @State private var pickedSeconds: Int = 60
    /// When the running hold began. Elapsed is measured against the wall clock, so a
    /// locked screen or a backgrounded app can't make the hold read short.
    @State private var startedAt: Date? = nil
    @State private var elapsed: Int = 0
    @State private var reachedTarget = false
    @State private var holdsThisSession: Int = 0
    @State private var totalSecSession: Int = 0
    @State private var showInfo = false

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    /// A hold keeps counting past the target until stopped; this ends one that was
    /// forgotten (phone put down) so it can't log an absurd time.
    private static let maxHoldSeconds = 600

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var isRunning: Bool { startedAt != nil }
    private var live: ExerciseDTO { exerciseModels.first?.snapshot ?? exercise }
    private var info: ExerciseInfo.Meta { ExerciseInfo.meta(for: live) }

    init(profile: ProfileDTO, exercise: ExerciseDTO) {
        self.profile = profile
        self.exercise = exercise
        let uid = profile.id
        let exId = exercise.id
        _historyModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid && $0.exerciseId == exId },
            sort: \.timestamp, order: .reverse
        )
        _exerciseModels = Query(filter: #Predicate<ExerciseModel> { $0.id == exId })
    }

    private var history: HistoryFold {
        fold.refresh(historyModels, exercise: live)
        return fold
    }

    var body: some View {
        let days = history.days
        let todayKey = Dates.dayKey()
        VStack(spacing: 18) {
            header
            ReferenceBlock(lines: ReferenceBuilder.holdLines(days: days, todayKey: todayKey))
            if isRunning {
                countdownDisplay
                stopButton
                discardButton
            } else {
                pickerSection
                startButton
            }
            if let strip = ReferenceBuilder.holdStrip(days: days, todayKey: todayKey) {
                ProjectionBar(text: strip)
            }
            if holdsThisSession > 0 {
                sessionSummary
            }
            Spacer()
            Button { dismiss() } label: { Text("Done") }
                .tactile(.ghost)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .onReceive(ticker) { _ in tick() }
        .sheet(isPresented: $showInfo) {
            ExerciseInfoSheet(exercise: live, profile: profile)
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(live.name)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Button { showInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.dim)
                }
                .tactile(.ghost)
            }
            Text("Isometric · \(info.muscleGroups.first ?? "Core")")
                .font(.system(size: 12, weight: .medium)).tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(theme.accent)
            Text("\(holdsThisSession) hold\(holdsThisSession == 1 ? "" : "s") this session")
                .font(.caption).foregroundStyle(theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Counts down to the target, then keeps counting UP so the time actually held is
    /// what gets logged.
    @ViewBuilder
    private var countdownDisplay: some View {
        let past = elapsed >= pickedSeconds
        let remaining = max(0, pickedSeconds - elapsed)
        VStack(spacing: 4) {
            AnimatedNumber(
                Double(past ? elapsed : remaining),
                font: .system(size: 120, weight: .semibold),
                color: past ? theme.ok : (remaining <= 5 ? Color.orange : theme.accent)
            )
            Text(past ? "seconds held · \(pickedSeconds) s target reached" : "seconds remaining")
                .font(.caption).tracking(1)
                .foregroundStyle(theme.dim)
        }
    }

    /// The four holds people actually pick, one tap each. The wheel below stays
    /// for everything else — same presets-plus-fine-control shape the live
    /// session picker uses for expected time.
    private let presets = [30, 45, 60, 90]

    @ViewBuilder
    private var pickerSection: some View {
        VStack(spacing: 8) {
            Text("Set hold duration".uppercased())
                .font(.system(size: 10)).tracking(2)
                .foregroundStyle(theme.dim)
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { secs in
                    Button {
                        pickedSeconds = secs
                        Haptics.selection()
                    } label: {
                        Text(formattedHoldDuration(secs))
                    }
                    .tactile(.pill, fill: pickedSeconds == secs ? theme.accent : nil)
                }
            }
            Picker("Duration", selection: $pickedSeconds) {
                ForEach(Array(stride(from: 5, through: 300, by: 5)), id: \.self) { s in
                    Text(formattedHoldDuration(s)).tag(s)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            .clipped()
        }
    }

    @ViewBuilder
    private var startButton: some View {
        Button {
            startedAt = Date()
            elapsed = 0
            reachedTarget = false
            Haptics.bump()
        } label: {
            Text("Start hold")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 88)
        }
        .tactile(.primary, fullWidth: true)
    }

    /// Ends the hold and logs the seconds actually held — early, on the target, or past it.
    @ViewBuilder
    private var stopButton: some View {
        Button {
            finishHold()
        } label: {
            Text("Stop and log")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 88)
        }
        .tactile(.primary, fullWidth: true)
    }

    /// Abandons a hold that shouldn't count (started by mistake). Logs nothing.
    @ViewBuilder
    private var discardButton: some View {
        Button {
            startedAt = nil
            elapsed = 0
            Haptics.warn()
        } label: {
            Text("Discard")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .tactile(.secondary, fullWidth: true)
    }

    @ViewBuilder
    private var sessionSummary: some View {
        HStack(spacing: 20) {
            VStack(spacing: 2) {
                Text("\(holdsThisSession)")
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .contentTransition(.numericText())
                Text("holds".uppercased())
                    .font(.system(size: 9)).tracking(1.5)
                    .foregroundStyle(theme.dim)
            }
            Divider().frame(height: 36)
            VStack(spacing: 2) {
                Text(formattedHoldDuration(totalSecSession))
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .contentTransition(.numericText())
                Text("total".uppercased())
                    .font(.system(size: 9)).tracking(1.5)
                    .foregroundStyle(theme.dim)
            }
        }
        .padding(12)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    private func tick() {
        guard let start = startedAt else { return }
        let seconds = Int(Date().timeIntervalSince(start))
        elapsed = seconds
        // One cue when the target is reached; the hold itself carries on.
        if seconds >= pickedSeconds, !reachedTarget {
            reachedTarget = true
            Haptics.success()
        }
        if seconds >= Self.maxHoldSeconds { finishHold() }
    }

    /// Log the time actually held. Stopping inside the first second logs nothing.
    private func finishHold() {
        guard let start = startedAt else { return }
        let held = min(Int(Date().timeIntervalSince(start)), Self.maxHoldSeconds)
        startedAt = nil
        elapsed = 0
        guard held >= 1 else { return }

        let ex = live
        let kcal = Repos.setCaloriesEstimate(
            exercise: ex,
            reps: 1,
            holdSeconds: held,
            bodyWeightLb: profile.weightLb
        )
        let dto = WorkoutSetDTO(
            userId: profile.id,
            exerciseId: ex.id,
            reps: 1,
            caloriesEst: kcal,
            holdSeconds: held
        )
        let rowsBefore = history.rows
        guard Repos.addSet(ctx, dto) else { return }
        holdsThisSession += 1
        totalSecSession += held
        let system = unitSystem
        if let best = RepHistory.newBest(after: dto, exercise: ex, rows: rowsBefore) {
            toasts.newBest(best) { ReferenceFormat.weight(lb: $0, system: system) }
        } else if RepHistory.isRepExercise(ex),
                  toasts.weeklyReps(Repos.weeklyReps(ctx, userId: profile.id), profileId: profile.id) {
            // The weekly-reps note (once per kind per week) stands in for "Set saved".
        } else {
            toasts.show(Toast(
                title: "Hold logged",
                detail: "\(formattedHoldDuration(held)) · ~\(Int(kcal)) cal",
                accent: .win,
                symbol: "checkmark.seal.fill"
            ))
        }
    }
}
