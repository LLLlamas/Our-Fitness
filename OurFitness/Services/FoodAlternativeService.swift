// On-device AI food alternative suggestions.
//
// Given a food the user wants to swap out, this service asks Apple's on-device
// model (FoundationModels, iOS 26+) to suggest 2–3 healthier alternatives whose
// names are then resolved through `FoodParser.resolve(items:)` so every macro
// number still comes from `CommonFoods`/`SQLiteFoodDatabase` — never from the AI.
//
// Each alternative now carries a `whyBetter` string — a brief, research-backed
// reason the alternative is healthier (1 sentence max, factual claim only, no
// invented citations and no disease-treatment language).
//
// Mode-awareness:
//   • Build  → alternatives with similar or higher protein content
//   • Circuit → alternatives lower in saturated fat and sodium, higher in
//               fiber and omega-3 sources
//
// THE SAFETY RULE (mirrors MealParseService / ExerciseInsightService):
//   • The model outputs TEXT ONLY — food names and one-sentence reasons.
//   • The @Generable shape carries NO nutrition fields.
//   • The prompt forbids nutrition numbers, medical claims, and fabricating foods.
//   • A name the food database cannot match is silently dropped — the resolver
//     makes it impossible for the model to invent nutrition.
//
// AI works from nutritional research alone — no user history is required to
// produce results. History (recentFoodNames / favoriteFoodNames) is an OPTIONAL
// enrichment, not a gate.
//
// Fully optional. On iOS < 26, without Apple Intelligence, or on any failure,
// `alternatives(for:...)` returns an empty array and callers degrade gracefully.
// FoundationModels needs no entitlement; this lives in Services/ (Domain is
// framework-free).

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - @Generable shapes (iOS 26+ only)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct AlternativeDraft {
    @Guide(description: "2 to 3 healthier alternative foods backed by nutritional research.")
    var alternatives: [AlternativeItemDraft]
}

@available(iOS 26.0, *)
@Generable
private struct AlternativeItemDraft {
    @Guide(description: "The alternative food in its simplest common name a nutrition database would recognise (e.g. 'Greek yogurt', 'brown rice', 'salmon fillet'). Plain everyday words. Do NOT include calories, macros, or any nutrition numbers.")
    var name: String

    @Guide(description: "One short sentence explaining why this food is a healthier swap, based on nutritional research. Focus on a specific nutrient or health benefit (e.g. 'Higher in fiber and has a lower glycemic index than white rice.' or 'Rich in omega-3 fatty acids that support heart health.'). No invented study citations. No medical claims about treating disease. Maximum 20 words.")
    var whyBetter: String
}
#endif

// MARK: - Public result type

/// A resolved food alternative with a research-backed reason from the on-device model.
/// Nutrition comes from the food database; `whyBetter` comes from the AI (text only).
public struct FoodAlternative: Sendable {
    /// The resolved food item with real USDA-backed nutrition.
    public let item: FoodParser.ParsedItem
    /// AI-generated one-sentence reason the alternative is a healthier swap.
    public let whyBetter: String
}

// MARK: - Service

public final class FoodAlternativeService: @unchecked Sendable {

    public static let shared = FoodAlternativeService()
    private init() {}

    private let cacheVersion = "v2"
    private let cachePrefix = "foodAlternatives"

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

    /// Derive the most frequently logged food names from the last 30 days of a
    /// user's food log. Returns the top 8 names (by log count), de-duplicated and
    /// in descending frequency order. Pass these into `alternatives(for:...)` as
    /// `recentFoodNames` so the model understands the user's existing palette.
    ///
    /// Pure function — no I/O, safe to call on any thread.
    public func learnedFrequents(from logs: [FoodLogEntryDTO]) -> [String] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
        let recent = logs.filter { $0.timestamp >= cutoff }

        // Count occurrences of each distinct food name.
        var tally: [String: Int] = [:]
        for entry in recent {
            // Prefer the curated foodId (gives canonical casing); fall back to
            // whatever custom name the user typed.
            let rawName: String?
            if let id = entry.foodId, !id.isEmpty {
                rawName = id
            } else if let custom = entry.customName, !custom.isEmpty {
                rawName = custom
            } else {
                rawName = nil
            }
            guard let name = rawName else { continue }
            let key = name.lowercased()
            tally[key, default: 0] += 1
        }

