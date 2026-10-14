// Inline quick-log for Circuit exercises (baby exercises and any user-added ones).
// No sets, no targets, no sheet. Tap the button right here — it saves immediately.
// Reps exercises get "+1" per tap. Duration exercises get "+1 min" and "+5 min".
// Header ring shows real progress: distinct exercises logged today / total available.

import SwiftUI
import SwiftData

struct BabyExercisesCard: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var exerciseModels: [ExerciseModel]
    @Query private var setModels: [WorkoutSetModel]

    @State private var showAddMovement = false
    @State private var ringGlow: Bool = false
    @State private var reveal: CGFloat = 0

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        let dayStart = Calendar.current.startOfDay(for: Date())
        _exerciseModels = Query(filter: #Predicate { $0.profileId == uid })
        _setModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid && $0.timestamp >= dayStart },
            sort: \.timestamp, order: .reverse
        )
    }

    private var myExercises: [ExerciseDTO] {
        exerciseModels.map(\.snapshot)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var countsByExercise: [String: Int] {
        setModels.reduce(into: [:]) { acc, set in
            acc[set.exerciseId, default: 0] += set.reps
        }
    }

    private var exercisesDoneToday: Int {
        let counts = countsByExercise
        return myExercises.filter { (counts[$0.id] ?? 0) > 0 }.count
    }

    /// Real progress for the header ring: how much of your movement list you've
    /// touched today. Zero when there's nothing to log, so the ring reads empty
    /// instead of pretending to be complete.
    private var ringPct: Double {
        let total = myExercises.count
        guard total > 0 else { return 0 }
        return Double(exercisesDoneToday) / Double(total)
    }

    private var todayTotalKcal: Double {
        setModels.reduce(0) { $0 + ($1.caloriesEst ?? 0) }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                header
                let exercises = myExercises
                if exercises.isEmpty {
                    // A labelled button beats "tap the + above" pointing at a
                    // 14pt glyph for someone opening this tab the first time.
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No movements yet. Add one, then log it with a single tap.")
                            .font(.callout).foregroundStyle(theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { showAddMovement = true } label: {
                            Label("Add your first movement", systemImage: "plus")
                        }
                        .tactile(.secondary, fullWidth: true)
                    }
                } else {
                    let counts = countsByExercise
                    let lastId = exercises.last?.id
                    ForEach(exercises) { exercise in
                        ExerciseRow(
                            profile: profile,
                            exercise: exercise,
                            todayCount: counts[exercise.id] ?? 0,
                            onLog: { amount in logActivity(exercise: exercise, amount: amount) },
                            onUndo: { undoLastSet(for: exercise) },
                            onDelete: { deleteExercise(exercise) }
                        )
                        if exercise.id != lastId {
                            Divider().background(theme.line)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddMovement) {
            AddExerciseSheet(mode: profile.mode) { draft in
                guard Repos.createExercise(
                    ctx, profileId: profile.id, name: draft.name,
                    defaultRepsBottom: 1, defaultRepsTop: 20,
                    tracksWeight: draft.tracksWeight,
                    loadLb: draft.loadLb,
                    kind: draft.kind
                ) != nil else { return }
                toasts.show(Toast(title: draft.name, detail: "Movement added", accent: .win, symbol: "plus.circle.fill"))
            }
            .themed(theme.mode)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressRing(pct: ringPct * Double(reveal), color: theme.accent,
                         trackColor: theme.barBg, lineWidth: 7)
                .shadow(color: theme.accent.opacity(ringGlow ? 0.55 : 0), radius: ringGlow ? 10 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: ringGlow)
                .frame(width: 54, height: 54)
                .overlay {
                    Text("\(exercisesDoneToday)/\(myExercises.count)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                        .contentTransition(.numericText())
                }
                .revealOnAppear($reveal)
                .accessibilityLabel("\(exercisesDoneToday) of \(myExercises.count) movements logged today")

            VStack(alignment: .leading, spacing: 2) {
                Text("Movements")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                if todayTotalKcal > 0 {
                    Text("~\(Int(todayTotalKcal)) cal burned today")
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                } else if exercisesDoneToday > 0 {
                    Text("\(exercisesDoneToday) logged today")
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                } else {
                    Text("tap + to log reps")
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                }
            }
            Spacer()
            Button { showAddMovement = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
            }
            .tactile(.ghost)
            .accessibilityLabel("Add movement")
        }
    }

    private func logActivity(exercise: ExerciseDTO, amount: Int) {
        let load = exercise.loadLb
        let cal: Double
        if exercise.kind == .duration {
            cal = CalorieEstimator.caloriesForDuration(
                minutes: Double(amount), loadLb: load, bodyWeightLb: profile.weightLb
            )
        } else {
            cal = CalorieEstimator.caloriesForReps(
                reps: amount, loadLb: load, bodyWeightLb: profile.weightLb
            )
        }

        let dto = WorkoutSetDTO(
            userId: profile.id,
            exerciseId: exercise.id,
            weightLb: nil,
            reps: amount,
            caloriesEst: cal
        )
        guard Repos.addSet(ctx, dto) else { return }
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

    private func undoLastSet(for exercise: ExerciseDTO) {
        let exId = exercise.id
        // Find the most recently logged set today for this exercise (query already scoped to profile)
        guard let latest = setModels.first(where: { $0.exerciseId == exId }) else { return }
        guard Repos.deleteSet(ctx, id: latest.id) else { return }
        toasts.show(Toast(title: "Undone", detail: "\(exercise.name) · last rep removed",
                          accent: .warn, symbol: "arrow.uturn.backward"))
    }

    private func deleteExercise(_ exercise: ExerciseDTO) {
        guard Repos.deleteExercise(ctx, id: exercise.id) else { return }
        toasts.show(Toast(title: "Removed", detail: "\(exercise.name) deleted",
                          accent: .warn, symbol: "trash"))
    }
}

// MARK: - Per-exercise row

private struct ExerciseRow: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO
    let todayCount: Int
    let onLog: (Int) -> Void
    let onUndo: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme
    @State private var showInfo = false
    @State private var showSets = false
    @State private var confirmDelete = false

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    private var loadLabel: String {
        guard let lb = exercise.loadLb else { return "" }
        return " · \(Units.formatWeightWithUnit(lb: lb, system: unitSystem, decimals: 0))"
    }

    private var countLabel: String {
        if exercise.kind == .duration {
            return todayCount > 0 ? "\(todayCount) min today" : "not logged yet"
        } else {
            return todayCount > 0 ? "\(todayCount) reps today" : "not logged yet"
        }
    }

    private var todayKcal: Double {
        guard todayCount > 0 else { return 0 }
        if exercise.kind == .duration {
            return CalorieEstimator.caloriesForDuration(
                minutes: Double(todayCount), loadLb: exercise.loadLb, bodyWeightLb: profile.weightLb
            )
        } else {
            return CalorieEstimator.caloriesForReps(
                reps: todayCount, loadLb: exercise.loadLb, bodyWeightLb: profile.weightLb
            )
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(countLabel + loadLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.dim)
            }
            Spacer(minLength: 0)

            if todayCount > 0 {
                Button { onUndo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.dim)
                }
                .tactile(.ghost)
                .accessibilityLabel("Undo last \(exercise.name)")

                // Undo only removes the last tap. This opens today's individual
                // logs so a wrong count can be corrected instead of re-tapped —
                // the same sheet Build uses, never a second set editor.
                Button { showSets = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.dim)
                }
                .tactile(.ghost)
                .accessibilityLabel("Edit today's \(exercise.name) logs")
            }

            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.dim)
            }
            .tactile(.ghost)
            .sheet(isPresented: $showInfo) {
                ExerciseInfoSheet(
                    exercise: exercise,
                    profile: profile,
                    todayCount: todayCount,
                    todayKcal: todayKcal
                )
                .themed(theme.mode)
            }

            if exercise.kind == .duration {
                HStack(spacing: 6) {
                    Button { onLog(1) } label: { Text("+1 min") }
                        .tactile(.bump)
                    Button { onLog(5) } label: { Text("+5 min") }
                        .tactile(.bump)
                }
            } else {
                Button { onLog(1) } label: { Text("+1") }
                    .tactile(.secondary)
            }
        }
        .padding(.vertical, 4)
        // Attached to the row, not to the clock button: deleting the last set
        // from inside the sheet hides that button, which would yank the sheet
        // out from under the user mid-edit.
        .sheet(isPresented: $showSets) {
            SetHistorySheet(profile: profile, exercise: exercise)
                .themed(theme.mode)
        }
        // No .swipeActions here: these rows live in a Card's VStack, not a List,
        // where that modifier is a no-op — it looked like a delete affordance and
        // wasn't one. Removing a movement is a confirmed action in the context
        // menu below, and in the "Delete movement" button inside the sets sheet.
        .contextMenu {
            if todayCount > 0 {
                Button { showSets = true } label: {
                    Label("Edit today's logs", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Remove movement", systemImage: "trash")
            }
        }
        .confirmationDialog("Remove \(exercise.name)?",
                            isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Remove movement and all its logs", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
