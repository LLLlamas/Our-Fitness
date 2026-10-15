// The Train tab's ONE exercise list — every exercise the profile owns, lifts,
// holds and quick-log movements alike, each rendered exactly once.
//
// Header ring: distinct exercises logged today / total, plus today's burn.
// Each row picks its controls from the exercise's SHAPE, never from the goal:
//   • isometric            → tap opens the hold timer
//   • tracks per-set weight → tap opens the rep counter (with its weight field)
//   • one-tap loggable      → inline +1 (or +1 min) with undo; tapping the
//                             row still opens the rep counter for bigger sets.
//                             Undo removes only a set THIS +1 created (tracked
//                             in view state) — never a rep-counter set; those
//                             are edited/deleted via the clock → SetHistorySheet
// Every row also carries the clock (→ SetHistorySheet, the one set editor) and
// ⓘ (→ ExerciseInfoSheet). Press-and-hold on the row body asks to delete the
// exercise (confirmed); SetHistorySheet's "Delete exercise" is the explicit path.
// The hold rides on the row-body buttons only, so +1 / undo / clock / ⓘ keep
// their plain taps.
//
// Calories shown here are the stored `caloriesEst` of the logged sets; every
// write estimates through `Repos.setCaloriesEstimate`, so there is no second
// copy of the MET math in this file.

import SwiftUI
import SwiftData

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
    /// Set ids the inline +1 wrote this session, per exercise, newest last —
    /// the only sets the row's undo may remove.
    @State private var quickLoggedSetIds: [String: [UUID]] = [:]
    /// Set by a press-and-hold on a row; drives the delete confirmation. While
    /// it's non-nil the row-body tap is ignored, so lifting the finger after
    /// the hold doesn't also open the rep counter.
    @State private var pendingDelete: ExerciseDTO?

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _exerciseModels = Query(
            filter: #Predicate<ExerciseModel> { $0.profileId == uid },
            sort: \.name, order: .forward
        )
        // Today + yesterday: the rows show both days, older sets live in
        // Progress › Training history.
        let cutoff = Dates.startOfYesterday()
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
        let doneToday = exercises.filter { (stats[$0.id]?.todaySets ?? 0) > 0 }.count
        let todayCal = exercises.reduce(0.0) { $0 + (stats[$1.id]?.todayCal ?? 0) }

        Card {
            VStack(alignment: .leading, spacing: 14) {
                header(done: doneToday, total: exercises.count, todayCal: todayCal)

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
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "exercise")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { ex in
            Button("Delete exercise and all its sets", role: .destructive) { deleteExercise(ex) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the exercise and every set logged for it.")
        }
    }

    /// Press-and-hold on a row body: a light tick at the threshold (no toast
    /// fires here), then the confirmation.
    private func requestDelete(_ ex: ExerciseDTO) {
        Haptics.tap()
        pendingDelete = ex
    }

    // MARK: - Header

    @ViewBuilder
    private func header(done: Int, total: Int, todayCal: Double) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Real progress: how much of your list you've touched today. Zero
            // when there's nothing to log, so the ring reads empty instead of
            // pretending to be complete.
            let pct = total > 0 ? Double(done) / Double(total) : 0
            ProgressRing(pct: pct * Double(reveal), color: theme.accent,
                         trackColor: theme.barBg, lineWidth: 7)
                .shadow(color: theme.accent.opacity(ringGlow ? 0.55 : 0), radius: ringGlow ? 10 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: ringGlow)
                .frame(width: 54, height: 54)
                .overlay {
                    Text("\(done)/\(total)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .contentTransition(.numericText())
                }
                .revealOnAppear($reveal)
                .accessibilityLabel("\(done) of \(total) exercises logged today")

            VStack(alignment: .leading, spacing: 2) {
                Text("Exercises")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                if todayCal > 0 {
                    Text("~\(Int(todayCal)) cal burned today")
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                } else if done > 0 {
                    Text("\(done) logged today")
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                } else {
                    Text("tap an exercise to log it")
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

                if ex.isOneTapLoggable {
                    quickLogControls(ex)
                }
            }
        }
        .padding(.vertical, 4)
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

    @ViewBuilder
    private func quickLogControls(_ ex: ExerciseDTO) -> some View {
        HStack(spacing: 6) {
            if undoableQuickLogId(for: ex) != nil {
                Button { undoLastSet(for: ex) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.dim)
                }
                .tactile(.ghost)
                .accessibilityLabel("Undo last \(ex.name)")
            }
            Button { quickLog(ex) } label: {
                Text(ex.kind == .duration ? "+1 min" : "+1")
            }
            .tactile(.secondary)
            .accessibilityLabel(ex.kind == .duration ? "Log 1 minute of \(ex.name)" : "Log 1 \(ex.name)")
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
        let cal = Repos.setCaloriesEstimate(
            exercise: exercise, reps: amount, holdSeconds: nil,
            bodyWeightLb: profile.weightLb
        )
        let dto = WorkoutSetDTO(
            userId: profile.id,
            exerciseId: exercise.id,
            weightLb: nil,
            reps: amount,
            caloriesEst: cal
        )
        guard Repos.addSet(ctx, dto) else { return }
        quickLoggedSetIds[exercise.id, default: []].append(dto.id)
        Task { @MainActor in
            ringGlow = true
            try? await Task.sleep(nanoseconds: 450_000_000)
            ringGlow = false
        }

        let unit = exercise.kind == .duration
            ? "+\(amount) min"
            : "+\(amount) rep\(amount == 1 ? "" : "s")"
        let calStr = cal >= 1 ? " · ~\(Int(cal)) cal" : ""
        toasts.show(Toast(
            title: exercise.name,
            detail: unit + calStr,
            accent: .win,
            symbol: "checkmark.seal.fill"
        ))
    }

    private func deleteExercise(_ ex: ExerciseDTO) {
        let deleted: Bool = withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            Repos.deleteExercise(ctx, id: ex.id)
        }
        guard deleted else { return }
        quickLoggedSetIds[ex.id] = nil
        toasts.show(Toast(title: "\(ex.name) deleted",
                          detail: "Exercise and its sets removed.",
                          accent: .warn, symbol: "trash.fill"))
    }

    /// Newest +1 set for this exercise that still exists today. Sets deleted
    /// in SetHistorySheet (or yesterday's, after midnight) are skipped.
    private func undoableQuickLogId(for exercise: ExerciseDTO) -> UUID? {
        guard let ids = quickLoggedSetIds[exercise.id], !ids.isEmpty else { return nil }
        let todayStart = Calendar.current.startOfDay(for: Date())
        let live = Set(setModels.lazy
            .filter { $0.exerciseId == exercise.id && $0.timestamp >= todayStart }
            .map(\.id))
        return ids.last(where: { live.contains($0) })
    }

    private func undoLastSet(for exercise: ExerciseDTO) {
        guard let id = undoableQuickLogId(for: exercise) else { return }
        guard Repos.deleteSet(ctx, id: id) else { return }
        quickLoggedSetIds[exercise.id]?.removeAll { $0 == id }
        toasts.show(Toast(title: "Undone", detail: "\(exercise.name) · last log removed",
                          accent: .warn, symbol: "arrow.uturn.backward"))
    }
}
