// The Train tab's ONE exercise list — every exercise the profile owns, lifts,
// holds and quick-log movements alike, each rendered exactly once.
//
// Header ring: reps toward the user's reps goal (per day or per week, switch +
// −/+ goal row under the header), plus today's burn. Reps, not sets — each +1
// is its own 1-rep set. Math in Domain/RepTarget.swift; the goal is stored per
// profile and period (`RepTargetPrefs`); unset = seeded from the user's own
// last week, and with no history the row says "Set a goal".
// Each row picks its controls from the exercise's SHAPE, never from the goal:
//   • isometric            → tap opens the hold timer; no ±1
//   • every other shape     → inline −1 / +1 (−1 min / +1 min for a duration),
//                             so a rep can be added or taken back without
//                             opening the counter; tapping the row body still
//                             opens the rep counter (with its weight field when
//                             the lift tracks per-set weight) for bigger sets.
//                             +1 logs a new 1-rep set (a per-set-weight lift is
//                             stamped with the last weight ever used for it, else
//                             bodyweight). −1 takes one rep off TODAY's newest set
//                             (`Repos.removeOneFromToday`: a 1-rep set is deleted,
//                             a longer one is re-priced through `updateSet`);
//                             disabled at 0 today and never touches yesterday.
//                             Whole sets are edited/deleted via the clock →
//                             SetHistorySheet.
// Every row also carries the clock (→ SetHistorySheet, the one set editor) and
// ⓘ (→ ExerciseInfoSheet). Press-and-hold on the row body asks to delete the
// exercise (confirmed); SetHistorySheet's "Delete exercise" is the explicit path.
// The hold rides on the row-body buttons only, so −1 / +1 / clock / ⓘ keep
// their plain taps.
//
// Calories shown here are the stored `caloriesEst` of the logged sets; every
// write estimates through `Repos.setCaloriesEstimate`, so there is no second
// copy of the MET math in this file.

import SwiftUI
import SwiftData

/// Per-profile reps-goal keys. A stored 0 means "never set" — fall back to the
/// default from last week (`RepTarget.resolve`).
enum RepTargetPrefs {
    static func periodKey(_ profileId: UUID) -> String { "repsTargetPeriod.\(profileId.uuidString)" }
    static func goalKey(_ profileId: UUID, _ period: RepTarget.Period) -> String {
        "repsTarget.\(period.rawValue).\(profileId.uuidString)"
    }
}

