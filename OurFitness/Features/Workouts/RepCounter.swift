// Friction-free rep counter (Build mode). Tap +1 per rep, Save Set commits a WorkoutSet.
// For isometric exercises, shows a countdown timer instead.

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

// MARK: - Rep counter (non-isometric)

private struct RepCounterView: View {
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
    @FocusState private var weightFocused: Bool

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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
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
            Text("Weight lifted (lb)")
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            TextField("", text: $weightStr)
                .keyboardType(.decimalPad)
                .padding(10).background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
                .font(.system(.title3, design: .monospaced))
                .focused($weightFocused)
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

// MARK: - Isometric timer

private struct IsometricTimerView: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var pickedSeconds: Int = 60
    @State private var secondsRemaining: Int? = nil
    @State private var holdsThisSession: Int = 0
    @State private var totalSecSession: Int = 0
    @State private var showInfo = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var isRunning: Bool { secondsRemaining != nil }
    private var info: ExerciseInfo.Meta { ExerciseInfo.meta(for: exercise) }

    var body: some View {
        VStack(spacing: 18) {
            header
            if isRunning {
                countdownDisplay
                cancelButton
            } else {
                pickerSection
                startButton
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
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .onReceive(ticker) { _ in tick() }
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
            Text("Isometric · \(info.muscleGroups.first ?? "Core")")
                .font(.system(size: 12, weight: .medium)).tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(theme.accent)
            Text("\(holdsThisSession) hold\(holdsThisSession == 1 ? "" : "s") this session")
                .font(.caption).foregroundStyle(theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var countdownDisplay: some View {
        let secs = secondsRemaining ?? 0
        VStack(spacing: 4) {
            AnimatedNumber(
                Double(secs),
                font: .system(size: 120, weight: .semibold),
                color: secs <= 5 ? Color.orange : theme.accent
            )
            Text("seconds remaining")
                .font(.caption).tracking(1)
                .foregroundStyle(theme.dim)
        }
    }

    @ViewBuilder
    private var pickerSection: some View {
        VStack(spacing: 8) {
            Text("Set hold duration".uppercased())
                .font(.system(size: 10)).tracking(2)
                .foregroundStyle(theme.dim)
            Picker("Duration", selection: $pickedSeconds) {
                ForEach(Array(stride(from: 5, through: 300, by: 5)), id: \.self) { s in
                    Text(shortDurationLabel(s)).tag(s)
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
            secondsRemaining = pickedSeconds
            Haptics.bump()
        } label: {
            Text("Start Hold")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 88)
        }
        .tactile(.primary, fullWidth: true)
    }

    @ViewBuilder
    private var cancelButton: some View {
        Button {
            secondsRemaining = nil
            Haptics.warn()
        } label: {
            Text("Cancel")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 88)
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
                Text(holdDurationLabel(totalSecSession))
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
        guard let r = secondsRemaining else { return }
        if r <= 1 {
            completeHold()
        } else {
            secondsRemaining = r - 1
        }
    }

    private func completeHold() {
        let secs = pickedSeconds
        secondsRemaining = nil
        holdsThisSession += 1
        totalSecSession += secs
        let kcal = CalorieEstimator.caloriesForIsometric(
            seconds: Double(secs),
            met: info.met,
            bodyWeightLb: profile.weightLb
        )
        let dto = WorkoutSetDTO(
            userId: profile.id,
            exerciseId: exercise.id,
            reps: 1,
            caloriesEst: kcal,
            holdSeconds: secs
        )
        Repos.addSet(ctx, dto)
        Haptics.success()
        toasts.show(Toast(
            title: "Hold logged",
            detail: "\(shortDurationLabel(secs)) · ~\(Int(kcal)) cal",
            accent: .win,
            symbol: "checkmark.seal.fill"
        ))
    }

    private func shortDurationLabel(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60; let r = s % 60
        return r > 0 ? "\(m)m \(r)s" : "\(m)m"
    }

    private func holdDurationLabel(_ s: Int) -> String {
        if s < 90 { return "\(s)s" }
        if s < 4200 {
            let m = s / 60; let r = s % 60
            return r > 0 ? "\(m)m \(r)s" : "\(m)m"
        }
        let h = s / 3600; let m = (s % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}

// MARK: - Exercise info sheet (Build mode)

struct BuildExerciseInfoSheet: View {
    let exercise: ExerciseDTO
    let profile: ProfileDTO

    @Environment(\.theme) private var theme

    private var info: ExerciseInfo.Meta { ExerciseInfo.meta(for: exercise) }

    private var sampleCalLabel: String {
        if exercise.isIsometric {
            let cal30 = CalorieEstimator.caloriesForIsometric(seconds: 30, met: info.met, bodyWeightLb: profile.weightLb)
            let cal60 = CalorieEstimator.caloriesForIsometric(seconds: 60, met: info.met, bodyWeightLb: profile.weightLb)
            return "~\(Int(cal30)) cal / 30s · ~\(Int(cal60)) cal / 60s at your weight"
        }
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.accent.opacity(0.25), lineWidth: 1))
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
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}
