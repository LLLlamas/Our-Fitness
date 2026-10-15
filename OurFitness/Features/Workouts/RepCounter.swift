// Friction-free set counter for any exercise. Scroll a wheel to the set's reps
// (or minutes for a duration exercise), Save set commits a WorkoutSet. Shows a weight field only
// for a lift that tracks per-set weight. For isometric exercises, shows a
// countdown timer instead. Calories go through `Repos.setCaloriesEstimate`, the
// same function a set edit recomputes with.

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

    // Profile + exercise scoped at the query level — drives the weekly volume
    // milestone count (approximated per-exercise; see workoutSetMessage call site).
    @Query private var weekSetModels: [WorkoutSetModel]

    @State private var reps: Int = 10
    @State private var weightStr: String = ""
    @State private var setsLogged: Int = 0
    @State private var showInfo = false
    @State private var lastProjection: String?
    @State private var prefilledWeight = false
    @State private var prefilledCount = false
    @FocusState private var weightFocused: Bool

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    init(profile: ProfileDTO, exercise: ExerciseDTO) {
        self.profile = profile
        self.exercise = exercise
        let uid = profile.id
        let exId = exercise.id
        let weekStart = Dates.startOfISOWeek()
        _weekSetModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid && $0.exerciseId == exId && $0.timestamp >= weekStart },
            sort: \.timestamp, order: .reverse
        )
    }

    private var tracksWeight: Bool { exercise.tracksPerSetWeight }
    private var info: ExerciseInfo.Meta { ExerciseInfo.meta(for: exercise) }
    /// A duration exercise stores minutes in `reps`, so the counter counts minutes.
    private var isMinutes: Bool { exercise.kind == .duration }
    private func unitWord(_ n: Int) -> String { isMinutes ? "min" : (n == 1 ? "rep" : "reps") }
    /// Wheel range: 1–100 reps, or 1–180 minutes for a duration exercise.
    private var countRange: ClosedRange<Int> { isMinutes ? 1...180 : 1...100 }

    // Sets logged this ISO week for this exercise (Monday-anchored, matching
    // the WorkoutsView stats helper). Approximates per-muscle weekly volume.
    private var setsThisWeekForMuscle: Int {
        // Re-filter rather than trust the query alone: `weekStart` is frozen at
        // init, so a view that outlives midnight on a Sunday would otherwise
        // count last week's sets. Dates.startOfISOWeek reuses one shared
        // calendar — building one here ran on every render.
        let weekStart = Dates.startOfISOWeek()
        return weekSetModels.filter { $0.timestamp >= weekStart }.count
    }

    var body: some View {
        VStack(spacing: 18) {
            header
            countPicker
            if tracksWeight {
                weightField
            }
            actionRow
            if let projection = lastProjection {
                ProjectionBar(text: projection)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The wheel + Save fit a half sheet; .large stays available for the weight
        // field with the keyboard up.
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .onAppear {
            prefillCount()
            prefillWeight()
        }
        .sheet(isPresented: $showInfo) {
            ExerciseInfoSheet(exercise: exercise, profile: profile)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
    }

    /// Carry the last weight used for this lift into the field. Same weight
    /// across sets is the common case, and re-typing it was the only typing left
    /// in the logging flow. Fills once, and only an empty field, so it can never
    /// overwrite what the user is typing. Scoped to this week's sets (the query
    /// window) — an older lift opens blank rather than suggesting a stale number.
    private func prefillWeight() {
        guard tracksWeight, weightStr.isEmpty, !prefilledWeight else { return }
        prefilledWeight = true
        guard let last = weekSetModels.first(where: { ($0.weightLb ?? 0) > 0 })?.weightLb else { return }
        weightStr = Units.formatWeight(lb: last, system: unitSystem, decimals: 0)
    }

    /// Start the wheel on this week's last logged count for this exercise (same
    /// query window as the weight pre-fill), else 10 reps / 5 min. Runs once, so
    /// it never moves the wheel out from under the user.
    private func prefillCount() {
        guard !prefilledCount else { return }
        prefilledCount = true
        let last = weekSetModels.first(where: { $0.holdSeconds == nil && $0.reps > 0 })?.reps
        let fallback = isMinutes ? 5 : 10
        reps = min(max(last ?? fallback, countRange.lowerBound), countRange.upperBound)
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

    /// Same wheel idiom as the isometric hold picker.
    @ViewBuilder
    private var countPicker: some View {
        VStack(spacing: 8) {
            Text((isMinutes ? "Minutes this set" : "Reps this set").uppercased())
                .font(.system(size: 10)).tracking(2)
                .foregroundStyle(theme.dim)
            Picker(isMinutes ? "Minutes" : "Reps", selection: $reps) {
                ForEach(Array(countRange), id: \.self) { n in
                    Text("\(n) \(unitWord(n))").tag(n)
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
                saveSet()
            } label: {
                Text("Save set")
            }
            .tactile(.primary, fill: theme.ok)

            Button {
                dismiss()
            } label: {
                Text("Done")
            }
            .tactile(.ghost)
        }
    }

    private func saveSet() {
        // Field shows the active unit; persist canonical lb.
        let weight = Units.parseWeightToLb(weightStr, system: unitSystem)
        let kcal = Repos.setCaloriesEstimate(
            exercise: exercise,
            reps: reps,
            holdSeconds: nil,
            bodyWeightLb: profile.weightLb
        )

        // Snapshot pre-save figures so the projection/milestone don't depend on
        // @Query refresh timing (SwiftData may not reflect the new set this tick).
        let caloriesTodayBefore = weekSetModels
            .filter { Calendar.current.isDateInToday($0.timestamp) }
            .reduce(0.0) { $0 + ($1.caloriesEst ?? 0) }
        let weekCountAfter = setsThisWeekForMuscle + 1

        let dto = WorkoutSetDTO(
            userId: profile.id,
            exerciseId: exercise.id,
            weightLb: tracksWeight ? weight : nil,
            reps: reps,
            caloriesEst: kcal
        )
        guard Repos.addSet(ctx, dto) else { return }
        setsLogged += 1

        // Same figure the set was stored with, so the strip matches the toast.
        lastProjection = EncouragementEngine.repProjection(
            setCalories: kcal,
            totalCaloriesToday: caloriesTodayBefore
        )

        // Weekly volume milestone — fires only at defined set counts. Its copy is
        // hypertrophy volume, so it only speaks for unloaded rep sets: not a minute of
        // carrying, and not a fixed-load movement counted in one-tap +1 rows.
        let countsAsVolume = !isMinutes && exercise.loadLb == nil
        if countsAsVolume, let milestone = EncouragementEngine.workoutSetMessage(
            exercise: exercise,
            repsJustLogged: reps,
            totalSetsThisWeekForMuscle: weekCountAfter
        ) {
            toasts.workoutMilestone(milestone)
        } else {
            toasts.show(Toast(
                title: "Set saved",
                detail: (tracksWeight ? weight : nil).map { "\(Units.formatWeightWithUnit(lb: $0, system: unitSystem, decimals: 0)) × \(reps)" } ?? "\(reps) \(unitWord(reps)) · ~\(Int(kcal)) cal",
                accent: .win,
                symbol: "checkmark.seal.fill"
            ))
        }
        // The wheel keeps its value: the next set is usually the same count.
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
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .onReceive(ticker) { _ in tick() }
        .sheet(isPresented: $showInfo) {
            ExerciseInfoSheet(exercise: exercise, profile: profile)
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

    /// The four holds people actually pick, one tap each. The wheel below stays
    /// for everything else — same presets-plus-fine-control shape the live
    /// session picker uses for expected time.
    private let presets = [30, 45, 60, 90]

    @ViewBuilder
    private var pickerSection: some View {
        VStack(spacing: 8) {
            Text("Set hold duration".uppercased())
                .font(.system(size: 10)).tracking(2)
                .foregroundStyle(theme.dim)
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { secs in
                    Button {
                        pickedSeconds = secs
                        Haptics.selection()
                    } label: {
                        Text(formattedHoldDuration(secs))
                    }
                    .tactile(.pill, fill: pickedSeconds == secs ? theme.accent : nil)
                }
            }
            Picker("Duration", selection: $pickedSeconds) {
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
    private var startButton: some View {
        Button {
            secondsRemaining = pickedSeconds
            Haptics.bump()
        } label: {
            Text("Start hold")
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
                Text(formattedHoldDuration(totalSecSession))
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
        let kcal = Repos.setCaloriesEstimate(
            exercise: exercise,
            reps: 1,
            holdSeconds: secs,
            bodyWeightLb: profile.weightLb
        )
        let dto = WorkoutSetDTO(
            userId: profile.id,
            exerciseId: exercise.id,
            reps: 1,
            caloriesEst: kcal,
            holdSeconds: secs
        )
        guard Repos.addSet(ctx, dto) else { return }
        toasts.show(Toast(
            title: "Hold logged",
            detail: "\(formattedHoldDuration(secs)) · ~\(Int(kcal)) cal",
            accent: .win,
            symbol: "checkmark.seal.fill"
        ))
    }
}
