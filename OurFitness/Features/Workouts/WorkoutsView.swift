import SwiftUI
import SwiftData

// MARK: - Train tab (both modes; Build = lifts, Circuit = Pilates + movements)

/// The Train tab root. Mode-aware: Build shows the lift list + rep counter,
/// Circuit shows Pilates plus the parenting-movement quick-log.
struct WorkoutsView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    // Profile-scoped at the query level — never fetch another profile's rows.
    @Query private var exerciseModels: [ExerciseModel]
    @Query private var setModels: [WorkoutSetModel]

    @State private var showAddSheet = false
    @State private var showGoalSheet = false
    @State private var activeRepCounter: ExerciseDTO?
    @State private var activeInfo: ExerciseDTO?
    @State private var activeHistory: ExerciseDTO?

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _exerciseModels = Query(
            filter: #Predicate<ExerciseModel> { $0.profileId == uid },
            sort: \.name, order: .forward
        )
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
    private var mySets: [WorkoutSetDTO] { setModels.map(\.snapshot) }

    // MARK: - Stats helpers

    private struct ExerciseStats {
        var todayReps: Int = 0
        var yesterdayReps: Int = 0
        var todayCal: Double = 0
        var todayHoldSec: Int = 0
        var yesterdayHoldSec: Int = 0
        var yesterdayCal: Double = 0
        /// Rows logged today — shown next to the history icon so the icon reads
        /// as "3 sets, tap to fix them" instead of an unlabelled clock.
        var todaySets: Int = 0
    }

    private var statsByExercise: [String: ExerciseStats] {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart

        return mySets.reduce(into: [String: ExerciseStats]()) { acc, s in
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
            } else if inYesterday {
                stats.yesterdayReps += s.reps
                stats.yesterdayHoldSec += s.holdSeconds ?? 0
                stats.yesterdayCal += s.caloriesEst ?? 0
            }
            acc[s.exerciseId] = stats
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Train")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text(profile.mode == .build
                     ? "Hypertrophy bias. Add your lifts, count reps, watch the numbers climb."
                     : "Pilates, live sessions, and your movements — log it, keep the markers moving.")
                    .font(.callout).foregroundStyle(theme.dim)

                LiveSessionCard(profile: profile)

                // Logging what's already on your list is the job you open this tab
                // for, so it sits above the "what should I work on?" discovery
                // prompt rather than below it.
                exercisesSection

                workoutSuggestionButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .scrollHapticTicks()
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showAddSheet) {
            AddExerciseSheet(mode: profile.mode) { draft in
                guard Repos.createExercise(
                    ctx, profileId: profile.id, name: draft.name,
                    defaultRepsBottom: 8, defaultRepsTop: 12,
                    tracksWeight: draft.tracksWeight,
                    kind: draft.kind,
                    isIsometric: draft.isIsometric
                ) != nil else { return }
                toasts.show(Toast(title: draft.name, detail: "Exercise added", accent: .win, symbol: "plus.circle.fill"))
            }
            .themed(profile.mode)
        }
        .sheet(item: $activeRepCounter) { ex in
            RepCounterSheet(profile: profile, exercise: ex)
                .themed(profile.mode)
        }
        .sheet(item: $activeInfo) { ex in
            ExerciseInfoSheet(exercise: ex, profile: profile)
                .themed(profile.mode)
        }
        .sheet(item: $activeHistory) { ex in
            SetHistorySheet(profile: profile, exercise: ex)
                .themed(profile.mode)
        }
        .sheet(isPresented: $showGoalSheet) {
            WorkoutGoalSheet(profile: profile, existingNames: Set(myExercises.map { $0.name.lowercased() }))
                .themed(profile.mode)
        }
    }

    // Build shows the lift list (rep counter, sets, weight history); Circuit shows its
    // movement loop — Pilates plus the parenting-movement quick-log (which renders the
    // same exercises with tap-to-log, so the Build list would only duplicate it).
    @ViewBuilder
    private var exercisesSection: some View {
        if profile.mode == .build {
            let exercises = myExercises
            HStack {
                Text("Your exercises")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                Spacer()
                Button { showAddSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                }
                .tactile(.pill, fill: theme.accent)
            }

            if exercises.isEmpty {
                // The card itself adds an exercise — a first-time user shouldn't
                // have to find the small Add pill to get started.
                PressableCard(action: { showAddSheet = true }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(theme.accent)
                            Text("Add your first exercise")
                                .font(.callout).foregroundStyle(theme.text)
                        }
                        Text("Each entry tracks reps, weight, calories, and muscle history. Not sure what to pick? Use “What do you want to work on?” below.")
                            .font(.caption).foregroundStyle(theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                let stats = statsByExercise
                ForEach(exercises) { ex in
                    exerciseCard(ex, stats: stats[ex.id] ?? ExerciseStats())
                }
            }
        } else {
            // Movements first: a one-tap quick-log used several times a day,
            // where Pilates is a handful of sessions a week.
            BabyExercisesCard(profile: profile)
            Card { PilatesCard(profile: profile) }
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

    @ViewBuilder
    private func exerciseCard(_ ex: ExerciseDTO, stats: ExerciseStats) -> some View {
        let info = ExerciseInfo.meta(for: ex)

        PressableCard(action: { activeRepCounter = ex }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.text)
                        if ex.isIsometric {
                            Text("Isometric")
                                .font(.system(size: 10, weight: .medium)).tracking(1)
                                .textCase(.uppercase)
                                .foregroundStyle(theme.accent.opacity(0.7))
                        }
                    }
                    Spacer()
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
                }

                Text(info.muscleGroups.prefix(3).joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium)).tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.accent)

                HStack(spacing: 0) {
                    if ex.isIsometric {
                        holdCell(label: "Today", seconds: stats.todayHoldSec,
                                 holds: stats.todayReps, cal: stats.todayCal > 0 ? stats.todayCal : nil)
                        Divider().frame(height: 32).background(theme.line).padding(.horizontal, 8)
                        holdCell(label: "Yesterday", seconds: stats.yesterdayHoldSec,
                                 holds: stats.yesterdayReps, cal: stats.yesterdayCal > 0 ? stats.yesterdayCal : nil)
                    } else {
                        repCell(label: "Today", reps: stats.todayReps,
                                cal: stats.todayCal > 0 ? stats.todayCal : nil)
                        Divider().frame(height: 32).background(theme.line).padding(.horizontal, 8)
                        repCell(label: "Yesterday", reps: stats.yesterdayReps, cal: nil)
                    }
                    Spacer()
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(theme.accent.opacity(0.5))
                        .font(.system(size: 16))
                }
            }
        }
    }

    @ViewBuilder
    private func repCell(label: String, reps: Int, cal: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(1.5)
                .foregroundStyle(theme.dim)
            Text(reps > 0 ? "\(reps)" : "—")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(reps > 0 ? theme.text : theme.dim)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: reps)
            if let c = cal, c > 0 {
                Text("~\(Int(c)) cal")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
        }
    }

    @ViewBuilder
    private func holdCell(label: String, seconds: Int, holds: Int, cal: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(1.5)
                .foregroundStyle(theme.dim)
            Text(seconds > 0 ? formattedHoldDuration(seconds) : "—")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(seconds > 0 ? theme.text : theme.dim)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: seconds)
            if holds > 0 {
                Text("\(holds) hold\(holds == 1 ? "" : "s")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
            if let c = cal, c > 0 {
                Text("~\(Int(c)) cal")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
        }
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

// MARK: - Add exercise sheet (both modes)

/// One add-exercise sheet for the whole Train tab. The fields vary by mode —
/// Build asks whether the lift tracks weight and whether it's an isometric
/// hold; Circuit asks reps-vs-duration and an optional carried load — but the
/// title, button style and focus behaviour are the same in both.
struct AddExerciseSheet: View {
    /// What the sheet collected. Callers own the rep range and the `Repos` call,
    /// because Build and Circuit seed different defaults.
    struct Draft {
        var name: String
        var kind: ExerciseKind
        var tracksWeight: Bool
        var isIsometric: Bool
        var loadLb: Double?
    }

    let mode: Mode
    let onSave: (Draft) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var kind: ExerciseKind = .reps
    @State private var tracksWeight: Bool = true
    @State private var isIsometric: Bool = false
    @State private var loadRaw: String = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var loadFocused: Bool

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    private var isCircuit: Bool { mode == .circuit }

    private var loadLb: Double? {
        // Field is in the active unit; persist canonical lb.
        guard !loadRaw.isEmpty, let v = Double(loadRaw), v > 0 else { return nil }
        return Units.weightToLb(v, system: unitSystem)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var draft: Draft {
        let load = isCircuit ? loadLb : nil
        return Draft(
            name: name.trimmingCharacters(in: .whitespaces),
            kind: isCircuit ? kind : (isIsometric ? .duration : .reps),
            // Circuit has no weight toggle — a carried load is what it tracks.
            tracksWeight: isCircuit ? (load != nil) : tracksWeight,
            isIsometric: isCircuit ? false : isIsometric,
            loadLb: load
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isCircuit ? "Add movement" : "Add exercise")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text(isCircuit
                         ? "Quick-log it from the Movements card with one tap."
                         : "Tracks reps, calories, and muscle history.")
                        .font(.caption).foregroundStyle(theme.dim)
                }

                fieldLabel("Name")
                TextField(isCircuit ? "e.g. Carried Baby" : "e.g. Pull-ups", text: $name)
                    .focused($nameFocused)
                    .padding(12)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    .foregroundStyle(theme.text)

                if isCircuit {
                    circuitFields
                } else {
                    buildFields
                }

                Button {
                    guard canSave else { return }
                    onSave(draft)
                    dismiss()
                } label: {
                    Text(isCircuit ? "Add movement" : "Save")
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

    @ViewBuilder
    private var buildFields: some View {
        Toggle(isOn: $tracksWeight) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tracks weight")
                    .foregroundStyle(theme.text)
                Text("Shows a weight field when logging")
                    .font(.caption).foregroundStyle(theme.dim)
            }
        }
        .tint(theme.accent)
        .disabled(isIsometric)
        .opacity(isIsometric ? 0.4 : 1)

        Toggle(isOn: $isIsometric) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Isometric hold")
                    .foregroundStyle(theme.text)
                Text("Plank, dead hang, wall sit — counts seconds, not reps")
                    .font(.caption).foregroundStyle(theme.dim)
            }
        }
        .tint(theme.accent)
        .onChange(of: isIsometric) { _, on in
            if on { tracksWeight = false }
        }
    }

    @ViewBuilder
    private var circuitFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Type")
            Picker("Type", selection: $kind) {
                Text("Reps").tag(ExerciseKind.reps)
                Text("Duration (min)").tag(ExerciseKind.duration)
            }
            .pickerStyle(.segmented)
        }

        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Load (\(Units.weightUnit(unitSystem))) · optional")
            TextField(unitSystem == .metric ? "e.g. 14" : "e.g. 30", text: $loadRaw)
                .keyboardType(.decimalPad)
                .focused($loadFocused)
                .padding(12)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }
    }
}

