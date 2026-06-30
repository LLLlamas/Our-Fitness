// On-device AI enrichment for CUSTOM exercises the user invents.
//
// Known exercises (pull-up, squat, deadlift…) keep their hand-curated,
// citation-backed metadata in Domain/ExerciseInfo.swift. When a user adds an
// exercise we don't recognise, this service asks Apple's on-device model
// (FoundationModels, iOS 26+) to describe its muscles and benefits in plain
// English — so the ⓘ info sheet says something useful instead of generic
// category defaults.
//
// Guardrails — AI never prescribes, it only suggests:
//   • Descriptive only. We do NOT let the model touch MET / calorie math, so
//     logged calorie estimates stay deterministic.
//   • General fitness guidance only — the prompt forbids medical claims and
//     fabricated study citations.
//   • Fully optional. On any device below iOS 26, without Apple Intelligence
//     enabled, or on failure, callers fall back to ExerciseInfo's defaults.
//
// Results are cached (per exercise identity) in UserDefaults so generation runs
// at most once per custom exercise.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Plain, cacheable result the info sheets render. Muscle names are raw —
/// the view layer runs them through `ExerciseInfo.plainMuscleList` for glosses.
public struct GeneratedExerciseInsight: Codable, Equatable, Sendable {
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    public var benefits: [String]

    public init(primaryMuscles: [String], secondaryMuscles: [String], benefits: [String]) {
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.benefits = benefits
    }
}

#if canImport(FoundationModels)
/// The structured shape the on-device model fills in. iOS 26+ only.
@available(iOS 26.0, *)
@Generable
private struct ExerciseInsightDraft {
    @Guide(description: "2 to 4 primary muscles this exercise works, in everyday words (e.g. 'chest', 'front of thighs').")
    var primaryMuscles: [String]

    @Guide(description: "0 to 4 secondary or stabiliser muscles, in everyday words.")
    var secondaryMuscles: [String]

    @Guide(description: "2 to 4 short, plain-English sentences on what this exercise does for the body. General fitness guidance only. Do NOT give medical advice, make health claims about diseases, or cite studies.")
    var benefits: [String]
}
#endif

public final class ExerciseInsightService: @unchecked Sendable {
    public static let shared = ExerciseInsightService()
    private init() {}

    private let cacheVersion = "v1"

    // MARK: - Availability

    /// True only when the on-device model can actually run right now.
    public var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            return SystemLanguageModel.default.availability == .available
            #else
            return false
            #endif
        }
        return false
    }

    // MARK: - Public API

    /// Returns a cached insight if present (instant, sync). Use this for the
    /// first render so a previously generated exercise shows immediately.
    public func cached(for exercise: ExerciseDTO) -> GeneratedExerciseInsight? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: exercise)) else { return nil }
        return try? JSONDecoder().decode(GeneratedExerciseInsight.self, from: data)
    }

    /// Generates (or returns cached) plain-language muscles + benefits for a
    /// custom exercise. Returns nil when AI is unavailable or generation fails —
    /// callers should fall back to `ExerciseInfo.meta(for:)`.
    public func insight(for exercise: ExerciseDTO) async -> GeneratedExerciseInsight? {
        if let hit = cached(for: exercise) { return hit }
        guard isAvailable else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession { Self.instructions }
                let response = try await session.respond(
                    to: prompt(for: exercise),
                    generating: ExerciseInsightDraft.self
                )
                let draft = response.content
                let insight = GeneratedExerciseInsight(
                    primaryMuscles: clean(draft.primaryMuscles, max: 4),
                    secondaryMuscles: clean(draft.secondaryMuscles, max: 4),
                    benefits: clean(draft.benefits, max: 4)
                )
                guard !insight.primaryMuscles.isEmpty || !insight.benefits.isEmpty else { return nil }
                store(insight, for: exercise)
                return insight
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    // MARK: - Prompt

    private static let instructions = """
    You are a knowledgeable, careful strength & conditioning coach. Given the \
    name of an exercise, describe which muscles it works and what it does for \
    the body in plain, encouraging English a beginner can understand. Keep \
    sentences short. Use everyday muscle names. This is general fitness \
    information only — never give medical advice, never claim it treats or \
    prevents any disease, and never cite studies or numbers you are unsure of.
    """

    private func prompt(for ex: ExerciseDTO) -> String {
        var parts = ["Exercise name: \"\(ex.name)\".",
                     "Type: \(ex.category.rawValue).",
                     ex.isIsometric ? "It is an isometric hold (no reps, held for time)."
                                    : "It is performed for \(ex.kind == .duration ? "time" : "reps")."]
        if let load = ex.loadLb, load > 0 {
            parts.append("Performed with about \(Int(load)) lb of load.")
        }
        if !ex.equipment.isEmpty {
            parts.append("Equipment: \(ex.equipment.map(\.rawValue).joined(separator: ", ")).")
        }
        return parts.joined(separator: " ")
    }

    /// Trim, drop blanks, cap count — defends the UI against odd model output.
    private func clean(_ items: [String], max: Int) -> [String] {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(max)
            .map { String($0) }
    }

    // MARK: - Cache

    private func cacheKey(for ex: ExerciseDTO) -> String {
        let identity = "\(ex.name.lowercased())|\(ex.category.rawValue)|\(Int(ex.loadLb ?? 0))|\(ex.isIsometric)"
        return "aiExerciseInsight.\(cacheVersion).\(identity)"
    }

    private func store(_ insight: GeneratedExerciseInsight, for ex: ExerciseDTO) {
        guard let data = try? JSONEncoder().encode(insight) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: ex))
    }
}
