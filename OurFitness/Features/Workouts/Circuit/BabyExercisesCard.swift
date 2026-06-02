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

    @State private var showAddMovement = false
    @State private var ringPct: Double = 0
    @State private var ringGlow: Bool = false
    @State private var ringTrigger: Int = 0

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
                            onLog: { amount in logActivity(exercise: exercise, amount: amount) },
                            onUndo: { undoLastSet(for: exercise) },
                            onDelete: { deleteExercise(exercise) }
                        )
                        if exercise.id != myExercises.last?.id {
                            Divider().background(theme.line)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddMovement) {
            AddCircuitMovementSheet(profileId: profile.id) { name, kind, loadLb in
                Repos.createExercise(
                    ctx, profileId: profile.id, name: name,
                    defaultRepsBottom: 1, defaultRepsTop: 20,
                    tracksWeight: loadLb != nil,
                    loadLb: loadLb,
                    kind: kind
                )
                Haptics.bump()
                toasts.show(Toast(title: name, detail: "Movement added", accent: .win, symbol: "plus.circle.fill"))
            }
            .themed(theme.mode)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ProgressRing(pct: ringPct, color: theme.accent, trackColor: theme.barBg, lineWidth: 7)
                .shadow(color: theme.accent.opacity(ringGlow ? 0.55 : 0), radius: ringGlow ? 10 : 0)
                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: ringGlow)
                .frame(width: 54, height: 54)
                .task(id: ringTrigger) {
                    ringPct = 0
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    withAnimation(.spring(response: 0.65, dampingFraction: 0.72)) {
                        ringPct = 1.0
                    }
                }

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
        Repos.addSet(ctx, dto)
        ringTrigger += 1
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
        let uid = profile.id
        let exId = exercise.id
        let today = Dates.dayKey()
        // Find the most recently logged set today for this exercise
        let todaySets = setModels
            .filter { $0.exerciseId == exId && $0.userId == uid && Dates.dayKey($0.timestamp) == today }
            .sorted { $0.timestamp > $1.timestamp }
        guard let latest = todaySets.first else { return }
        Repos.deleteSet(ctx, id: latest.id)
        Haptics.warn()
        toasts.show(Toast(title: "Undone", detail: "\(exercise.name) · last rep removed",
                          accent: .warn, symbol: "arrow.uturn.backward"))
    }

    private func deleteExercise(_ exercise: ExerciseDTO) {
        Repos.deleteExercise(ctx, id: exercise.id)
        Haptics.warn()
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
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Remove movement", systemImage: "trash")
            }
        }
    }
}

// MARK: - Exercise info sheet

private struct ExerciseInfoSheet: View {
    let exercise: ExerciseDTO
    let todayCount: Int
    let todayKcal: Double

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    // On-device AI fills in muscles + benefits for custom movements (not the
    // seeded parenting lifts and not curated strength exercises).
    @State private var ai: GeneratedExerciseInsight?
    @State private var aiLoading = false

    private var hint: Movement.PostExerciseHint {
        Movement.postExerciseHint(for: exercise)
    }

    private var canUseAI: Bool {
        !Movement.hasNamedHint(for: exercise) && !ExerciseInfo.hasCuratedMeta(for: exercise)
    }
    private var usingAI: Bool { ai != nil }

    private var musclesText: String {
        if let ai, !ai.primaryMuscles.isEmpty {
            let all = ai.primaryMuscles + ai.secondaryMuscles
            return ExerciseInfo.plainMuscleList(all, separator: ", ")
        }
        return ExerciseInfo.plainMuscleList(hint.musclesWorked, separator: ", ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(exercise.name)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(theme.text)

                if aiLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Generating insights with Apple Intelligence…")
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                }

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
                    body: musclesText
                )

                // What it does (AI-generated for custom movements)
                if let ai, !ai.benefits.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11)).foregroundStyle(theme.accent)
                            Text("WHAT IT DOES")
                                .font(.caption).tracking(2).foregroundStyle(theme.dim)
                        }
                        ForEach(Array(ai.benefits.enumerated()), id: \.offset) { _, b in
                            HStack(alignment: .top, spacing: 8) {
                                Text("·").foregroundStyle(theme.accent)
                                Text(b).font(.callout).foregroundStyle(theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

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

                if usingAI {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10)).foregroundStyle(theme.accent)
                        Text("Muscles and benefits for this custom movement were generated on-device by Apple Intelligence. General fitness guidance, not medical advice.")
                            .font(.caption2).foregroundStyle(theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .presentationDragIndicator(.visible)
        .task(id: exercise.id) { await loadAIIfNeeded() }
    }

    private func loadAIIfNeeded() async {
        guard canUseAI, ai == nil else { return }
        if let cached = ExerciseInsightService.shared.cached(for: exercise) {
            ai = cached
            return
        }
        guard ExerciseInsightService.shared.isAvailable else { return }
        aiLoading = true
        ai = await ExerciseInsightService.shared.insight(for: exercise)
        aiLoading = false
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

// MARK: - Add movement sheet

private struct AddCircuitMovementSheet: View {
    let profileId: UUID
    let onSave: (String, ExerciseKind, Double?) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: ExerciseKind = .reps
    @State private var loadRaw = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var loadFocused: Bool

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    private var loadLb: Double? {
        // Field is in the active unit; persist canonical lb.
        guard !loadRaw.isEmpty, let v = Double(loadRaw), v > 0 else { return nil }
        return Units.weightToLb(v, system: unitSystem)
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("add movement.")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("CIRCUIT · QUICK-LOG")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("NAME")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                    TextField("e.g. Carried Baby", text: $name)
                        .focused($nameFocused)
                        .padding(12)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                        .foregroundStyle(theme.text)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { nameFocused = false; loadFocused = false }
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("TYPE")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                    Picker("Type", selection: $kind) {
                        Text("Reps").tag(ExerciseKind.reps)
                        Text("Duration (min)").tag(ExerciseKind.duration)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("LOAD (\(Units.weightUnit(unitSystem).uppercased())) · OPTIONAL")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                    TextField(unitSystem == .metric ? "e.g. 14" : "e.g. 30", text: $loadRaw)
                        .keyboardType(.decimalPad)
                        .focused($loadFocused)
                        .padding(12)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                        .foregroundStyle(theme.text)
                }

                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed, kind, loadLb)
                    dismiss()
                } label: {
                    Text("Add movement").frame(maxWidth: .infinity)
                }
                .tactile(.primary)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .presentationDragIndicator(.visible)
        .onAppear { nameFocused = true }
    }
}
