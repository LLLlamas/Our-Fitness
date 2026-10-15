import SwiftUI
import SwiftData

// MARK: - Train tab

/// The Train tab root — the same tab for every profile: live sessions, the one
/// exercise list (`ExercisesCard`), Pilates, then the "what should I work on?"
/// discovery prompt. The fitness goal only tilts the suggestion ranking.
struct WorkoutsView: View {
    let profile: ProfileDTO

    @Environment(\.theme) private var theme

    // Profile-scoped at the query level — only used so the suggestion sheet can
    // mark picks the user already has as "Added".
    @Query private var exerciseModels: [ExerciseModel]

    @State private var showGoalSheet = false

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _exerciseModels = Query(filter: #Predicate<ExerciseModel> { $0.profileId == uid })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Train")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Live sessions, your exercises, and Pilates — log it, watch the numbers move.")
                    .font(.callout).foregroundStyle(theme.dim)

                LiveSessionCard(profile: profile)

                // Logging what's already on your list is the job you open this tab
                // for, so it sits above the "what should I work on?" discovery
                // prompt rather than below it.
                ExercisesCard(profile: profile)
                Card { PilatesCard(profile: profile) }

                workoutSuggestionButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .scrollHapticTicks()
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showGoalSheet) {
            WorkoutGoalSheet(profile: profile,
                             existingNames: Set(exerciseModels.map { $0.name.lowercased() }))
        }
    }

    // "What do you want to work on?" — AI (or research-matcher fallback) suggests
    // exercises for a free-text goal, grounded in the curated ExerciseInfo library.
    @ViewBuilder
    private var workoutSuggestionButton: some View {
        Button { showGoalSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What do you want to work on?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text("Get exercise picks for your goal")
                        .font(.caption).foregroundStyle(theme.dim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.dim)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
        }
        .tactile(.ghost)
    }
}

// MARK: - Shared duration formatter

/// One hold/duration label for the Train tab (`WorkoutsView` stats cells and
/// `RepCounter`'s isometric session summary). Seconds under 90 stay seconds,
/// then minutes, then hours — never add a second copy of this.
func formattedHoldDuration(_ seconds: Int) -> String {
    if seconds < 90 { return "\(seconds)s" }
    if seconds < 4200 {
        let m = seconds / 60; let s = seconds % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }
    let h = seconds / 3600; let m = (seconds % 3600) / 60
    return m > 0 ? "\(h)h \(m)m" : "\(h)h"
}

// MARK: - Add exercise sheet

/// The ONE add-exercise sheet, one field set for everyone. The answers decide the
/// exercise's shape — and so its logging controls — and the UI makes the invalid
/// combinations impossible: an isometric hold hides weight, load and duration;
/// tracking per-set weight (reps only) hides the fixed load.
struct AddExerciseSheet: View {
    /// What the sheet collected, already normalised to a valid shape. The caller
    /// owns the rep range and the `Repos.createExercise` call.
    struct Draft {
        var name: String
        var kind: ExerciseKind
        /// Per-set weight lift (rep counter with a weight field). Never true
        /// alongside `loadLb` or `isIsometric`.
        var tracksWeight: Bool
        var isIsometric: Bool
        /// Fixed carried load (one-tap logging). Nil for a weight-tracked lift
        /// or a hold.
        var loadLb: Double?
    }

    let onSave: (Draft) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var kind: ExerciseKind = .reps
    @State private var tracksWeight: Bool = false
    @State private var isIsometric: Bool = false
    @State private var loadRaw: String = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var loadFocused: Bool

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    /// Per-set weight only exists for a rep-counted, non-isometric exercise.
    private var showsWeightToggle: Bool { !isIsometric && kind == .reps }
    private var effectiveTracksWeight: Bool { showsWeightToggle && tracksWeight }
    /// A fixed load is for one-tap movements: not a hold, not a weight-tracked lift.
    private var showsLoad: Bool { !isIsometric && !effectiveTracksWeight }

