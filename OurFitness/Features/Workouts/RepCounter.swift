// Friction-free rep counter. Tap +1 per rep, Save Set commits a WorkoutSet.
// Big haptic per tap, success haptic on save. Used by BuildWorkoutsView.

import SwiftUI
import SwiftData

// MARK: - Sheet

struct RepCounterSheet: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var reps: Int = 0
    @State private var weightStr: String = ""
    @State private var setsLogged: Int = 0
    @State private var showInfo = false

    private var tracksWeight: Bool { exercise.category == .compound || exercise.category == .isolation }
    private var info: ExerciseInfo.Meta { ExerciseInfo.meta(for: exercise) }

    var body: some View {
        VStack(spacing: 18) {
            header
            counterDisplay
            tapButton
            if tracksWeight {
                weightField
            }
            actionRow
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .sheet(isPresented: $showInfo) {
            BuildExerciseInfoSheet(exercise: exercise, profile: profile)
                .themed(theme.mode)
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(exercise.name)
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
            // Primary muscles
            Text(info.muscleGroups.prefix(3).joined(separator: " · "))
                .font(.system(size: 12, weight: .medium)).tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(theme.accent)
            Text("\(setsLogged) set\(setsLogged == 1 ? "" : "s") this session")
                .font(.caption).foregroundStyle(theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var counterDisplay: some View {
        AnimatedNumber(
            Double(reps),
            font: .system(size: 120, weight: .semibold),
            color: theme.accent
        )
    }

    @ViewBuilder
    private var tapButton: some View {
        Button {
            reps += 1
            Haptics.tap()
        } label: {
            Text("+1 rep")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 88)
        }
        .tactile(.primary, fullWidth: true)
    }

    @ViewBuilder
    private var weightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weight (lb)")
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            TextField("", text: $weightStr)
                .keyboardType(.decimalPad)
                .padding(10).background(theme.card)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
                .font(.system(.title3, design: .monospaced))
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                reps = 0
                Haptics.warn()
            } label: {
                Text("Clear")
            }
            .tactile(.secondary)

            Button {
                saveSet()
            } label: {
                Text("Save Set")
            }
            .tactile(.primary, fill: theme.ok)
            .disabled(reps == 0)
            .opacity(reps == 0 ? 0.5 : 1)

            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .tactile(.ghost)
        }
    }

    private func saveSet() {
        let weight = Double(weightStr)
        // Use exercise-specific MET from ExerciseInfo for accurate per-exercise calorie math.
        let kcal = CalorieEstimator.caloriesForReps(
            reps: reps,
            exercise: exercise,
            bodyWeightLb: profile.weightLb
        )
        let dto = WorkoutSetDTO(
            userId: profile.id,
            exerciseId: exercise.id,
            weightLb: tracksWeight ? weight : nil,
            reps: reps,
            caloriesEst: kcal
        )
        Repos.addSet(ctx, dto)
        setsLogged += 1
        toasts.show(Toast(
            title: "Set saved",
            detail: weight.map { "\(Int($0)) lb × \(reps)" } ?? "\(reps) reps · ~\(Int(kcal)) cal",
            accent: .win,
            symbol: "checkmark.seal.fill"
        ))
        reps = 0
    }
}

// MARK: - Exercise info sheet (Build mode)

struct BuildExerciseInfoSheet: View {
    let exercise: ExerciseDTO
    let profile: ProfileDTO

    @Environment(\.theme) private var theme

    private var info: ExerciseInfo.Meta { ExerciseInfo.meta(for: exercise) }

    private var sampleCalLabel: String {
        let reps10 = CalorieEstimator.caloriesForReps(reps: 10, exercise: exercise, bodyWeightLb: profile.weightLb)
        return "~\(Int(reps10)) cal per 10 reps at your weight"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name.lowercased() + ".")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text(sampleCalLabel)
                        .font(.system(size: 11, weight: .medium)).tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                }

                muscleSection
                benefitsSection
                recoverySection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var muscleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Muscles worked")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            Text(info.muscleGroups.joined(separator: " · "))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.text)
            if !info.secondaryMuscles.isEmpty {
                Text("Also: \(info.secondaryMuscles.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(theme.dim)
            }
        }
        .padding(12)
        .background(theme.card)
        .overlay(Rectangle().stroke(theme.accent.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What it does")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            ForEach(Array(info.benefits.enumerated()), id: \.offset) { _, b in
                HStack(alignment: .top, spacing: 8) {
                    Text("·")
                        .foregroundStyle(theme.accent)
                    Text(b)
                        .font(.callout)
                        .foregroundStyle(theme.text)
                }
            }
        }
    }

    @ViewBuilder
    private var recoverySection: some View {
        let hint = Movement.postExerciseHint(for: exercise)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill").font(.system(size: 11)).foregroundStyle(theme.accent)
                Text("Recovery · rest \(hint.recoveryHours)h")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
            }
            Text("\(hint.primaryNeed) within \(hint.windowMinutes) min.")
                .font(.caption).foregroundStyle(theme.text)
            Text("Try: \(hint.recoveryFoods.joined(separator: " · "))")
                .font(.caption).italic().foregroundStyle(theme.dim)
        }
        .padding(12)
        .background(theme.card)
        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
    }
}
