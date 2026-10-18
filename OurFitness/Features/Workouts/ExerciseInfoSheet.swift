// The ⓘ sheet behind every exercise — one sheet, the same for every profile.
//
// Opened from the Train tab's exercise rows (`ExercisesCard`) and from the rep
// counter / isometric timer. It used to exist twice, with the same content in
// two layouts and two copies of the AI loader.
//
// Content sources, in priority order and never invented:
//   • Movement.postExerciseHint — researched recovery + spine-safety form cues
//     (named parenting movements get specific cues citing McGill & Cholewicki).
//   • ExerciseInfo.meta — curated muscles / benefits / MET for known exercises.
//   • ExerciseInsightService — on-device AI, ONLY for movements neither library
//     recognises, and only descriptively (never calorie math). iOS 26+; any
//     older device, Apple Intelligence off, or a failure falls back silently.
//
// Beyond the content above the sheet carries two things that belong to the
// exercise itself, so there is no second per-exercise sheet:
//   • Weight — for an exercise with a fixed load (Lifted Baby 30 lb), edit it
//     via `Repos.updateExercise`. Applies to reps logged from now on; past reps
//     keep the weight they were done at (stamped on each row).
//   • Your progress — last day + best, opening `ExerciseProgressSheet` (the one
//     per-exercise history view).
// The exercise is re-read live (`current`) so an edited weight shows at once.

import SwiftUI
import SwiftData

struct ExerciseInfoSheet: View {
    let exercise: ExerciseDTO
    let profile: ProfileDTO
    /// Today's tally, passed by the exercise list: reps, minutes for a
    /// duration exercise, or holds for an isometric. The rep counter and hold
    /// timer leave this at zero, which hides the block.
    var todayCount: Int
    var todayKcal: Double

    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var ctx
    @EnvironmentObject private var toasts: ToastCenter
    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    // Profile-scoped at the query level. The exercise row is read live so a
    // weight edit shows immediately (the `exercise` value is a snapshot taken
    // when the sheet opened); the sets are this exercise's whole history.
    @Query private var exerciseModels: [ExerciseModel]
    @Query private var setModels: [WorkoutSetModel]

    @State private var memo = ExerciseHistoryMemo()
    @State private var showProgress = false
    @State private var editingWeight = false
    @State private var weightDraft = ""
    @State private var weightError: String?
    @FocusState private var weightFocused: Bool

    // On-device AI fills in muscles + benefits for custom movements we have no
    // curated copy for. Nil until (and unless) generation succeeds.
    @State private var ai: GeneratedExerciseInsight?
    @State private var aiLoading = false