    private var loadLb: Double? {
        // Field is in the active unit; persist canonical lb.
        guard showsLoad, !loadRaw.isEmpty, let v = Double(loadRaw), v > 0 else { return nil }
        return Units.weightToLb(v, system: unitSystem)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var draft: Draft {
        Draft(
            name: name.trimmingCharacters(in: .whitespaces),
            // A hold is stored as a duration exercise; only its sets carry seconds.
            kind: isIsometric ? .duration : kind,
            tracksWeight: effectiveTracksWeight,
            isIsometric: isIsometric,
            loadLb: loadLb
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add exercise")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("Tracks reps or minutes, calories, and muscle history.")
                        .font(.caption).foregroundStyle(theme.dim)
                }

                fieldLabel("Name")
                TextField("e.g. Pull-ups", text: $name)
                    .focused($nameFocused)
                    .padding(12)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    .foregroundStyle(theme.text)

                Toggle(isOn: $isIsometric.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Isometric hold")
                            .foregroundStyle(theme.text)
                        Text("Plank, dead hang, wall sit — counts seconds, not reps")
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                }
                .tint(theme.accent)

                if !isIsometric {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Count by")
                        Picker("Count by", selection: $kind.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                            Text("Reps").tag(ExerciseKind.reps)
                            Text("Duration (min)").tag(ExerciseKind.duration)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if showsWeightToggle {
                    Toggle(isOn: $tracksWeight.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tracks weight per set")
                                .foregroundStyle(theme.text)
                            Text("Shows a weight field when logging — for barbell and dumbbell lifts")
                                .font(.caption).foregroundStyle(theme.dim)
                        }
                    }
                    .tint(theme.accent)
                }

                if showsLoad {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Load carried (\(Units.weightUnit(unitSystem))) · optional")
                        TextField(unitSystem == .metric ? "e.g. 14" : "e.g. 30", text: $loadRaw)
                            .keyboardType(.decimalPad)
                            .focused($loadFocused)
                            .padding(12)
                            .background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                            .foregroundStyle(theme.text)
                        Text("The same weight every time — a child, a stroller, a bag. Logs with one tap.")
                            .font(.caption).foregroundStyle(theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    guard canSave else { return }
                    onSave(draft)
                    dismiss()
                } label: {
                    Text("Save")
                }
                .tactile(.primary, fullWidth: true)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .presentationDragIndicator(.visible)
        .onAppear { nameFocused = true }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nameFocused = false; loadFocused = false }
            }
        }
    }

    @ViewBuilder
    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium)).tracking(2)
            .foregroundStyle(theme.dim)
    }
}

// MARK: - Set history + edit/delete sheet

