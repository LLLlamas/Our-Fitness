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

    private var tracksWeight: Bool { exercise.category == .compound || exercise.category == .isolation }

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
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(theme.text)
            if let r = exercise.defaultRepRange, r.count == 2 {
                Text("Target: \(r[0])–\(r[1]) reps")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
            }
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
        let load = exercise.loadLb ?? (tracksWeight ? weight : nil)
        let kcal = CalorieEstimator.caloriesForReps(
            reps: reps,
            loadLb: load,
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
            detail: weight.map { "\(Int($0)) lb × \(reps)" } ?? "\(reps) reps",
            accent: .win,
            symbol: "checkmark.seal.fill"
        ))
        reps = 0
    }
}