        return tally
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { $0.key }
    }

    /// Suggest healthier alternatives for `foodName`, resolved through
    /// `FoodParser` so macros are always database-backed. Each result carries
    /// a `whyBetter` string — a brief, research-backed reason the swap is healthier.
    ///
    /// The AI works from nutritional research alone. `recentFoodNames` and
    /// `favoriteFoodNames` are optional context that may improve relevance but
    /// are not required to produce results.
    ///
    /// - Parameters:
    ///   - foodName: The food the user wants to swap (e.g. "white rice").
    ///   - mode: `.build` = protein focus; `.circuit` = sat-fat/sodium/fiber focus.
    ///   - recentFoodNames: Foods the user already eats (optional context).
    ///     Use `learnedFrequents(from:)` to derive these from the log history.
    ///   - favoriteFoodNames: Additional foods the user has marked as favourites (optional).
    ///
    /// - Returns: Resolved `FoodAlternative` list (empty on unavailability or failure).
    public func alternatives(
        for foodName: String,
        mode: Mode,
        recentFoodNames: [String] = [],
        favoriteFoodNames: [String] = []
    ) async -> [FoodAlternative] {
        let cleanName = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return [] }
        guard isAvailable else { return [] }

        // Check cache first — avoid re-running the model for the same query.
        let key = cacheKey(for: cleanName, mode: mode)
        if let cached = cachedEntries(for: key) {
            return resolve(entries: cached)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession { Self.systemInstructions }
                let userPrompt = buildPrompt(
                    foodName: cleanName,
                    mode: mode,
                    recentFoodNames: recentFoodNames,
                    favoriteFoodNames: favoriteFoodNames
                )
                let response = try await session.respond(
                    to: userPrompt,
                    generating: AlternativeDraft.self
                )
                let entries = cleanEntries(response.content.alternatives)
                guard !entries.isEmpty else { return [] }
                storeEntries(entries, for: key)
                return resolve(entries: entries)
            } catch {
                return []
            }
        }
        #endif
        return []
    }

    /// Background prefetch — call this when a food is logged so the cache is warm
    /// before the user navigates to Smarter Swaps. Fire-and-forget; silently drops errors.
    public func prefetch(for foodName: String, mode: Mode) {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            _ = await self.alternatives(for: foodName, mode: mode)
        }
    }

    // MARK: - Prompt construction

    private static let systemInstructions = """
    You are a practical nutrition researcher. Given a food, suggest 2 to 3 healthier \
    alternatives backed by nutritional science. For each alternative:
    - Choose a real, common food a standard nutrition database (such as USDA FoodData Central) \
    would recognise by name.
    - Use simple everyday names (e.g. "Greek yogurt", "salmon fillet", "lentil soup").
    - Provide one short sentence explaining the specific nutritional reason it is a healthier \
    swap (e.g. higher fiber, lower saturated fat, better omega-3 to omega-6 ratio, lower \
    glycemic index, higher protein density). Cite a specific nutrient or mechanism, not a \
    vague claim like "it is healthier."
    You provide food names and one-sentence reasons ONLY. Do NOT output calories, grams of \
    protein, carbs, fat, or any nutrition numbers — those are looked up separately. Do NOT \
    make disease-treatment claims. Do NOT invent foods. If unsure, suggest only alternatives \
    you are confident are real foods in common nutrition databases.
    """

    private func buildPrompt(
        foodName: String,
        mode: Mode,
        recentFoodNames: [String],
        favoriteFoodNames: [String]
    ) -> String {
        var parts: [String] = []

        parts.append("Food to find alternatives for: \"\(foodName)\".")

        switch mode {
        case .build:
            parts.append("Goal: Build mode (gaining lean muscle mass). Prioritise alternatives with similar or higher protein content. Whole-food protein sources are preferred.")
        case .circuit:
            parts.append("Goal: Circuit mode (losing body fat and improving heart-health markers). Prioritise alternatives that are lower in saturated fat and sodium, higher in fibre, and ideally rich in omega-3 fatty acids.")
        }

        let contextFoods = (recentFoodNames + favoriteFoodNames)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
        let unique = (NSOrderedSet(array: contextFoods).array as? [String] ?? contextFoods).prefix(10)
        if !unique.isEmpty {
            let list = unique.joined(separator: ", ")
            parts.append("Foods this person already eats and likes: \(list). Suggestions that complement or relate to these are welcome, but do not repeat them.")
        }

        parts.append("Suggest 2 to 3 alternatives. For each: the food name and one sentence explaining the specific nutritional reason it is a healthier swap.")

        return parts.joined(separator: " ")
    }

    // MARK: - Defensive cleanup

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func cleanEntries(_ drafts: [AlternativeItemDraft]) -> [[String: String]] {
        drafts
            .compactMap { draft -> [String: String]? in
                let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let why = draft.whyBetter.trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.count > 1 else { return nil }
                return ["name": name, "why": why.isEmpty ? "" : why]
            }
            .prefix(3)
            .map { $0 }
    }
    #endif

    // MARK: - Resolution

    /// Resolve alternative name+why pairs through FoodParser (CommonFoods + SQLite USDA).
    /// Names that cannot be matched are silently dropped — the model can never
    /// supply nutrition numbers for unrecognised foods.
    private func resolve(entries: [[String: String]]) -> [FoodAlternative] {
        var result: [FoodAlternative] = []
        for entry in entries {
            guard let name = entry["name"], !name.isEmpty else { continue }
            let why = entry["why"] ?? ""
            let items = [FoodParser.ExtractedItem(name: name, quantity: 1.0)]
            let parsed = FoodParser.resolve(items: items)
            guard let parsedItem = parsed.recognized.first else { continue }
            result.append(FoodAlternative(item: parsedItem, whyBetter: why))
        }
        return result
    }

    // MARK: - Cache

    private func cacheKey(for foodName: String, mode: Mode) -> String {
        let sanitised = foodName
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: "_")
        return "\(cachePrefix).\(cacheVersion).\(sanitised).\(mode.rawValue)"
    }

    /// Load cached alternative entries (name+why dicts, not resolved items — the DB
    /// may have changed so we re-resolve on every cold read).
    private func cachedEntries(for key: String) -> [[String: String]]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([[String: String]].self, from: data),
              !entries.isEmpty else { return nil }
        return entries
    }

    private func storeEntries(_ entries: [[String: String]], for key: String) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
