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

import SwiftUI

struct ExerciseInfoSheet: View {
    let exercise: ExerciseDTO
    let profile: ProfileDTO
    /// Today's tally, passed by the exercise list: reps, minutes for a
    /// duration exercise, or holds for an isometric. The rep counter and hold
    /// timer leave this at zero, which hides the block.
    var todayCount: Int = 0
    var todayKcal: Double = 0

    @Environment(\.theme) private var theme

    // On-device AI fills in muscles + benefits for custom movements we have no
    // curated copy for. Nil until (and unless) generation succeeds.
    @State private var ai: GeneratedExerciseInsight?
    @State private var aiLoading = false

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
            exercise: exercise, reps: reps, holdSeconds: holdSeconds,
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
