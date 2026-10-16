import SwiftUI
import SwiftData

// MARK: - Train tab

/// The Train tab root — the same tab for every profile: live sessions, the one
/// exercise list (`ExercisesCard`), the optional activity sections the user has
/// added (Pilates / Yoga / Stretching), then the "what should I work on?"
/// discovery prompt. The fitness goal only tilts the suggestion ranking.
struct WorkoutsView: View {
    let profile: ProfileDTO

    @Environment(\.theme) private var theme

    // Profile-scoped at the query level — only used so the suggestion sheet can
    // mark picks the user already has as "Added".
    @Query private var exerciseModels: [ExerciseModel]

    // One-row existence probes: until the user adds or removes a section, the
    // sections shown are the ones they already have sessions for.
    @Query private var pilatesProbe: [PilatesSessionModel]
    @Query private var yogaProbe: [ActivitySessionModel]
    @Query private var stretchingProbe: [ActivitySessionModel]

    /// CSV of `TrainSection` ids; "" = never set. See `TrainSections`.
    @AppStorage private var sectionsRaw: String

    @State private var showGoalSheet = false
    @State private var showHistory = false
    @State private var sectionPendingRemoval: TrainSection?

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _exerciseModels = Query(filter: #Predicate<ExerciseModel> { $0.profileId == uid })
        _sectionsRaw = AppStorage(wrappedValue: "", TrainSections.storageKey(profileId: uid))

        var pilates = FetchDescriptor<PilatesSessionModel>(
            predicate: #Predicate { $0.profileId == uid })
        pilates.fetchLimit = 1
        _pilatesProbe = Query(pilates)

        let yogaId = TrainSection.yoga.activityId
        var yoga = FetchDescriptor<ActivitySessionModel>(
            predicate: #Predicate { $0.profileId == uid && $0.activityId == yogaId })
        yoga.fetchLimit = 1
        _yogaProbe = Query(yoga)

        let stretchingId = TrainSection.stretching.activityId
        var stretching = FetchDescriptor<ActivitySessionModel>(
            predicate: #Predicate { $0.profileId == uid && $0.activityId == stretchingId })
        stretching.fetchLimit = 1
        _stretchingProbe = Query(stretching)
    }

    private var sectionsWithData: Set<TrainSection> {
        var set: Set<TrainSection> = []
        if !pilatesProbe.isEmpty { set.insert(.pilates) }
        if !yogaProbe.isEmpty { set.insert(.yoga) }
        if !stretchingProbe.isEmpty { set.insert(.stretching) }
        return set
    }

    private var enabledSections: [TrainSection] {
        TrainSections.enabled(raw: sectionsRaw, withData: sectionsWithData)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Train")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Live sessions and your exercises — log it, watch the numbers move.")
                    .font(.callout).foregroundStyle(theme.dim)

                LiveSessionCard(profile: profile)

                // Logging what's already on your list is the job you open this tab
                // for, so it sits above the "what should I work on?" discovery
                // prompt rather than below it.
                ExercisesCard(profile: profile)

                historyButton

                ForEach(enabledSections) { section in
                    Card { ActivitySectionCard(profile: profile, section: section) }
                        // Press-and-hold to remove; the confirmation lives on the
                        // ScrollView so one dialog serves every section.
                        .contextMenu {
                            Button(role: .destructive) {
                                sectionPendingRemoval = section
                            } label: {
                                Label("Remove \(section.title) section", systemImage: "minus.circle")
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                let available = TrainSections.available(enabled: enabledSections)
                if !available.isEmpty {
                    addSectionRow(available)
                }

                workoutSuggestionButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .scrollHapticTicks()
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showHistory) {
            TrainingHistorySheet(profile: profile)
        }
        .sheet(isPresented: $showGoalSheet) {
            WorkoutGoalSheet(profile: profile,
                             existingNames: Set(exerciseModels.map { $0.name.lowercased() }))
        }
        .confirmationDialog(
            "Remove the \(sectionPendingRemoval?.title ?? "") section?",
            isPresented: Binding(
                get: { sectionPendingRemoval != nil },
                set: { if !$0 { sectionPendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: sectionPendingRemoval
        ) { section in
            Button("Remove section", role: .destructive) { remove(section) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Your logged sessions are kept.")
        }
    }

    // MARK: - Optional sections

    /// Pills for the sections not on the tab yet. Adding one stores the CSV, so
    /// from then on the user's choice — not their logged data — decides.
    @ViewBuilder
    private func addSectionRow(_ available: [TrainSection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a section")
                .font(.caption).foregroundStyle(theme.dim)
            HStack(spacing: 8) {
                ForEach(available) { section in
                    Button { add(section) } label: {
                        Label(section.title, systemImage: "plus")
                    }
                    .tactile(.pill)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func add(_ section: TrainSection) {
        Haptics.tap()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            sectionsRaw = TrainSections.encode(enabledSections + [section])
        }
    }

    private func remove(_ section: TrainSection) {
        Haptics.warn()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            sectionsRaw = TrainSections.encode(enabledSections.filter { $0 != section })
        }
    }

    /// Every past day's sets and sessions; tap an exercise there to fix or add
    /// sets on that day (same `TrainingHistorySheet` Progress opens).
    @ViewBuilder
    private var historyButton: some View {
        Button { showHistory = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training history")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text("View past days · fix or add forgotten sets")
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
/// combinations impossible: an isometric hold hides weight, load and duration.
/// There is no "tracks weight" switch — a rep-counted exercise with no fixed
/// weight always logs through the rep counter, whose weight field is optional.
struct AddExerciseSheet: View {
    /// What the sheet collected, already normalised to a valid shape. The caller
    /// owns the rep range and the `Repos.createExercise` call.
    struct Draft {
        var name: String
        var kind: ExerciseKind
        /// Rep counter with an optional weight field. Derived, not asked: true for
        /// a rep-counted, non-hold exercise with no fixed `loadLb`.
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
    @State private var isIsometric: Bool = false
    @State private var loadRaw: String = ""
    @FocusState private var nameFocused: Bool
    @FocusState private var loadFocused: Bool

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    /// A fixed weight is the optional shortcut: the same load every time, so it
    /// logs with one tap. Not for a hold.
    private var showsLoad: Bool { !isIsometric }

    private var loadLb: Double? {
        // Field is in the active unit; persist canonical lb.
        guard showsLoad, !loadRaw.isEmpty, let v = Double(loadRaw), v > 0 else { return nil }
        return Units.weightToLb(v, system: unitSystem)
    }

    /// No fixed weight on a rep-counted exercise → the rep counter asks for one
    /// each set (optional there too).
    private var tracksWeight: Bool { !isIsometric && kind == .reps && loadLb == nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var draft: Draft {
        Draft(
            name: name.trimmingCharacters(in: .whitespaces),
            // A hold is stored as a duration exercise; only its sets carry seconds.
            kind: isIsometric ? .duration : kind,
            tracksWeight: tracksWeight,
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

                if showsLoad {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Fixed weight (\(Units.weightUnit(unitSystem))) · optional")
                        TextField(unitSystem == .metric ? "e.g. 14" : "e.g. 30", text: $loadRaw)
                            .keyboardType(.decimalPad)
                            .focused($loadFocused)
                            .padding(12)
                            .background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                            .foregroundStyle(theme.text)
                        Text(kind == .reps
                             ? "Leave blank for dumbbells, barbells or bodyweight — you'll enter the weight when you log each set. Fill it in only for one fixed weight (a child, a stroller, a bag) that logs with one tap."
                             : "The same weight every time — a child, a stroller, a bag. Optional.")
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

/// The ONE place a logged set is corrected, added after the fact or removed.
/// Lists one day's sets for an exercise (newest first) with a 7-day strip to
/// switch days; tap a row to edit it, trash to remove it, "Add a set" to log one
/// the user forgot, plus a destructive "delete exercise" action that
/// cascade-removes its sets. Owns a profile+exercise-scoped @Query so the list
/// refreshes as sets change.
///
/// Opened from the clock on every `ExercisesCard` row (on today) and from an
/// exercise row in `TrainingHistorySheet` (on that row's day). Don't add a
/// second set-editing surface.
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
    @State private var adding: WorkoutSetDTO?
    @State private var selectedDayKey: String
    /// The day the sheet opened on — kept in the strip even when it's older
    /// than the last 7 days (opened from Training history).
    private let initialDayKey: String

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    init(profile: ProfileDTO, exercise: ExerciseDTO, dayKey: String = Dates.dayKey()) {
        self.profile = profile
        self.exercise = exercise
        self.initialDayKey = dayKey
        _selectedDayKey = State(initialValue: dayKey)
        let uid = profile.id
        let exId = exercise.id
        // Bounded to the strip's window (last 7 days, or back to the opening day
        // if older); the day itself is picked in Swift so switching days doesn't
        // rebuild the query.
        let cal = Calendar.current
        let weekStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) ?? Date()
        let openedStart = Dates.date(fromDayKey: dayKey) ?? weekStart
        let windowStart = min(weekStart, openedStart)
        _setModels = Query(
            filter: #Predicate<WorkoutSetModel> {
                $0.userId == uid && $0.exerciseId == exId && $0.timestamp >= windowStart
            },
            sort: \.timestamp, order: .reverse
        )
    }

    private var today: String { Dates.dayKey() }
    private var isToday: Bool { selectedDayKey == today }
    private var allSets: [WorkoutSetDTO] { setModels.map(\.snapshot) }

    private func dayLabel(_ key: String) -> String {
        if key == today { return "Today" }
        let yesterday = Dates.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        if key == yesterday { return "Yesterday" }
        return Dates.formatShort(key)
    }

    /// "today" / "yesterday" / "on Oct 12" — for sentences.
    private func dayPhrase(_ key: String) -> String {
        let label = dayLabel(key)
        return key == today || label == "Yesterday" ? label.lowercased() : "on \(label)"
    }

    /// Last 7 days, newest first, plus the opening day when it's older.
    private var dayKeys: [String] {
        let week = Array(Dates.lastNDays(7).reversed())
        return week.contains(initialDayKey) ? week : week + [initialDayKey]
    }

    var body: some View {
        let loggedDays = Set(allSets.map { Dates.dayKey($0.timestamp) })
        let sets = allSets.filter { Dates.dayKey($0.timestamp) == selectedDayKey }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text(isToday ? "Today's sets" : "Sets · \(Dates.formatLong(selectedDayKey))")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                }

                dayStrip(loggedDays: loggedDays)

                if sets.isEmpty {
                    Card {
                        Text("No sets logged \(dayPhrase(selectedDayKey)).")
                            .font(.callout).foregroundStyle(theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("Tap a set to fix it · trash to remove it")
                        .font(.caption).foregroundStyle(theme.dim)
                    ForEach(sets) { setRow($0) }
                }

                // Forgot to log a set? Add it to the selected day.
                Button { adding = newSetTemplate(daySets: sets) } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(isToday ? "Add a set" : "Add a set to \(dayLabel(selectedDayKey))")
                    }
                }
                .tactile(.primary, fullWidth: true)

                Text("Older days are in Training history on the Train tab.")
                    .font(.caption2).foregroundStyle(theme.dim)

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
        .sheet(item: $adding) { s in
            EditSetSheet(profile: profile, exercise: exercise, loggedSet: s, isNew: true)
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
    private func dayStrip(loggedDays: Set<String>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dayKeys, id: \.self) { key in
                    Button {
                        guard key != selectedDayKey else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedDayKey = key
                        }
                        Haptics.selection()
                    } label: {
                        HStack(spacing: 5) {
                            Text(dayLabel(key))
                                .font(.system(size: 13, weight: .medium))
                            if loggedDays.contains(key) && selectedDayKey != key {
                                Circle().fill(theme.accent).frame(width: 5, height: 5)
                            }
                        }
                    }
                    .tactile(.pill, fill: selectedDayKey == key ? theme.accent : nil)
                    .accessibilityLabel(loggedDays.contains(key) ? "\(dayLabel(key)), has sets" : dayLabel(key))
                }
            }
        }
    }

    /// The set the add form starts from: the day's most recent set (or this
    /// exercise's latest anywhere in the window), else 10 reps / 5 min / a 60s
    /// hold — the same starting points the rep counter and hold timer use.
    /// Timestamp: now for today; otherwise a minute after the day's last set,
    /// or midday when the day has none.
    private func newSetTemplate(daySets: [WorkoutSetDTO]) -> WorkoutSetDTO {
        let base = daySets.first ?? allSets.first
        let timestamp: Date
        if isToday {
            timestamp = Date()
        } else if let last = daySets.first {
            // Stay inside the selected day even after a 23:59 set.
            let dayStart = Dates.date(fromDayKey: selectedDayKey) ?? last.timestamp
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)?
                .addingTimeInterval(-1) ?? last.timestamp
            timestamp = min(last.timestamp.addingTimeInterval(60), dayEnd)
        } else {
            let dayStart = Dates.date(fromDayKey: selectedDayKey) ?? Date()
            timestamp = Calendar.current.date(byAdding: .hour, value: 12, to: dayStart) ?? dayStart
        }
        let defaultCount = exercise.kind == .duration ? 5 : 10
        let holdSeconds = exercise.isIsometric ? (base?.holdSeconds ?? 60) : nil
        // A fixed-load movement carries the load it is done at: this day's own
        // stamped weight if it has sets (a back-filled day may predate an edit
        // of the load), else the exercise's. Holds never get one.
        let fixedLoad = exercise.fixedLoadLb(
            forRowWeight: daySets.first?.weightLb, holdSeconds: holdSeconds)
        return WorkoutSetDTO(
            userId: profile.id,
            exerciseId: exercise.id,
            weightLb: exercise.tracksPerSetWeight ? base?.weightLb : fixedLoad,
            reps: exercise.isIsometric ? 1 : (base?.reps ?? defaultCount),
            timestamp: timestamp,
            holdSeconds: holdSeconds
        )
    }

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
/// weight lifted — or, with `isNew`, log a forgotten set on a past day from a
/// template `SetHistorySheet` builds. Opened only from `SetHistorySheet` — the
/// only set editor in the app.
///
/// The "≈ cal" readout comes from `Repos.setCaloriesEstimate`, the same function
/// `Repos.updateSet` writes with, so the preview is exactly what gets stored —
/// never a second copy of the MET math.
private struct EditSetSheet: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO
    let loggedSet: WorkoutSetDTO
    let isNew: Bool

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var reps: Int
    @State private var holdSeconds: Int
    @State private var weightStr: String = ""
    @State private var prefilled = false
    @State private var prefilledWeightStr: String?
    @FocusState private var weightFocused: Bool

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    init(profile: ProfileDTO, exercise: ExerciseDTO, loggedSet: WorkoutSetDTO, isNew: Bool = false) {
        self.profile = profile
        self.exercise = exercise
        self.loggedSet = loggedSet
        self.isNew = isNew
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
        // Untouched since the prefill: keep the stored value. The field shows
        // whole units, so re-parsing it would turn a 32.5 lb load into 33 on any
        // unrelated edit (weights match exactly).
        if weightStr == prefilledWeightStr, let stored = loggedSet.weightLb { return stored }
        // Canonical to 0.01 lb so a retyped metric value matches the logged weight.
        return Units.parseWeightToLb(weightStr, system: unitSystem).map(RepHistory.canonicalLb)
    }

    /// The load a fixed-load row is priced at: what the field says, else the
    /// row's stamped weight, else the exercise's (nil for any other shape). The
    /// same resolution `Repos.updateSet` applies, so the preview is the stored figure.
    private var rowLoadLb: Double? {
        exercise.fixedLoadLb(
            forRowWeight: (showsWeight ? weightLb : nil) ?? loggedSet.weightLb,
            holdSeconds: isHold ? holdSeconds : nil)
    }

    private var estimatedCal: Int {
        Int(Repos.setCaloriesEstimate(
            exercise: exercise,
            reps: isHold ? max(1, loggedSet.reps) : reps,
            holdSeconds: isHold ? holdSeconds : nil,
            bodyWeightLb: profile.weightLb,
            loadLb: rowLoadLb
        ).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text((isNew ? "Add set" : "Edit set").uppercased())
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                    Text(exercise.name)
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text(isNew
                         ? "For \(Dates.formatLong(Dates.dayKey(loggedSet.timestamp)))"
                         : "Logged \(loggedSet.timestamp.formatted(date: Dates.dayKey(loggedSet.timestamp) == Dates.dayKey() ? .omitted : .abbreviated, time: .shortened))")
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

                if !isNew {
                    Text("The calorie estimate is recalculated from the new numbers when you save.")
                        .font(.caption2).foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { save() } label: { Text(isNew ? "Add set" : "Save changes") }
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
                prefilledWeightStr = weightStr
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
        if isNew {
            var dto = loggedSet
            dto.reps = newReps
            dto.weightLb = rowLoadLb ?? (showsWeight ? weightLb : nil)
            dto.holdSeconds = isHold ? holdSeconds : nil
            dto.caloriesEst = Repos.setCaloriesEstimate(
                exercise: exercise, reps: newReps,
                holdSeconds: dto.holdSeconds, bodyWeightLb: profile.weightLb,
                loadLb: rowLoadLb
            )
            guard Repos.addSet(ctx, dto) else { return }
        } else {
            guard Repos.updateSet(
                ctx, id: loggedSet.id,
                reps: newReps,
                weightLb: showsWeight ? weightLb : nil,
                holdSeconds: isHold ? holdSeconds : nil,
                bodyWeightLb: profile.weightLb
            ) else { return }
        }

        var detail = isHold
            ? "\(formattedHoldDuration(holdSeconds)) hold"
            : "\(newReps) \(isMinutes ? "min" : (newReps == 1 ? "rep" : "reps"))"
        if let w = weightLb, w > 0, showsWeight {
            detail += " · \(Units.formatWeightWithUnit(lb: w, system: unitSystem, decimals: 0))"
        }
        detail += " · ~\(estimatedCal) cal"
        toasts.show(Toast(title: isNew ? "Set added" : "Set updated", detail: detail,
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
