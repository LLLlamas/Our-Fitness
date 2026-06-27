// On-device AI "what are you in the mood for?" meal ideas.
//
// Given a free-text craving with loose constraints ("not that hungry but I need
// at least 500 calories and a little protein, maybe something salty"), this asks
// Apple's on-device model (FoundationModels, iOS 26+) to suggest real foods that
// fit. The model emits food NAMES + a one-line reason only; every calorie/macro
// number comes from `FoodParser.resolve` (CommonFoods / USDA), never the model.
//
// THE SAFETY RULE (mirrors MealParseService / FoodAlternativeService):
//   • The model outputs TEXT ONLY — a food name and a one-sentence reason.
//   • The @Generable shape carries NO nutrition fields.
//   • A name the food database cannot match is silently dropped — the resolver
//     makes it impossible for the model to invent nutrition.
//
// Personalisation: pass the user's recently-logged foods so ideas lean toward
// their palette. History is optional context, not a gate.
//
// Fully optional. On iOS < 26, without Apple Intelligence, or on any failure,
// `ideas(forCraving:...)` returns an empty array and callers fall back to the
// deterministic `MealCravingMatcher` ("recommend according to previous meals").

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - @Generable shapes (iOS 26+ only)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct MealIdeaDraft {
    @Guide(description: "3 to 5 real foods or simple meals that fit what the person is in the mood for.")
    var ideas: [MealIdeaItemDraft]
}

@available(iOS 26.0, *)
@Generable
private struct MealIdeaItemDraft {
    @Guide(description: "The food in its simplest common name a nutrition database would recognise (e.g. 'pretzels', 'beef jerky', 'miso soup', 'Greek yogurt'). Plain everyday words. Do NOT include calories, macros, or any nutrition numbers.")
    var name: String

    @Guide(description: "One short sentence on why this fits what they asked for (flavour, how filling, protein). No nutrition numbers, no medical claims. Maximum 18 words.")
    var why: String
}
#endif

// MARK: - Public result type

/// A resolved meal idea: a real, database-backed food plus the model's reason it
/// fits the craving. Nutrition comes from `item`; `why` is the AI's text.
public struct MealIdea: Sendable {
    public let item: FoodParser.ParsedItem
    public let why: String
}

// MARK: - Service

public final class MealIdeaService: @unchecked Sendable {

    public static let shared = MealIdeaService()
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

    /// Turn a free-text craving into resolved food ideas. Returns ideas whose names
    /// resolve to the food database (others dropped), capped at `limit`. Empty on
    /// unavailability or failure.
    public func ideas(
        forCraving craving: String,
        mode: Mode,
        recentFoodNames: [String] = [],
        limit: Int = 5
    ) async -> [MealIdea] {
        let trimmed = craving.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard isAvailable else { return [] }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession { Self.instructions }
                let response = try await session.respond(
                    to: prompt(craving: trimmed, mode: mode, recentFoodNames: recentFoodNames),
                    generating: MealIdeaDraft.self
                )
                return resolve(cleanEntries(response.content.ideas), limit: limit)
            } catch {
                return []
            }
        }
        #endif
        return []
    }

    // MARK: - Prompt

    private static let instructions = """
    You are a friendly, practical nutrition coach. The user tells you what they \
    are in the mood for, in casual words — they may mention a flavour (salty, \
    sweet, savory), how hungry they are, a rough calorie amount, and how much \
    protein they want. Suggest real, common foods that fit. Use simple everyday \
    names a standard food database would recognise. For each, give one short \
    sentence on why it fits. You provide food NAMES and reasons ONLY — never \
    calories, grams, or any nutrition numbers, which are looked up separately. \
    Do NOT invent foods or make medical claims. If unsure, suggest only foods you \
    are confident are real and common.
    """

    private func prompt(craving: String, mode: Mode, recentFoodNames: [String]) -> String {
        var parts = ["What they're in the mood for: \"\(craving)\"."]
        switch mode {
        case .build:
            parts.append("They are gaining lean muscle, so foods with solid protein are welcome.")
        case .circuit:
            parts.append("They are losing body fat and improving heart health, so leaner, higher-fibre, lower-sodium foods are welcome.")
        }
        let context = recentFoodNames.map { $0.lowercased() }.filter { !$0.isEmpty }
        let unique = (NSOrderedSet(array: context).array as? [String] ?? context).prefix(10)
        if !unique.isEmpty {
            parts.append("Foods this person already eats: \(unique.joined(separator: ", ")). Lean toward foods like these when it fits.")
        }
        parts.append("Suggest 3 to 5 foods. For each: the food name and one sentence on why it fits.")
        return parts.joined(separator: " ")
    }

    // MARK: - Defensive cleanup + resolution

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func cleanEntries(_ drafts: [MealIdeaItemDraft]) -> [(name: String, why: String)] {
        drafts.compactMap { draft in
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count > 1 else { return nil }
            let why = draft.why.trimmingCharacters(in: .whitespacesAndNewlines)
            return (name, why)
        }
    }
    #endif

    /// Resolve idea names through `FoodParser` (CommonFoods + USDA). Names that
    /// can't be matched are dropped — the model can never supply nutrition for an
    /// unrecognised food. De-duplicates by resolved food id.
    private func resolve(_ entries: [(name: String, why: String)], limit: Int) -> [MealIdea] {
        var seen = Set<String>()
        var out: [MealIdea] = []
        for entry in entries {
            let parsed = FoodParser.resolve(items: [FoodParser.ExtractedItem(name: entry.name, quantity: 1.0)])
            guard let item = parsed.recognized.first else { continue }
            guard seen.insert(item.food.id).inserted else { continue }
            out.append(MealIdea(item: item, why: entry.why))
            if out.count >= limit { break }
        }
        return out
    }
}
