// On-device AI training-goal → exercise suggestions.
//
// Given a free-text goal ("I want a bigger back and shoulders"), this asks
// Apple's on-device model (FoundationModels, iOS 26+) to SELECT exercises from
// our curated research library (`ExerciseInfo.catalog`) and explain why each
// fits the goal. The model is grounded in the catalog we hand it — it picks
// existing exercise names; it never invents exercises, muscles, or MET values.
//
// THE SAFETY RULE (mirrors ExerciseInsightService / FoodAlternativeService):
//   • The model outputs TEXT ONLY — an exercise name (chosen from our list) and
//     a one-sentence reason. The @Generable shape carries no muscle/MET/calorie
//     fields; those stay deterministic in `ExerciseInfo`.
//   • A picked name we can't map back to the catalog is dropped — the model can
//     never conjure an exercise outside the curated research.
//   • Descriptive, general-fitness guidance only; the prompt forbids medical
//     claims and fabricated study citations.
//
// Fully optional. On iOS < 26, without Apple Intelligence, or on any failure,
// `picks(forGoal:)` returns an empty array and callers fall back to the
// deterministic `ExerciseGoalMatcher`. FoundationModels needs no entitlement;
// this lives in Services/ (Domain stays framework-free).

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - @Generable shapes (iOS 26+ only)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct WorkoutSuggestionDraft {
    @Guide(description: "3 to 5 exercises chosen from the provided list that best fit the person's goal, best first.")
    var picks: [WorkoutPickDraft]
}

@available(iOS 26.0, *)
@Generable
private struct WorkoutPickDraft {
    @Guide(description: "The exercise name, copied EXACTLY as written in the provided list (e.g. 'Pull-up', 'Overhead Press'). Do NOT invent exercises or use names not on the list.")
    var exerciseName: String

    @Guide(description: "One short, encouraging sentence on why this exercise serves the goal, referring to the muscles it works. General fitness guidance only — no medical claims, no study citations. Maximum 22 words.")
    var reason: String
}
#endif

// MARK: - Public result type

/// A model-selected exercise pick (text only). The caller maps `exerciseName`
/// back onto `ExerciseInfo.catalog` for the authoritative muscles / MET.
public struct WorkoutAIPick: Sendable {
    public let exerciseName: String
    public let reason: String
}

// MARK: - Service

public final class WorkoutSuggestionService: @unchecked Sendable {

    public static let shared = WorkoutSuggestionService()
    private init() {}

    // MARK: - Availability

    /// True only when the on-device model can run right now.
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

    /// Ask the model to pick exercises from `ExerciseInfo.catalog` for a free-text
    /// goal. Returns picks whose names resolve back to the catalog (others are
    /// dropped), de-duplicated, capped at `limit`. Empty on unavailability/failure.
    public func picks(forGoal goal: String, mode: Mode, limit: Int = 5) async -> [WorkoutAIPick] {
        let trimmed = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard isAvailable else { return [] }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession { Self.instructions }
                let response = try await session.respond(
                    to: prompt(forGoal: trimmed, mode: mode),
                    generating: WorkoutSuggestionDraft.self
                )
                return clean(response.content.picks, limit: limit)
            } catch {
                return []
            }
        }
        #endif
        return []
    }

    // MARK: - Prompt

    private static let instructions = """
    You are a knowledgeable, encouraging strength & conditioning coach. The user \
    tells you what they want to work on. You choose the best-fitting exercises \
    ONLY from the list of exercises you are given, and for each give one short, \
    plain-English reason it serves their goal, naming the muscles it trains. Use \
    the muscle information provided for each exercise — do not invent muscles. \
    This is general fitness information only: never give medical advice, never \
    claim it treats or prevents any disease, and never cite studies. Pick exercise \
    names EXACTLY as written in the list.
    """

    private func prompt(forGoal goal: String, mode: Mode) -> String {
        // Hand the model the curated catalog as ground truth: name + primary muscles.
        let menu = ExerciseInfo.catalog
            .map { "- \($0.name): \($0.muscleGroups.joined(separator: ", "))" }
            .joined(separator: "\n")
        let modeLine: String
        switch mode {
        case .build:
            modeLine = "They are gaining lean mass and training for hypertrophy — all else equal, lean toward weighted, progressable strength exercises (roughly 6–12 reps)."
        case .circuit:
            modeLine = "They are losing body fat and improving heart-health markers — all else equal, lean toward higher-calorie-burn, conditioning, and joint-friendly options. The goal still comes first."
        }
        return """
        Goal: "\(goal)".
        \(modeLine)

        Choose 3 to 5 exercises from this list (use the names exactly):
        \(menu)

        For each pick, give the exercise name and one sentence on why it fits the goal.
        """
    }

    // MARK: - Defensive cleanup

    #if canImport(FoundationModels)
    /// Keep only picks that map back to the catalog (canonicalising the name),
    /// drop duplicates and blanks, cap the count.
    @available(iOS 26.0, *)
    private func clean(_ drafts: [WorkoutPickDraft], limit: Int) -> [WorkoutAIPick] {
        var seen = Set<String>()
        var out: [WorkoutAIPick] = []
        for draft in drafts {
            guard let entry = ExerciseInfo.catalogEntry(named: draft.exerciseName) else { continue }
            guard seen.insert(entry.name).inserted else { continue }
            let reason = draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(WorkoutAIPick(exerciseName: entry.name, reason: reason))
            if out.count >= limit { break }
        }
        return out
    }
    #endif
}
