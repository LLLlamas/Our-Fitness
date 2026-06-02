// On-device AI meal parser.
//
// Free-text meal logging ("two eggs, a flat white and some sourdough") is hard
// for the string-rule parser in `Domain/FoodParser.swift` to split reliably.
// This service asks Apple's on-device model (FoundationModels, iOS 26+) to do
// the PARSING only — break the sentence into distinct foods with a best-guess
// quantity — and hands those names straight back to `FoodParser` so the actual
// calorie/macro NUMBERS still come from `CommonFoods`/`FoodDatabase`.
//
// THE SAFETY RULE (mirrors Services/ExerciseInsightService.swift — "we do NOT
// let the model touch MET / calorie math"):
//   • The model extracts/normalises TEXT only: food name + quantity + unit.
//   • It NEVER produces calories or macros. The prompt forbids it, and the
//     @Generable shape has no numeric-nutrition fields to fill in.
//   • An extracted item that isn't found in the food database is treated as
//     unrecognised — exactly like the string parser does today. The model can
//     never invent a food's nutrition.
//
// Fully optional. On any device below iOS 26, without Apple Intelligence
// enabled, or on any failure, `parse` returns nil and callers fall back to the
// unchanged `FoodParser.parse(text:)` string path. FoundationModels needs no
// entitlement; this lives in Services/ (Domain stays framework-free).

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// The structured shape the on-device model fills in. iOS 26+ only.
/// Deliberately carries NO nutrition fields — the model cannot emit calories/macros.
@available(iOS 26.0, *)
@Generable
private struct MealParseDraft {
    @Guide(description: "Each distinct food or drink the person mentioned. Do NOT include foods they did not mention.")
    var items: [MealItemDraft]
}

@available(iOS 26.0, *)
@Generable
private struct MealItemDraft {
    @Guide(description: "The food or drink in its simplest common name (e.g. 'eggs', 'flat white', 'sourdough bread'). Plain everyday words, singular or as commonly searched.")
    var name: String

    @Guide(description: "Best-guess count or servings the person ate, as a number (e.g. 2 for 'two eggs', 1 for 'a coffee', 0.5 for 'half a bagel'). Use 1 when unsure.")
    var quantity: Double

    @Guide(description: "Optional natural unit if one was stated (e.g. 'slice', 'cup', 'bowl'). Leave empty if none. Never put nutrition, calories, or grams of macros here.")
    var unit: String?
}
#endif

public final class MealParseService: @unchecked Sendable {
    public static let shared = MealParseService()
    private init() {}

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

    /// Parse free text into extracted food items (TEXT only — no nutrition).
    /// Returns nil when AI is unavailable or generation fails; callers should then
    /// fall back to `FoodParser.parse(text:)`. The returned items must be resolved
    /// through `FoodParser.resolve(items:)` to get deterministic macros.
    public func parse(_ text: String) async -> [FoodParser.ExtractedItem]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard isAvailable else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession { Self.instructions }
                let response = try await session.respond(
                    to: "Meal description: \"\(trimmed)\".",
                    generating: MealParseDraft.self
                )
                let items = clean(response.content.items)
                return items.isEmpty ? nil : items
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    // MARK: - Prompt

    private static let instructions = """
    You split a casual meal description into the individual foods and drinks the \
    person ate. For each one, give its simplest common name and a best-guess \
    quantity (a count or number of servings). Only include foods the person \
    actually mentioned — never add foods they did not say. Use everyday names a \
    food-lookup database would recognise. You provide TEXT ONLY: do NOT output \
    calories, macros, grams of protein/carbs/fat, or any nutrition numbers — \
    those are looked up separately. If you are unsure of a quantity, use 1.
    """

    // MARK: - Defensive cleanup

    #if canImport(FoundationModels)
    /// Trim names, drop blanks, clamp quantities, cap the list — defends the
    /// downstream resolver against odd model output.
    @available(iOS 26.0, *)
    private func clean(_ drafts: [MealItemDraft]) -> [FoodParser.ExtractedItem] {
        drafts
            .map { draft -> FoodParser.ExtractedItem in
                let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let qty = draft.quantity.isFinite ? min(max(draft.quantity, 0), 20) : 1
                return FoodParser.ExtractedItem(name: name, quantity: qty == 0 ? 1 : qty)
            }
            .filter { $0.name.count > 1 }
            .prefix(12)
            .map { $0 }
    }
    #endif
}