struct ExercisesCard: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    // Profile-scoped at the query level — never fetch another profile's rows.
    @Query private var exerciseModels: [ExerciseModel]
    @Query private var setModels: [WorkoutSetModel]

    @State private var showAddSheet = false
    @State private var activeCounter: ExerciseDTO?
    @State private var activeInfo: ExerciseDTO?
    @State private var activeHistory: ExerciseDTO?
    @State private var ringGlow: Bool = false
    @State private var reveal: CGFloat = 0
    /// Set by a press-and-hold on a row; drives the delete confirmation. While
    /// it's non-nil the row-body tap is ignored, so lifting the finger after
    /// the hold doesn't also open the rep counter.
    @State private var pendingDelete: ExerciseDTO?

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial
    @AppStorage private var targetPeriodRaw: String
    @AppStorage private var dayGoal: Int
    @AppStorage private var weekGoal: Int

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _exerciseModels = Query(
            filter: #Predicate<ExerciseModel> { $0.profileId == uid },
            sort: \.name, order: .forward
        )
        _targetPeriodRaw = AppStorage(wrappedValue: RepTarget.Period.day.rawValue,
                                      RepTargetPrefs.periodKey(uid))
        _dayGoal = AppStorage(wrappedValue: 0, RepTargetPrefs.goalKey(uid, .day))
        _weekGoal = AppStorage(wrappedValue: 0, RepTargetPrefs.goalKey(uid, .week))
        // From last ISO week's Monday: the rows show today + yesterday (older
        // sets live in Training history), the reps goal needs this week and
        // last week (its default). Last Monday is always before yesterday.
        let cutoff = Dates.startOfISOWeek(weeksAgo: 1)
        _setModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid && $0.timestamp >= cutoff },
            sort: \.timestamp, order: .forward
        )
    }

    // Exercises arrive name-sorted from the query; re-sort case-insensitively so
    // capitalisation never breaks the A→Z order the user sees.
    private var myExercises: [ExerciseDTO] {
        exerciseModels.map(\.snapshot)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Stats

    private struct ExerciseStats {
        var todayReps: Int = 0
        var yesterdayReps: Int = 0
        var todayCal: Double = 0
        var yesterdayCal: Double = 0
        var todayHoldSec: Int = 0
        var yesterdayHoldSec: Int = 0
        /// Rows logged today — shown next to the history icon so the icon reads
        /// as "3 sets, tap to fix them" instead of an unlabelled clock.
        var todaySets: Int = 0
    }

    /// The one aggregation for this card: per-exercise today/yesterday totals,
    /// calories summed from what each set stored when it was logged.
    private var statsByExercise: [String: ExerciseStats] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        return setModels.reduce(into: [String: ExerciseStats]()) { acc, s in
            let ts = s.timestamp
            let inToday = ts >= todayStart
            let inYesterday = !inToday && ts >= yesterdayStart
            guard inToday || inYesterday else { return }

            var stats = acc[s.exerciseId] ?? ExerciseStats()
            if inToday {
                stats.todayReps += s.reps
                stats.todayHoldSec += s.holdSeconds ?? 0
                stats.todayCal += s.caloriesEst ?? 0
                stats.todaySets += 1
            } else {
                stats.yesterdayReps += s.reps
                stats.yesterdayHoldSec += s.holdSeconds ?? 0
                stats.yesterdayCal += s.caloriesEst ?? 0
            }
            acc[s.exerciseId] = stats
        }
    }

    var body: some View {
        let exercises = myExercises
        let stats = statsByExercise
        let todayCal = exercises.reduce(0.0) { $0 + (stats[$1.id]?.todayCal ?? 0) }
        let target = repTarget(exercises)

        Card {
            VStack(alignment: .leading, spacing: 14) {
                header(target: target, todayCal: todayCal)
                if !exercises.isEmpty {
                    goalRow(target)
                }

                if exercises.isEmpty {
                    // The whole block adds an exercise — a first-time user
                    // shouldn't have to find the small + to get started.
                    PressableCard(action: { showAddSheet = true }) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(theme.accent)
                                Text("Add your first exercise")
                                    .font(.callout).foregroundStyle(theme.text)
                            }
                            Text("Lifts, holds, or everyday movements — log reps, minutes, or weight. Not sure what to pick? Use “What do you want to work on?” below.")
                                .font(.caption).foregroundStyle(theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    let lastId = exercises.last?.id
                    ForEach(exercises) { ex in
                        exerciseRow(ex, stats: stats[ex.id] ?? ExerciseStats())
                        if ex.id != lastId {
                            Divider().background(theme.line)
                        }
                    }
                }
            }
        }
        // Sheets hang off the list, not the rows: deleting the last set from
        // inside SetHistorySheet changes the row, which would otherwise yank the
        // sheet out from under the user mid-edit.
        .sheet(isPresented: $showAddSheet) {
            AddExerciseSheet { draft in
                guard Repos.createExercise(
                    ctx, profileId: profile.id, name: draft.name,
                    defaultRepsBottom: 8, defaultRepsTop: 12,
                    tracksWeight: draft.tracksWeight,
                    loadLb: draft.loadLb,
                    kind: draft.kind,
                    isIsometric: draft.isIsometric
                ) != nil else { return }
                toasts.show(Toast(title: draft.name, detail: "Exercise added", accent: .win, symbol: "plus.circle.fill"))
            }
        }
        .sheet(item: $activeCounter) { ex in
            RepCounterSheet(profile: profile, exercise: ex)
        }
        .sheet(item: $activeInfo) { ex in
            let s = statsByExercise[ex.id] ?? ExerciseStats()
            ExerciseInfoSheet(
                exercise: ex,
                profile: profile,
                todayCount: ex.isIsometric ? s.todaySets : s.todayReps,
                todayKcal: s.todayCal
            )
        }
        .sheet(item: $activeHistory) { ex in
            SetHistorySheet(profile: profile, exercise: ex)
        }
    }

    /// Press-and-hold on a row body: one strong warning haptic the moment the
    /// hold is recognised (no toast fires here), then the confirmation.
    private func requestDelete(_ ex: ExerciseDTO) {
        Haptics.warn()
        pendingDelete = ex
    }

    // MARK: - Header

    private struct TargetState {
        let period: RepTarget.Period
        let reps: Int
        let goal: Int?
        /// True when `goal` is last week's default, not one the user set.
        let isDefault: Bool
    }

    private var targetPeriod: RepTarget.Period {
        RepTarget.Period(rawValue: targetPeriodRaw) ?? .day
    }

    private func repTarget(_ exercises: [ExerciseDTO]) -> TargetState {
        let period = targetPeriod
        let totals = TrainingHistory.dailyRepTotals(setModels.map(\.snapshot), exercises: exercises)
        let now = Date()
        let stored = period == .day ? dayGoal : weekGoal
        return TargetState(
            period: period,
            reps: RepTarget.reps(totals, period: period, now: now),
            goal: RepTarget.resolve(
                stored: stored,
                suggested: RepTarget.suggestedGoal(totals, period: period, now: now)),
            isDefault: stored <= 0
        )
    }

    private func adjustGoal(_ direction: Int, _ target: TargetState) {
        guard let next = RepTarget.adjusted(target.goal, by: direction, period: target.period),
              next != target.goal || target.isDefault else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if target.period == .day { dayGoal = next } else { weekGoal = next }
        }
        Haptics.tap()
    }

    @ViewBuilder
    private func header(target: TargetState, todayCal: Double) -> some View {
        let unit = target.period == .day ? "today" : "this week"
        HStack(alignment: .center, spacing: 12) {
            // Reps toward the goal. No goal yet = empty ring with the count,
            // never a made-up target.
            let pct = RepTarget.fraction(reps: target.reps, goal: target.goal)
            ProgressRing(pct: pct * Double(reveal), color: theme.accent,
                         trackColor: theme.barBg, lineWidth: 7)
                .shadow(color: theme.accent.opacity(ringGlow ? 0.55 : 0), radius: ringGlow ? 10 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: ringGlow)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: pct)
                .frame(width: 54, height: 54)
                .overlay {
                    Text("\(target.reps)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .contentTransition(.numericText())
                }
                .revealOnAppear($reveal)
                .accessibilityLabel(target.goal.map { "\(target.reps) of \($0) reps \(unit)" }
                                    ?? "\(target.reps) reps \(unit), no goal set")

            VStack(alignment: .leading, spacing: 2) {
                Text("Exercises")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                Text(target.goal.map { "\(target.reps) of \($0) reps \(unit)" } ?? "\(target.reps) reps \(unit)")
                    .font(.caption)
                    .foregroundStyle(theme.dim)
                    .contentTransition(.numericText())
                if todayCal > 0 {
                    Text("~\(Int(todayCal)) cal burned today")
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                }
            }
            Spacer()
            Button { showAddSheet = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
            }
            .tactile(.ghost)
            .accessibilityLabel("Add exercise")
        }
    }

    /// Day / Week switch + −/+ goal, same shape as WaterCard's goal row.
    private func goalRow(_ target: TargetState) -> some View {
        HStack(spacing: 10) {
            Picker("Reps goal period", selection: Binding(
                get: { targetPeriod },
                set: { p in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { targetPeriodRaw = p.rawValue }
                    Haptics.selection()
                }
            )) {
                Text("Day").tag(RepTarget.Period.day)
                Text("Week").tag(RepTarget.Period.week)
            }
            .pickerStyle(.segmented)
            .frame(width: 116)
            Spacer()
            Button { adjustGoal(-1, target) } label: { Image(systemName: "minus") }
                .tactile(.ghost)
                .disabled(target.goal == nil)
                .accessibilityLabel("Lower reps goal")
            Text(target.goal.map { "\($0) reps" } ?? "Set a goal")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(target.goal == nil ? theme.dim : theme.text)
                .contentTransition(.numericText())
            Button { adjustGoal(1, target) } label: { Image(systemName: "plus") }
                .tactile(.ghost)
                .accessibilityLabel("Raise reps goal")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func exerciseRow(_ ex: ExerciseDTO, stats: ExerciseStats) -> some View {
        let info = ExerciseInfo.meta(for: ex)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                // Row body: always opens the counter that fits the shape —
                // RepCounterSheet branches to the hold timer for an isometric.
                Button { openCounter(ex) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(ex.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.text)
                            if ex.isIsometric {
                                Text("Isometric")
                                    .font(.system(size: 10, weight: .medium)).tracking(1)
                                    .textCase(.uppercase)
                                    .foregroundStyle(theme.accent.opacity(0.7))
                            }
                        }
                        Text(info.muscleGroups.prefix(3).joined(separator: " · ") + loadLabel(ex))
                            .font(.system(size: 10, weight: .medium)).tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(theme.accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .tactile(.ghost)
                .simultaneousGesture(deleteHold(ex))
                .accessibilityLabel(ex.isIsometric ? "\(ex.name): start a hold" : "\(ex.name): count a set")
                .accessibilityAction(named: "Delete \(ex.name)") { pendingDelete = ex }

                Button { activeHistory = ex } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(theme.dim)
                        if stats.todaySets > 0 {
                            Text("\(stats.todaySets)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.accent)
                        }
                    }
                }
                .tactile(.ghost)
                .accessibilityLabel(stats.todaySets > 0
                                    ? "\(ex.name): \(stats.todaySets) sets today, edit or delete"
                                    : "\(ex.name) logged sets")

                Button { activeInfo = ex } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(theme.dim)
                }
                .tactile(.ghost)
                .accessibilityLabel("About \(ex.name)")
            }

            HStack(alignment: .bottom, spacing: 0) {
                Button { openCounter(ex) } label: {
                    HStack(spacing: 0) {
                        statCell(ex, label: "Today",
                                 reps: stats.todayReps, holdSec: stats.todayHoldSec, cal: stats.todayCal)
                        Divider().frame(height: 32).background(theme.line).padding(.horizontal, 8)
                        statCell(ex, label: "Yesterday",
                                 reps: stats.yesterdayReps, holdSec: stats.yesterdayHoldSec, cal: stats.yesterdayCal)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .tactile(.ghost)
                .simultaneousGesture(deleteHold(ex))
                .accessibilityHidden(true)

                if !ex.isIsometric {
                    quickLogControls(ex, todaySets: stats.todaySets)
                }
            }
        }
        .padding(.vertical, 4)
        // Attached per row (one is ever presented — it keys off
        // `pendingDelete`) so the iOS 26 popover points at the row being
        // deleted, not at the whole card.
        .confirmationDialog(
            "Delete \(ex.name)?",
            isPresented: Binding(
                get: { pendingDelete?.id == ex.id },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            // Clear explicitly: once the row is gone its dialog binding may never
            // be written back, and a stale `pendingDelete` swallows every row tap.
            Button("Delete exercise and all its sets", role: .destructive) {
                pendingDelete = nil
                deleteExercise(ex)
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the exercise and every set logged for it.")
        }
    }

    /// Row-body tap. Swallowed while a delete confirmation is up: the hold that
    /// raised it ends in a finger-lift, which the Button still reports as a tap.
    private func openCounter(_ ex: ExerciseDTO) {
        guard pendingDelete == nil else { return }
        activeCounter = ex
    }

    /// Press-and-hold → delete confirmation. Simultaneous with the Button's own
    /// tap (a parent/exclusive gesture would starve it); LongPressGesture's
    /// default 10pt max distance lets a scroll cancel it.
    private func deleteHold(_ ex: ExerciseDTO) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in requestDelete(ex) }
    }

    /// Fixed carried load, appended to the muscle line (" · 30 LB").
    private func loadLabel(_ ex: ExerciseDTO) -> String {
        guard let lb = ex.loadLb else { return "" }
        return " · \(Units.formatWeightWithUnit(lb: lb, system: unitSystem, decimals: 0))"
    }

    /// Inline −1 / +1 for every non-isometric row (plain "−1" / "+1" even for a
    /// minute row — the accessibility labels say minute). `todaySets` gates −1:
    /// with nothing logged today there is nothing to take back.
    @ViewBuilder
    private func quickLogControls(_ ex: ExerciseDTO, todaySets: Int) -> some View {
        let isMin = ex.kind == .duration
        let unit = isMin ? "minute" : "rep"
        HStack(spacing: 6) {
            Button { removeOne(ex) } label: {
                Text("\u{2212}1")
            }
            .tactile(.secondary)
            .disabled(todaySets == 0)
            .accessibilityLabel("Remove 1 \(unit) of \(ex.name)")

            Button { quickLog(ex) } label: {
                Text("+1")
            }
            .tactile(.primary)
            .accessibilityLabel("Add 1 \(unit) of \(ex.name)")
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func statCell(_ ex: ExerciseDTO, label: String, reps: Int, holdSec: Int, cal: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(1.5)
                .foregroundStyle(theme.dim)
            let hasValue = ex.isIsometric ? holdSec > 0 : reps > 0
            Text(hasValue ? valueLabel(ex, reps: reps, holdSec: holdSec) : "—")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(hasValue ? theme.text : theme.dim)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: ex.isIsometric ? holdSec : reps)
            if ex.isIsometric, holdSec > 0, reps > 0 {
                // A hold row stores reps = 1, so the rep total is the hold count.
                // (holdSec > 0 skips legacy minute-logged rows on an isometric.)
                Text("\(reps) hold\(reps == 1 ? "" : "s")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
            if cal > 0 {
                Text("~\(Int(cal)) cal")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private func valueLabel(_ ex: ExerciseDTO, reps: Int, holdSec: Int) -> String {
        // Hold first: an isometric is also `.duration` kind, but only a hold
        // carries holdSeconds. A duration exercise stores minutes in reps.
        if ex.isIsometric { return formattedHoldDuration(holdSec) }
        if ex.kind == .duration { return "\(reps) min" }
        return "\(reps)"
    }

    // MARK: - Writes

    private func quickLog(_ exercise: ExerciseDTO) {
        // `reps` carries minutes for a duration exercise.
        let amount = 1
        // A fixed-load movement stamps the load it is done at, so a later edit
        // of the exercise's weight never re-reads this rep (nil for the rest).
        let load = exercise.fixedLoadLb(forRowWeight: nil, holdSeconds: nil)
        // The exercise's whole history BEFORE this row (the card's own query only
        // starts last Monday), so the new-best check doesn't depend on refresh timing.
        let rowsBefore = Repos.setHistory(ctx, userId: profile.id, exerciseId: exercise.id, limit: 100_000)
        // A per-set-weight lift has no fixed load: stamp the last weight ever used
        // for it — the value the rep counter pre-fills — else bodyweight (nil).
        let rowWeight = exercise.tracksPerSetWeight
            ? RepHistory.lastWeightLb(for: exercise, rows: rowsBefore)
            : load
        let cal = Repos.setCaloriesEstimate(
            exercise: exercise, reps: amount, holdSeconds: nil,
            bodyWeightLb: profile.weightLb, loadLb: load
        )
        let dto = WorkoutSetDTO(
            userId: profile.id,
            exerciseId: exercise.id,
            weightLb: rowWeight,
            reps: amount,
            caloriesEst: cal
        )
        guard Repos.addSet(ctx, dto) else { return }
        Task { @MainActor in
            ringGlow = true
            try? await Task.sleep(nanoseconds: 450_000_000)
            ringGlow = false
        }

        // One toast: a new best, else the weekly-reps note (once per kind per week),
        // else the plain "+1" confirmation.
        let system = unitSystem
        if let best = RepHistory.newBest(after: dto, exercise: exercise, rows: rowsBefore) {
            toasts.newBest(best) { ProgressFormat.weight($0, system: system) }
            return
        }
        if RepHistory.isRepExercise(exercise),
           toasts.weeklyReps(Repos.weeklyReps(ctx, userId: profile.id), profileId: profile.id) {
            return
        }

        let unit = exercise.kind == .duration
            ? "+\(amount) min"
            : "+\(amount) rep\(amount == 1 ? "" : "s")"
        let calStr = cal >= 1 ? " · ~\(Int(cal)) cal" : ""
        // A per-set-weight lift shows the weight it was stamped with.
        let weightStr = exercise.tracksPerSetWeight
            ? rowWeight.map { " · " + ProgressFormat.weight($0, system: system) } ?? ""
            : ""
        toasts.show(Toast(
            title: exercise.name,
            detail: unit + weightStr + calStr,
            accent: .win,
            symbol: "checkmark.seal.fill"
        ))
    }

    private func deleteExercise(_ ex: ExerciseDTO) {
        let deleted: Bool = withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            Repos.deleteExercise(ctx, id: ex.id)
        }
        guard deleted else { return }
        toasts.show(Toast(title: "\(ex.name) deleted",
                          detail: "Exercise and its sets removed.",
                          accent: .warn, symbol: "trash.fill"))
    }

    /// Inline −1: one rep (or minute) off today's newest set for this exercise.
    /// Success-only feedback (rule 9); a quiet light tap, no toast.
    private func removeOne(_ exercise: ExerciseDTO) {
        let removed: Bool = withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            Repos.removeOneFromToday(ctx, userId: profile.id, exerciseId: exercise.id,
                                     bodyWeightLb: profile.weightLb)
        }
        guard removed else { return }
        Haptics.tap()
    }
}