// MARK: - Set history + edit/delete sheet

/// The ONE place a logged set is corrected or removed. Lists today's sets for an
/// exercise (newest first); tap a row to edit it, trash to remove it, plus a
/// destructive "delete exercise" action that cascade-removes its sets.
/// Owns a profile+exercise-scoped @Query so the list refreshes as sets change.
///
/// Internal, not private: Circuit's movement quick-log
/// (`Circuit/BabyExercisesCard.swift`) opens this same sheet from a row, so a
/// mis-tapped +1 is fixable there too. Don't add a second set-editing surface.
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
                            Text(profile.mode == .build
                                 ? "Tap the exercise to start counting. Past days live in Progress › Training history."
                                 : "Tap + on the movement to log it. Past days live in Progress › Training history.")
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
                .themed(profile.mode)
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

    /// Circuit calls these "movements" everywhere else; Build calls them exercises.
    private var noun: String { profile.mode == .build ? "exercise" : "movement" }

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
        // Hold first: a Build isometric is also `.duration` kind, and only a hold
        // carries holdSeconds. A Circuit duration movement stores minutes in reps.
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
    /// count (1) and is left alone. A Circuit `.duration` movement stores minutes
    /// in `reps`, so the same stepper edits it with a different unit word.
    private var isHold: Bool { loggedSet.holdSeconds != nil }
    private var isMinutes: Bool { !isHold && exercise.kind == .duration }
    private var unitLabel: String { isMinutes ? "min" : (reps == 1 ? "rep" : "reps") }

    private var showsWeight: Bool {
        !isHold && (exercise.category == .compound || exercise.category == .isolation || loggedSet.weightLb != nil)
    }

    private var weightLb: Double? {
        // Field is in the active unit; persist canonical lb.
        guard !weightStr.isEmpty else { return nil }
        return Units.parseWeightToLb(weightStr, system: unitSystem)
    }

    private var estimatedCal: Int {
        Int(Repos.setCaloriesEstimate(
            exercise: exercise, mode: profile.mode,
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
            bodyWeightLb: profile.weightLb,
            mode: profile.mode
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
                    Text("Tell me what you want to build and I'll suggest exercises from the research library.")
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
            let picks = await WorkoutSuggestionService.shared.picks(forGoal: g, mode: profile.mode)
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
        results = ExerciseGoalMatcher.suggestions(for: g, mode: profile.mode)
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
