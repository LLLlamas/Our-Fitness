import SwiftUI
import SwiftData

struct WorkoutsView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme

    var body: some View {
        BuildWorkoutsView(profile: profile)
            .background(theme.bg.ignoresSafeArea())
    }
}

// MARK: - Workouts content (both modes; Build = lifts, Circuit = Pilates + movements)

private struct BuildWorkoutsView: View {
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
            } else if inYesterday {
                stats.yesterdayReps += s.reps
                stats.yesterdayHoldSec += s.holdSeconds ?? 0
                stats.yesterdayCal += s.caloriesEst ?? 0
            }
            acc[s.exerciseId] = stats
        }
    }

    private func holdLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 90 { return "\(seconds)s" }
        if seconds < 4200 {
            let m = seconds / 60; let s = seconds % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        }
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
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

                workoutSuggestionButton

                exercisesSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .scrollHapticTicks()
        }
        .sheet(isPresented: $showAddSheet) {
            AddExerciseSheet(profileId: profile.id) { name, lo, hi, tracksWeight, isIsometric in
                Repos.createExercise(
                    ctx, profileId: profile.id, name: name,
                    defaultRepsBottom: lo, defaultRepsTop: hi,
                    tracksWeight: tracksWeight,
                    isIsometric: isIsometric
                )
                Haptics.bump()
                toasts.show(Toast(title: name, detail: "Exercise added", accent: .win, symbol: "plus.circle.fill"))
            }
            .themed(profile.mode)
        }
        .sheet(item: $activeRepCounter) { ex in
            RepCounterSheet(profile: profile, exercise: ex)
                .themed(profile.mode)
        }
        .sheet(item: $activeInfo) { ex in
            BuildExerciseInfoSheet(exercise: ex, profile: profile)
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

            if myExercises.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No exercises yet.")
                            .font(.callout).foregroundStyle(theme.text)
                        Text("Tap Add to build your list. Each entry tracks reps, calories, and muscle history.")
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                }
            } else {
                let stats = statsByExercise
                ForEach(myExercises) { ex in
                    exerciseCard(ex, stats: stats[ex.id] ?? ExerciseStats())
                }
            }
        } else {
            Card { PilatesCard(profile: profile) }
            BabyExercisesCard(profile: profile)
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
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(theme.dim)
                    }
                    .tactile(.ghost)
                    .accessibilityLabel("\(ex.name) logged sets")
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
            Text(holdLabel(seconds))
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

// MARK: - Add exercise sheet

private struct AddExerciseSheet: View {
    let profileId: UUID
    let onSave: (String, Int, Int, Bool, Bool) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var tracksWeight: Bool = true
    @State private var isIsometric: Bool = false
    @FocusState private var nameFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add exercise")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(theme.text)

                TextField("Name (e.g. Pull-ups)", text: $name)
                    .padding(10).background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    .foregroundStyle(theme.text)
                    .focused($nameFocused)

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

                Button {
                    onSave(name.trimmingCharacters(in: .whitespaces), 8, 12, tracksWeight, isIsometric)
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nameFocused = false }
            }
        }
    }
}

// MARK: - Set history + delete sheet

/// Lists every set logged against an exercise (newest first) with per-set delete,
/// plus a destructive "delete exercise" action that cascade-removes its sets.
/// Owns a profile+exercise-scoped @Query so the list refreshes as sets are removed.
private struct SetHistorySheet: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var setModels: [WorkoutSetModel]
    @State private var confirmDeleteExercise = false

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
                            Text("Tap the exercise to start counting. Past days live in Progress › Training history.")
                                .font(.caption).foregroundStyle(theme.dim)
                        }
                    }
                } else {
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
                        Text("Delete exercise")
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
        .confirmationDialog("Delete \(exercise.name)?",
                            isPresented: $confirmDeleteExercise,
                            titleVisibility: .visible) {
            Button("Delete exercise and all its sets", role: .destructive) {
                Repos.deleteExercise(ctx, id: exercise.id)
                Haptics.warn()
                toasts.show(Toast(title: "\(exercise.name) deleted",
                                  detail: "Exercise and its sets removed.",
                                  accent: .warn, symbol: "trash.fill"))
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func setRow(_ s: WorkoutSetDTO) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLabel(s))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(secondaryLabel(s))
                    .font(.caption).foregroundStyle(theme.dim)
            }
            Spacer()
            Button(role: .destructive) {
                Repos.deleteSet(ctx, id: s.id)
                Haptics.warn()
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
        if exercise.isIsometric {
            let secs = s.holdSeconds ?? 0
            return "\(secs)s hold"
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
        Repos.createExercise(
            ctx, profileId: profile.id, name: g.exerciseName,
            defaultRepsBottom: g.repRange.lowerBound, defaultRepsTop: g.repRange.upperBound,
            tracksWeight: g.tracksWeight,
            kind: g.isIsometric ? .duration : .reps,
            muscleGroups: g.muscleGroups,
            isIsometric: g.isIsometric
        )
        added.insert(g.exerciseName.lowercased())
        Haptics.bump()
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
