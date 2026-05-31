// Inline quick-log for Circuit exercises (baby exercises and any user-added ones).
// No sets, no targets, no sheet. Tap the button right here — it saves immediately.
// Reps exercises get "+1" per tap. Duration exercises get "+1 min" and "+5 min".
// Header ring shows how many distinct exercises were logged today / total available.

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

    private var exercisesDoneToday: Int {
        myExercises.filter { todayReps(for: $0) > 0 }.count
    }

    private var completionPct: Double {
        guard !myExercises.isEmpty else { return 0 }
        return min(1, Double(exercisesDoneToday) / Double(myExercises.count))
    }

    private var todayTotalKcal: Double {
        let uid = profile.id
        return setModels
            .filter { $0.userId == uid && Dates.dayKey($0.timestamp) == todayKey }
            .reduce(0) { $0 + ($1.caloriesEst ?? 0) }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                header
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

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                ProgressRing(pct: completionPct, color: theme.accent, trackColor: theme.barBg, lineWidth: 7)
                VStack(spacing: 0) {
                    Text("\(exercisesDoneToday)")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                    Text("/\(myExercises.count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(theme.dim)
                }
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text("Movements")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                if todayTotalKcal > 0 {
                    Text("~\(Int(todayTotalKcal)) cal burned today")
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                } else {
                    Text("done today")
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                }
            }
            Spacer()
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
        Repos.addSet(ctx, dto)

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
}

// MARK: - Per-exercise row

private struct ExerciseRow: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO
    let todayCount: Int
    let onLog: (Int) -> Void

    @Environment(\.theme) private var theme
    @State private var showInfo = false

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

            Button { showInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.dim)
            }
            .tactile(.ghost)
            .sheet(isPresented: $showInfo) {
                ExerciseInfoSheet(
                    exercise: exercise,
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
    }
}

// MARK: - Exercise info sheet

private struct ExerciseInfoSheet: View {
    let exercise: ExerciseDTO
    let todayCount: Int
    let todayKcal: Double

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var hint: Movement.PostExerciseHint {
        Movement.postExerciseHint(for: exercise)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(exercise.name)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(theme.text)

                // Form & Safety — shown prominently for loaded movements
                if !hint.formCues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.shield.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.warn)
                            Text("Form & Safety")
                                .font(.caption).tracking(2).textCase(.uppercase)
                                .foregroundStyle(theme.dim)
                        }
                        ForEach(Array(hint.formCues.enumerated()), id: \.offset) { _, cue in
                            HStack(alignment: .top, spacing: 8) {
                                Text("·")
                                    .font(.callout)
                                    .foregroundStyle(theme.warn)
                                Text(cue)
                                    .font(.callout)
                                    .foregroundStyle(theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .background(theme.warn.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.warn.opacity(0.3), lineWidth: 1))
                }

                // Muscles worked
                infoBlock(
                    icon: "figure.strengthtraining.traditional",
                    title: "Muscles worked",
                    body: hint.musclesWorked.joined(separator: ", ")
                )

                // Today's activity
                if todayCount > 0 {
                    infoBlock(
                        icon: "flame.fill",
                        title: "Today",
                        body: exercise.kind == .duration
                            ? "\(todayCount) min · ~\(Int(todayKcal)) cal burned"
                            : "\(todayCount) reps · ~\(Int(todayKcal)) cal burned"
                    )
                }

                // Recovery nutrition
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.accent2)
                        Text("Recovery (within \(hint.windowMinutes) min · rest \(hint.recoveryHours)h)")
                            .font(.caption).tracking(2).textCase(.uppercase)
                            .foregroundStyle(theme.dim)
                    }
                    Text(hint.primaryNeed)
                        .font(.callout).foregroundStyle(theme.text)
                    Text("Try: \(hint.recoveryFoods.joined(separator: " · "))")
                        .font(.caption).italic()
                        .foregroundStyle(theme.dim)
                }
                .padding(14)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))

                if !hint.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(hint.citations.enumerated()), id: \.offset) { _, cite in
                            Text(cite)
                                .font(.caption2)
                                .foregroundStyle(theme.dim)
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func infoBlock(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent)
                Text(title.uppercased())
                    .font(.caption).tracking(2)
                    .foregroundStyle(theme.dim)
            }
            Text(body)
                .font(.callout)
                .foregroundStyle(theme.text)
        }
    }
}
