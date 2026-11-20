// On-device "did you mean" for the Add Food search. When the typed query finds
// nothing or only loose matches (a misspelling the vocabulary fix can't reach,
// a describing phrase like "that crunchy cereal with marshmallows"), Apple
// Intelligence proposes a few plain-word alternative SEARCH QUERIES. It never
// produces food data: every suggestion is kept only if it finds at least one
// food in the normal search, and the numbers always come from the database.
//
// Same shape as MealParseService: when the model is unavailable, Apple
// Intelligence is off, or anything fails, `suggestions(for:)` returns nil and
// the UI shows nothing extra. FoundationModels needs no entitlement.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// What the on-device model fills in. iOS 26+ only. Text queries only — no nutrition fields.
@available(iOS 26.0, *)
@Generable
private struct FoodQueryDraft {
    @Guide(description: "One to three short alternative food-search queries, plain words, no numbers, no brands the person did not mention")
    var queries: [String]
}
#endif

public final class FoodQueryRewriteService: @unchecked Sendable {
    public static let shared = FoodQueryRewriteService()
    private init() {}

    /// True only when the on-device model can actually run right now.
    public var isAvailable: Bool { OnDeviceModel.isAvailable }

    /// Alternative queries for `raw` that each find at least one food, best
    /// first, at most 3. nil when AI is unavailable or generation fails; an
    /// empty array never comes back (nil instead), so callers show nothing.
    public func suggestions(for raw: String) async -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard let draft = await OnDeviceModel.generate(instructions: Self.instructions, { session in
                try await session.respond(
                    to: "Food search the person typed: \"\(trimmed)\".",
                    generating: FoodQueryDraft.self
                ).content
            }) else { return nil }
            var kept: [String] = []
            for candidate in FoodSearch.cleanSuggestions(draft.queries, raw: trimmed) {
                // Only offer a rewrite the normal search can answer.
                if !(await FoodSearch.search(candidate)).foods.isEmpty { kept.append(candidate) }
            }
            return kept.isEmpty ? nil : kept
        }
        #endif
        return nil
    }

    private static let instructions = """
    You help someone search a food database. The text they typed found nothing \
    useful, perhaps because of a misspelling or because they described the food \
    instead of naming it. Reply with one to three short alternative search \
    queries in plain everyday words — the most likely food names. Never add a \
    brand the person did not mention, never include numbers, and never output \
    calories or nutrition facts. You provide search text only.
    """
}