    init(exercise: ExerciseDTO, profile: ProfileDTO, todayCount: Int = 0, todayKcal: Double = 0) {
        self.exercise = exercise
        self.profile = profile
        self.todayCount = todayCount
        self.todayKcal = todayKcal
        let uid = profile.id
        let exId = exercise.id
        _exerciseModels = Query(
            filter: #Predicate<ExerciseModel> { $0.profileId == uid && $0.id == exId }
        )
        _setModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid && $0.exerciseId == exId },
            sort: \.timestamp, order: .reverse
        )
    }

    /// The exercise as stored right now (falls back to the opening snapshot if
    /// the row is gone).
    private var current: ExerciseDTO { exerciseModels.first?.snapshot ?? exercise }

    private var info: ExerciseInfo.Meta { ExerciseInfo.meta(for: exercise) }
    private var hint: Movement.PostExerciseHint { Movement.postExerciseHint(for: exercise) }

    /// Eligible for AI enrichment only when NEITHER research library knows this
    /// movement — curated strength exercises and the seeded parenting lifts keep
    /// their hand-written copy.
    private var canUseAI: Bool {
        !ExerciseInfo.hasCuratedMeta(for: exercise) && !Movement.hasNamedHint(for: exercise)
    }
    private var usingAI: Bool { ai != nil }

    // Parenting movements aren't in ExerciseInfo's named library, so their real
    // muscle list lives on the Movement hint — prefer it over category defaults.
    private var displayPrimary: [String] {
        if let ai, !ai.primaryMuscles.isEmpty { return ai.primaryMuscles }
        if Movement.hasNamedHint(for: exercise) { return hint.musclesWorked }
        return info.muscleGroups
    }
    private var displayBenefits: [String] {
        if let ai, !ai.benefits.isEmpty { return ai.benefits }
        return info.benefits
    }

    /// Sample burn at the user's body weight, through the same per-set
    /// estimator every logging surface writes with — so the sample matches
    /// what a logged set will actually store.
    private func sampleCal(reps: Int, holdSeconds: Int? = nil) -> Int {
        Int(CalorieEstimator.caloriesForSet(
            exercise: current, reps: reps, holdSeconds: holdSeconds,
            bodyWeightLb: profile.weightLb
        ))
    }

    private var sampleCalLabel: String {
        if exercise.isIsometric {
            return "~\(sampleCal(reps: 1, holdSeconds: 30)) cal / 30s · ~\(sampleCal(reps: 1, holdSeconds: 60)) cal / 60s at your weight"
        }
        if exercise.kind == .duration {
            // A duration exercise's `reps` are minutes.
            return "~\(sampleCal(reps: 10)) cal per 10 min at your weight"
        }
        return "~\(sampleCal(reps: 10)) cal per 10 reps at your weight"
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

                if aiLoading { aiLoadingRow }
                muscleSection
                if let line = oneLiner {
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                todaySection
                progressSection
                weightSection
                if usingAI { aiAttribution }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium])
        .presentationBackground(theme.bg)
        .presentationDragIndicator(.visible)
        .task(id: exercise.id) { await loadAIIfNeeded() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
        .sheet(isPresented: $showProgress) {
            ExerciseProgressSheet(profile: profile, exercise: current)
        }
    }

    /// The single AI loader.
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

    // MARK: - Sections

    @ViewBuilder
    private var aiLoadingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Generating insights with Apple Intelligence…")
                .font(.caption).foregroundStyle(theme.dim)
        }
    }

    /// One short sentence (≤ 25 words): the first form cue for loaded movements,
    /// otherwise the first benefit — each cut to its first sentence. Nothing shows
    /// if no candidate is that short (cutting mid-sentence would mislead).
    private var oneLiner: String? {
        for text in hint.formCues + displayBenefits {
            let first = text.components(separatedBy: ". ").first?
                .trimmingCharacters(in: CharacterSet(charactersIn: ". ")) ?? ""
            if !first.isEmpty, first.split(separator: " ").count <= 25 { return first + "." }
        }
        return nil
    }

    @ViewBuilder
    private var muscleSection: some View {
        Text(displayPrimary.joined(separator: " · "))
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(theme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var todaySection: some View {
        if todayCount > 0 {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accent)
                    Text("Today")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                }
                Text("\(todayTallyLabel) · ~\(Int(todayKcal)) cal burned")
                    .font(.callout)
                    .foregroundStyle(theme.text)
            }
        }
    }

    /// Hold first: an isometric is also `.duration` kind.
    private var todayTallyLabel: String {
        if exercise.isIsometric { return "\(todayCount) hold\(todayCount == 1 ? "" : "s")" }
        if exercise.kind == .duration { return "\(todayCount) min" }
        return "\(todayCount) rep\(todayCount == 1 ? "" : "s")"
    }

    // MARK: - Your progress

    private var historyFold: ExerciseHistoryFold {
        memo.fold(for: ExerciseHistoryFold.signature(models: setModels, exercise: current)) {
            ExerciseHistoryFold.make(exercise: current, rows: setModels.map(\.snapshot))
        }
    }

    /// "Best day · 38 reps (Oct 2)" — only once there are 2+ days; the first
    /// days are the baseline, not a record.
    private func bestLine(_ fold: ExerciseHistoryFold) -> String? {
        guard fold.bests.dayCount >= RepHistory.minHistoryDaysForBest else { return nil }
        if RepHistory.measure(for: current) == .holdSeconds {
            return fold.bests.longestHold.map {
                "Longest hold · \(RepHistory.durationText(seconds: $0.amount)) (\(Dates.formatShort($0.dayKey)))"
            }
        }
        return fold.bests.bestDay.map {
            "Best day · \(ProgressFormat.amount($0.amount, measure: RepHistory.measure(for: current))) (\(Dates.formatShort($0.dayKey)))"
        }
    }

    /// "Today · 50 lb × 30 · 55 lb × 8" — the same reps-at-weight line every list prints.
    private func lastLine(_ last: RepHistory.DayTally) -> String {
        let system = unitSystem
        let summary = RepHistory.summary(last) { ProgressFormat.weight($0, system: system) }
        return "\(ProgressFormat.relativeDayLabel(last.key)) · \(summary)"
    }

    @ViewBuilder
    private var progressSection: some View {
        let fold = historyFold
        if let last = fold.days.first {
            Button {
                Haptics.tap()
                showProgress = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 11)).foregroundStyle(theme.accent)
                            Text("Your progress")
                                .font(.caption).tracking(2).textCase(.uppercase)
                                .foregroundStyle(theme.dim)
                        }
                        Text(lastLine(last))
                            .font(.callout).foregroundStyle(theme.text)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if let best = bestLine(fold) {
                            Text(best).font(.caption).foregroundStyle(theme.dim)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.dim)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this exercise's history and comparisons")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your progress")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                Text("Nothing logged yet. Your history starts with the first one.")
                    .font(.callout).foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Fixed weight

    private func beginEditingWeight(_ lb: Double) {
        weightDraft = ProgressFormat.weightNumber(lb, system: unitSystem)
        weightError = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { editingWeight = true }
        weightFocused = true
    }

    private func cancelEditingWeight() {
        weightFocused = false
        weightError = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { editingWeight = false }
    }

    private func saveWeight() {
        let text = weightDraft.replacingOccurrences(of: ",", with: ".")
        // Canonical to 0.01 lb, so a metric entry stores the same weight as its lb twin.
        let lb = Units.parseWeightToLb(text, system: unitSystem).map(RepHistory.canonicalLb) ?? 0
        guard lb.isFinite, lb > 0, lb <= Repos.maxFixedLoadLb else {
            weightError = "Enter a weight above 0, up to \(ProgressFormat.weight(Repos.maxFixedLoadLb, system: unitSystem))."
            return
        }
        // Same weight as shown (metric round-trips through lb): nothing to write.
        if let old = current.loadLb,
           ProgressFormat.weightNumber(old, system: unitSystem) == ProgressFormat.weightNumber(lb, system: unitSystem) {
            cancelEditingWeight()
            return
        }
        guard Repos.updateExercise(ctx, id: exercise.id, loadLb: lb) else {
            weightError = "Couldn't save that weight. Try again."
            return
        }
        weightFocused = false
        weightError = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { editingWeight = false }
        toasts.show(Toast(
            title: "\(current.name) weight updated",
            detail: "Now \(ProgressFormat.weight(lb, system: unitSystem)). Past reps keep their weight.",
            accent: .ok, symbol: "scalemass.fill"))
    }

    @ViewBuilder
    private var weightSection: some View {
        if let load = current.loadLb {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weight")
                            .font(.caption).tracking(2).textCase(.uppercase)
                            .foregroundStyle(theme.dim)
                        Text("\(current.name) · \(ProgressFormat.weight(load, system: unitSystem))")
                            .font(.callout).foregroundStyle(theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !editingWeight {
                        Button("Update") { beginEditingWeight(load) }
                            .tactile(.pill)
                    }
                }
                if editingWeight {
                    HStack(spacing: 8) {
                        TextField("", text: $weightDraft)
                            .keyboardType(.decimalPad)
                            .padding(10).background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                            .foregroundStyle(theme.text)
                            .font(.system(.title3, design: .monospaced))
                            .focused($weightFocused)
                            .accessibilityLabel("New weight in \(Units.weightUnit(unitSystem))")
                        Text(Units.weightUnit(unitSystem))
                            .font(.callout).foregroundStyle(theme.dim)
                        Button("Save") { saveWeight() }
                            .tactile(.primary)
                        Button("Cancel") { cancelEditingWeight() }
                            .tactile(.ghost)
                    }
                    if let weightError {
                        Text(weightError)
                            .font(.caption).foregroundStyle(theme.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("A new weight applies to reps you log from now on. Reps already logged keep the weight they were done at.")
                    .font(.caption2).foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var aiAttribution: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10)).foregroundStyle(theme.accent)
            Text("Muscles and note written on-device by Apple Intelligence.")
                .font(.caption2).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