/// The ONE place a logged set is corrected or removed. Lists today's sets for an
/// exercise (newest first); tap a row to edit it, trash to remove it, plus a
/// destructive "delete exercise" action that cascade-removes its sets.
/// Owns a profile+exercise-scoped @Query so the list refreshes as sets change.
///
/// Opened from the clock on every `ExercisesCard` row, so a mis-tapped +1 is
/// fixable as easily as a lifted set. Don't add a second set-editing surface.
struct SetHistorySheet: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var setModels: [WorkoutSetModel]
    @State private var confirmDeleteExercise = false
    @State private var editing: WorkoutSetDTO?

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    init(profile: ProfileDTO, exercise: ExerciseDTO) {
        self.profile = profile
        self.exercise = exercise
        let uid = profile.id
        let exId = exercise.id
        // Recent sets show the CURRENT DAY only — the full cross-day history lives
        // in the Progress tab (Training history).
        let dayStart = Calendar.current.startOfDay(for: Date())
        _setModels = Query(
            filter: #Predicate<WorkoutSetModel> {
                $0.userId == uid && $0.exerciseId == exId && $0.timestamp >= dayStart
            },
            sort: \.timestamp, order: .reverse
        )
    }

    private var sets: [WorkoutSetDTO] { setModels.map(\.snapshot) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("Today sets")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                }

                if sets.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No sets logged today.")
                                .font(.callout).foregroundStyle(theme.text)
                            Text("Tap the exercise to log it. Past days live in Progress › Training history.")
                                .font(.caption).foregroundStyle(theme.dim)
                        }
                    }
                } else {
                    Text("Tap a set to fix it · trash to remove it")
                        .font(.caption).foregroundStyle(theme.dim)
                    ForEach(sets) { setRow($0) }
                    Text("Showing today only. Earlier sessions are in Progress › Training history.")
                        .font(.caption2).foregroundStyle(theme.dim)
                        .padding(.top, 2)
                }

                Button(role: .destructive) {
                    confirmDeleteExercise = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete \(noun)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tactile(.secondary, fullWidth: true)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .sheet(item: $editing) { s in
            EditSetSheet(profile: profile, exercise: exercise, loggedSet: s)
        }
        .confirmationDialog("Delete \(exercise.name)?",
                            isPresented: $confirmDeleteExercise,
                            titleVisibility: .visible) {
            Button("Delete \(noun) and all its sets", role: .destructive) {
                guard Repos.deleteExercise(ctx, id: exercise.id) else { return }
                toasts.show(Toast(title: "\(exercise.name) deleted",
                                  detail: "\(noun.capitalized) and its sets removed.",
                                  accent: .warn, symbol: "trash.fill"))
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private let noun = "exercise"

    @ViewBuilder
    private func setRow(_ s: WorkoutSetDTO) -> some View {
        HStack {
            Button { editing = s } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(primaryLabel(s))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.text)
                        Text(secondaryLabel(s))
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .tactile(.ghost)
            .accessibilityLabel("Edit set · \(primaryLabel(s))")

            Button(role: .destructive) {
                guard Repos.deleteSet(ctx, id: s.id) else { return }
                toasts.show(Toast(title: "Set removed",
                                  detail: primaryLabel(s),
                                  accent: .warn, symbol: "trash.fill"))
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(theme.warn)
            }
            .tactile(.ghost)
            .accessibilityLabel("Delete set")
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    private func primaryLabel(_ s: WorkoutSetDTO) -> String {
        // Hold first: an isometric is also `.duration` kind, and only a hold
        // carries holdSeconds. A duration exercise stores minutes in reps.
        if let secs = s.holdSeconds, secs > 0 {
            return "\(formattedHoldDuration(secs)) hold"
        }
        if exercise.kind == .duration {
            return "\(s.reps) min"
        }
        var label = "\(s.reps) rep\(s.reps == 1 ? "" : "s")"
        if let w = s.weightLb, w > 0 {
            label += " · \(Units.formatWeightWithUnit(lb: w, system: unitSystem, decimals: 0))"
        }
        return label
    }

    private func secondaryLabel(_ s: WorkoutSetDTO) -> String {
        var parts = [s.timestamp.formatted(date: .abbreviated, time: .shortened)]
        if let c = s.caloriesEst, c > 0 {
            parts.append("~\(Int(c)) cal")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Edit a logged set

/// Correct one already-logged set: reps (or minutes, or hold length) and the
/// weight lifted. Opened by tapping a row in `SetHistorySheet` — the only set
/// editor in the app.
///
/// The "≈ cal" readout comes from `Repos.setCaloriesEstimate`, the same function
/// `Repos.updateSet` writes with, so the preview is exactly what gets stored —
/// never a second copy of the MET math.
private struct EditSetSheet: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO
    let loggedSet: WorkoutSetDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var reps: Int
    @State private var holdSeconds: Int
    @State private var weightStr: String = ""
    @State private var prefilled = false
    @FocusState private var weightFocused: Bool

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    init(profile: ProfileDTO, exercise: ExerciseDTO, loggedSet: WorkoutSetDTO) {
        self.profile = profile
        self.exercise = exercise
        self.loggedSet = loggedSet
        _reps = State(initialValue: max(1, loggedSet.reps))
        _holdSeconds = State(initialValue: max(5, loggedSet.holdSeconds ?? 60))
    }

    /// A hold row is the one that carries holdSeconds; reps there is the hold
    /// count (1) and is left alone. A `.duration` exercise stores minutes
    /// in `reps`, so the same stepper edits it with a different unit word.
    private var isHold: Bool { loggedSet.holdSeconds != nil }
    private var isMinutes: Bool { !isHold && exercise.kind == .duration }
    private var unitLabel: String { isMinutes ? "min" : (reps == 1 ? "rep" : "reps") }

    /// A per-set-weight lift edits its weight. A set that already carries a
    /// weight keeps the field too, so saving can never silently drop it.
    private var showsWeight: Bool {
        !isHold && (exercise.tracksPerSetWeight || loggedSet.weightLb != nil)
    }

    private var weightLb: Double? {
        // Field is in the active unit; persist canonical lb.
        guard !weightStr.isEmpty else { return nil }
        return Units.parseWeightToLb(weightStr, system: unitSystem)
    }

    private var estimatedCal: Int {
        Int(Repos.setCaloriesEstimate(
            exercise: exercise,
            reps: isHold ? max(1, loggedSet.reps) : reps,
            holdSeconds: isHold ? holdSeconds : nil,
            bodyWeightLb: profile.weightLb
        ).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit set".uppercased())
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                    Text(exercise.name)
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("Logged \(loggedSet.timestamp.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(theme.dim)
                }

                if isHold {
                    holdEditor
                } else {
                    countEditor
                    if showsWeight { weightField }
                }

                Text("≈ \(estimatedCal) cal")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)

                Text("The calorie estimate is recalculated from the new numbers when you save.")
                    .font(.caption2).foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)

                Button { save() } label: { Text("Save changes") }
                    .tactile(.primary, fullWidth: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .onAppear {
            guard !prefilled else { return }
            prefilled = true
            if let w = loggedSet.weightLb, w > 0 {
                weightStr = Units.formatWeight(lb: w, system: unitSystem, decimals: 0)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
    }

    // MARK: - Editors

    @ViewBuilder
    private var countEditor: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                AnimatedNumber(
                    Double(reps),
                    font: .system(size: 64, weight: .semibold),
                    color: theme.accent
                )
                Text(unitLabel)
                    .font(.system(size: 15, weight: .medium)).tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.dim)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                ForEach([-5, -1, 1, 5], id: \.self) { delta in
                    Button {
                        reps = max(1, reps + delta)
                        Haptics.bump()
                    } label: {
                        Text(delta > 0 ? "+\(delta)" : "−\(abs(delta))")
                    }
                    .tactile(.bump)
                    .disabled(delta < 0 && reps == 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private var holdEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hold duration".uppercased())
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            // Same 5-second grid the isometric timer logs on, so an edited hold
            // can only land on a value the timer could have produced.
            Picker("Hold duration", selection: $holdSeconds) {
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
    private var weightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Weight lifted (\(Units.weightUnit(unitSystem)))")
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(theme.dim)
            TextField("—", text: $weightStr)
                .keyboardType(.decimalPad)
                .padding(10).background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
                .font(.system(.title3, design: .monospaced))
                .focused($weightFocused)
        }
    }

    private func save() {
        let newReps = isHold ? max(1, loggedSet.reps) : reps
        guard Repos.updateSet(
            ctx, id: loggedSet.id,
            reps: newReps,
            weightLb: showsWeight ? weightLb : nil,
            holdSeconds: isHold ? holdSeconds : nil,
            bodyWeightLb: profile.weightLb
        ) else { return }

        var detail = isHold
            ? "\(formattedHoldDuration(holdSeconds)) hold"
            : "\(newReps) \(isMinutes ? "min" : (newReps == 1 ? "rep" : "reps"))"
        if let w = weightLb, w > 0, showsWeight {
            detail += " · \(Units.formatWeightWithUnit(lb: w, system: unitSystem, decimals: 0))"
        }
        detail += " · ~\(estimatedCal) cal"
        toasts.show(Toast(title: "Set updated", detail: detail,
                          accent: .win, symbol: "checkmark.seal.fill"), for: 2.4)
        dismiss()
    }
}

// MARK: - Workout goal suggestion sheet

/// "What do you want to work on?" — type a free-text goal and get exercise picks.
/// Apple Intelligence (when available) selects from `ExerciseInfo.catalog` and
/// explains why; otherwise the deterministic `ExerciseGoalMatcher` ranks the same
/// research library. Either way the muscle data and reasons come from our library,
/// never invented. One tap adds a pick to the user's exercises.
private struct WorkoutGoalSheet: View {
    let profile: ProfileDTO
    /// Lowercased names already in the user's list, so we can show "Added".
    let existingNames: Set<String>

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var goal: String = ""
    @State private var results: [ExerciseGoalMatcher.GoalSuggestion] = []
    @State private var loading = false
    @State private var usedAI = false
    @State private var hasSearched = false
    @State private var added: Set<String> = []
    @FocusState private var focused: Bool

    private let examples = ["bigger back and shoulders", "stronger legs and glutes", "bigger arms", "better posture"]

    private var trimmedGoal: String { goal.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tell me what you want to work on and I'll suggest exercises from the research library.")
                        .font(.callout).foregroundStyle(theme.dim)

                    HStack(spacing: 8) {
                        TextField("e.g. bigger back and shoulders", text: $goal)
                            .padding(10).background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                            .foregroundStyle(theme.text)
                            .focused($focused)
                            .submitLabel(.search)
                            .onSubmit { Task { await run() } }

                        Button { Task { await run() } } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(trimmedGoal.isEmpty ? theme.dim : theme.accent)
                        }
                        .tactile(.ghost)
                        .disabled(trimmedGoal.isEmpty)
                        .accessibilityLabel("Get suggestions")
                    }

                    if !hasSearched {
                        FlowChips(items: examples) { example in
                            goal = example
                            Task { await run() }
                        }
                    }

                    if loading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Finding exercises with Apple Intelligence…")
                                .font(.caption).foregroundStyle(theme.dim)
                        }
                    }

                    ForEach(results) { suggestionCard($0) }

                    if usedAI && !results.isEmpty { aiAttribution }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Work on…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.tactile(.ghost)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    private func run() async {
        let g = trimmedGoal
        guard !g.isEmpty else { return }
        focused = false
        hasSearched = true

        if WorkoutSuggestionService.shared.isAvailable {
            loading = true
            let picks = await WorkoutSuggestionService.shared.picks(forGoal: g, fitnessGoal: profile.fitnessGoal)
            loading = false
            let mapped = picks.compactMap { pick -> ExerciseGoalMatcher.GoalSuggestion? in
                guard let entry = ExerciseInfo.catalogEntry(named: pick.exerciseName) else { return nil }
                return ExerciseGoalMatcher.suggestion(from: entry, reason: pick.reason.isEmpty ? nil : pick.reason)
            }
            if !mapped.isEmpty {
                results = mapped
                usedAI = true
                Haptics.selection()
                return
            }
        }

        // Deterministic fallback — always returns sensible picks.
        usedAI = false
        results = ExerciseGoalMatcher.suggestions(for: g, fitnessGoal: profile.fitnessGoal)
        Haptics.selection()
    }

    @ViewBuilder
    private func suggestionCard(_ g: ExerciseGoalMatcher.GoalSuggestion) -> some View {
        let isAdded = added.contains(g.exerciseName.lowercased()) || existingNames.contains(g.exerciseName.lowercased())
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.exerciseName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text(g.muscleGroups.joined(separator: " · "))
                            .font(.caption).foregroundStyle(theme.accent)
                    }
                    Spacer(minLength: 8)
                    Button {
                        add(g)
                    } label: {
                        Label(isAdded ? "Added" : "Add", systemImage: isAdded ? "checkmark" : "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .tactile(.pill, fill: isAdded ? nil : theme.accent)
                    .disabled(isAdded)
                }
                Text(g.reason)
                    .font(.callout).foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = g.researchNote, note != g.reason {
                    Text(note)
                        .font(.caption).foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func add(_ g: ExerciseGoalMatcher.GoalSuggestion) {
        guard Repos.createExercise(
            ctx, profileId: profile.id, name: g.exerciseName,
            defaultRepsBottom: g.repRange.lowerBound, defaultRepsTop: g.repRange.upperBound,
            tracksWeight: g.tracksWeight,
            kind: g.isIsometric ? .duration : .reps,
            muscleGroups: g.muscleGroups,
            isIsometric: g.isIsometric
        ) != nil else { return }
        added.insert(g.exerciseName.lowercased())
        toasts.show(Toast(title: g.exerciseName, detail: "Added to your exercises",
                          accent: .win, symbol: "plus.circle.fill"))
    }

    @ViewBuilder
    private var aiAttribution: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10)).foregroundStyle(theme.accent)
            Text("Picks chosen on-device by Apple Intelligence from the app's exercise research. Muscles and calorie estimates come from that research, not the model.")
                .font(.caption2).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

/// Small wrapping row of tappable example chips.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8).padding(.horizontal, 12)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                        .foregroundStyle(theme.text)
                }
                .tactile(.ghost)
            }
        }
    }
}
