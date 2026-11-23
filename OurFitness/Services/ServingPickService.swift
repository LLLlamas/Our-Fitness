// On-device "typical pick" for the Add Food search. Given the top results the
// normal search already ranked, Apple Intelligence names the ONE a typical
// person would log for a single meal (the plain, regular version unless the
// query names a variant; never a bulk package) and how many of its listed
// serving they'd usually eat. It never produces food data: the answer is an
// option number + a servings count, validated by `ServingPick.validated`
// (must be a shown result, amount snapped to 0.5/0.75/1/1.5/2), and the
// numbers always come from that result's database row.
//
// Same shape as FoodQueryRewriteService: nil when the model is unavailable,
// Apple Intelligence is off, or anything fails — the UI then shows the
// deterministic order unchanged.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
/// What the on-device model fills in. iOS 26+ only. No nutrition fields.
@available(iOS 26.0, *)
@Generable
private struct ServingPickDraft {
    @Guide(description: "The number of the listed option a typical person would log for one meal")
    var choice: Int

    @Guide(description: "How many of that option's listed serving one person usually eats in one meal: 0.5, 0.75, 1, 1.5 or 2")
    var servings: Double
}
#endif

public final class ServingPickService: @unchecked Sendable {
    public static let shared = ServingPickService()
    private init() {}

    /// True only when the on-device model can actually run right now.
    public var isAvailable: Bool { OnDeviceModel.isAvailable }

    /// The typical pick among the first `ServingPick.candidateCount` of
    /// `results` for `query`; nil when there's nothing to choose, AI is
    /// unavailable, generation fails, or the answer doesn't validate.
    public func pick(for query: String, among results: [CommonFood]) async -> ServingPick? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = Array(results.prefix(ServingPick.candidateCount))
        guard !trimmed.isEmpty, candidates.count >= 2 else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let options = candidates.enumerated()
                .map { "\($0.offset + 1). \($0.element.name) — serving: \($0.element.servingLabel)" }
                .joined(separator: "\n")
            guard let draft = await OnDeviceModel.generate(instructions: Self.instructions, { session in
                try await session.respond(
                    to: "Search: \"\(trimmed)\"\nOptions:\n\(options)",
                    generating: ServingPickDraft.self
                ).content
            }) else { return nil }
            return ServingPick.validated(choice: draft.choice, servings: draft.servings, candidates: candidates)
        }
        #endif
        return nil
    }

    private static let instructions = """
    Someone is logging a meal and searched a food database. From the numbered \
    options, choose the one a typical person means: the plain, regular, \
    everyday version, unless the search names a flavor, brand or variant. \
    Never choose a bulk, family or institutional package. Then say how many of \
    that option's listed serving one person usually eats in one meal (for \
    example a bowl of cereal, a slice of cheese, a cup of milk). Reply with the \
    option number and servings only — never calories or nutrition facts.
    """
}
