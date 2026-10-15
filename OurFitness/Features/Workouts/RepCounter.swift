// Friction-free set counter for any exercise. Tap +1 per rep (or per minute for
// a duration exercise), Save set commits a WorkoutSet. Shows a weight field only
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

    @State private var reps: Int = 0
    @State private var weightStr: String = ""
    @State private var setsLogged: Int = 0
    @State private var showInfo = false
    @State private var lastProjection: String?
    @State private var prefilledWeight = false
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
            counterDisplay
            tapButton
            bumpRow
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
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .onAppear { prefillWeight() }
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
        VStack(spacing: 0) {
            AnimatedNumber(
                Double(reps),
                font: .system(size: 120, weight: .semibold),
                color: theme.accent
            )
            if isMinutes {
                Text("minutes")
                    .font(.caption).tracking(1)
                    .foregroundStyle(theme.dim)
            }
        }
    }

    @ViewBuilder
    private var tapButton: some View {
        Button {
            reps += 1
        } label: {
            Text(isMinutes ? "+1 min" : "+1 rep")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 88)
        }
        .tactile(.primary, fullWidth: true)
    }

    /// Coarse adjustments beside the +1 tap target. A 12-rep set was 12 taps plus
    /// Save; with these it's two. −1 is what makes overshooting a +10 fixable
    /// without Clear wiping the count.
    @ViewBuilder
    private var bumpRow: some View {
        HStack(spacing: 8) {
            Button {
                reps = max(0, reps - 1)
                Haptics.bump()
            } label: { Text("−1") }
            .tactile(.bump)
            .disabled(reps == 0)
            .opacity(reps == 0 ? 0.5 : 1)

            Button {
                reps += 5
                Haptics.bump()
            } label: { Text("+5") }
            .tactile(.bump)

            Button {
                reps += 10
                Haptics.bump()
            } label: { Text("+10") }
            .tactile(.bump)
        }
        .frame(maxWidth: .infinity)
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
                reps = 0
                Haptics.warn()
            } label: {
                Text("Clear")
            }
            .tactile(.secondary)

            Button {
                saveSet()
            } label: {
                Text("Save set")
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

        // The projection's math is per-rep, so it only speaks for rep sets.
        lastProjection = isMinutes ? nil : EncouragementEngine.repProjection(
            exercise: exercise,
            repsLogged: reps,
            totalCaloriesToday: caloriesTodayBefore,
            bodyWeightLb: profile.weightLb
        )

        // Weekly volume milestone — fires only at defined set counts.
        if let milestone = EncouragementEngine.workoutSetMessage(
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
                        Text(shortDurationLabel(secs))
                    }
                    .tactile(.pill, fill: pickedSeconds == secs ? theme.accent : nil)
                }
            }
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
}
