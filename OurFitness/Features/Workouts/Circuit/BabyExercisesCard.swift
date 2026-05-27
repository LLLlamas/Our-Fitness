// Inline quick-log for Circuit exercises (baby exercises and any user-added ones).
// No sets, no targets, no sheet. Tap the button right here — it saves immediately.
// Reps exercises get "+1" per tap. Duration exercises get "+1 min" and "+5 min".
// Today's running total is shown below each exercise name.

import SwiftUI
import SwiftData

struct BabyExercisesCard: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var exerciseModels: [ExerciseModel]
    @Query private var setModels: [WorkoutSetModel]

    private var myExercises: [ExerciseDTO] {
        let id = profile.id
        return exerciseModels.map(\.snapshot)
            .filter { $0.profileId == id }
            .sorted { $0.name < $1.name }
    }

    private var todayKey: String { Dates.dayKey() }

    private func todayReps(for exercise: ExerciseDTO) -> Int {
        let exId = exercise.id
        let uid = profile.id
        return setModels
            .filter { $0.exerciseId == exId && $0.userId == uid
                && Dates.dayKey($0.timestamp) == todayKey }
            .reduce(0) { $0 + $1.reps }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Movements")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)

                if myExercises.isEmpty {
                    Text("No exercises yet. Head to Settings or ask to add one.")
                        .font(.callout).foregroundStyle(theme.dim)
                } else {
                    ForEach(myExercises) { exercise in
                        ExerciseRow(
                            profile: profile,
                            exercise: exercise,
                            todayCount: todayReps(for: exercise),
                            onLog: { amount in logActivity(exercise: exercise, amount: amount) }
                        )
                        if exercise.id != myExercises.last?.id {
                            Divider().background(theme.line)
                        }
                    }
                }
            }
        }
    }

    private func logActivity(exercise: ExerciseDTO, amount: Int) {
        let load = exercise.loadLb
        let kcal: Double
        if exercise.kind == .duration {
            kcal = CalorieEstimator.caloriesForDuration(
                minutes: Double(amount), loadLb: load, bodyWeightLb: profile.weightLb
            )
        } else {
            kcal = CalorieEstimator.caloriesForReps(
                reps: amount, loadLb: load, bodyWeightLb: profile.weightLb
            )
        }

        let dto = WorkoutSetDTO(
            userId: profile.id,
            exerciseId: exercise.id,
            weightLb: nil,
            reps: amount,
            caloriesEst: kcal
        )
        Repos.addSet(ctx, dto)

        let detail = exercise.kind == .duration
            ? "+\(amount) min"
            : "+\(amount) rep\(amount == 1 ? "" : "s")"
        toasts.show(Toast(
            title: exercise.name,
            detail: detail,
            accent: .win,
            symbol: "checkmark.seal.fill"
        ))
    }
}

// MARK: - Per-exercise row

private struct ExerciseRow: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO
    let todayCount: Int
    let onLog: (Int) -> Void

    @Environment(\.theme) private var theme

    private var loadLabel: String {
        guard let lb = exercise.loadLb else { return "" }
        return " · \(Int(lb)) lb"
    }

    private var countLabel: String {
        if exercise.kind == .duration {
            return todayCount > 0 ? "\(todayCount) min today" : "not logged yet"
        } else {
            return todayCount > 0 ? "\(todayCount) reps today" : "not logged yet"
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
    }
}
