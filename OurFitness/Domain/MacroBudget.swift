// Remaining macro / micronutrient budget for a day = targets − today's totals.
// Pure Domain. Powers the Circuit heart-health panel (fiber floor + sodium /
// added-sugar / saturated-fat caps) and "X to go" copy.
//
// Convention (matches RemainingMacros): for CAPS (sodium, added sugar, saturated
// fat) the value is how much room is LEFT under the cap — negative once exceeded.
// For the fiber FLOOR the value is signed distance to the floor — negative until
// the floor is met, positive once cleared. The four micro fields are nil in Build
// mode (no caps configured), so the UI can drive a Circuit-only panel off them.

import Foundation

public enum MacroBudget {

    public static func remaining(totals: DailyTotals, targets: MacroTargets) -> RemainingMacros {
        RemainingMacros(
            calories: targets.calories - totals.calories,
            proteinG: targets.proteinG - totals.proteinG,
            carbsG: targets.carbsG - totals.carbsG,
            fatG: targets.fatG - totals.fatG,
            sodiumMg: targets.sodiumMgMax.map { $0 - totals.sodiumMg },
            addedSugarG: targets.addedSugarGMax.map { $0 - totals.addedSugarG },
            saturatedFatG: targets.saturatedFatGMax.map { $0 - totals.saturatedFatG },
            fiberG: targets.fiberGMin.map { totals.fiberG - $0 }   // negative until floor met
        )
    }

    /// Same budget, but the three CAP fields go nil when the day's log can't
    /// actually account for that nutrient (`capCoverage(...) == .none`) — so a
    /// caller can never read "1500 mg of room left" off a day whose foods carry
    /// no sodium figure at all. nil therefore means "no number to show", whether
    /// because the cap isn't configured (Build) or because nothing measured it.
    /// Use `capCoverage` alongside if you need to tell those two apart.
    /// Fiber is untouched: it IS carried by every curated food.
    public static func remaining(totals: DailyTotals, targets: MacroTargets,
                                 entries: [FoodLogEntryDTO]) -> RemainingMacros {
        var r = remaining(totals: totals, targets: targets)
        if capCoverage(entries: entries).level == .none {
            r.sodiumMg = nil
            r.addedSugarG = nil
            r.saturatedFatG = nil
        }
        return r
    }

    // MARK: - Cap coverage
    //
    // Sodium, added sugar and saturated fat are NOT in the curated food database
    // (`CommonFoods`) or the USDA table behind it — both carry calories, protein,
    // carbs, fat and fiber only. The one path that supplies them is a scanned
    // nutrition label, which writes all three together off the same panel.
    //
    // So we read provenance off the values themselves: a POSITIVE figure can only
    // have come from a label, and because labels fill all three at once, one
    // positive figure vouches for the other two on that entry (a label that
    // genuinely reads 0 g added sugar is a measured zero, not a gap). An entry
    // with all three at zero is a gap, not a food with no sodium.
    //
    // That rule is deliberately pessimistic in one corner: a label whose three
    // values are all genuinely 0 (black coffee, bottled water) reads as a gap.
    // It contributes nothing to the totals either way, and over-stating "we may
    // be missing some" is the safe direction for a cardiovascular-risk cap.
    //
    // Fiber has no coverage notion here — it comes from every curated food, so
    // the fiber floor is driven straight off `DailyTotals.fiberG` as before.

    /// How much of the day's cap nutrients the log can actually account for.
    public enum CapCoverageLevel: Equatable, Sendable {
        /// Nothing logged carried a sodium / added-sugar / saturated-fat figure.
        /// The totals are zero because the data is missing, not because intake was.
        case none
        /// Some entries carried label figures and some did not — the totals are a
        /// floor ("at least"), never the real intake.
        case partial
        /// Every logged entry carried label figures. The totals are the real intake.
        case full
    }

    /// Cap-nutrient coverage for a day, plus the counts behind it so the UI can
    /// say *how much* is missing. `measuredEntries`/`entryCount` are 0 when the
    /// coverage was inferred from totals alone (no entry list available).
    public struct CapCoverage: Equatable, Sendable {
        public let level: CapCoverageLevel
        public let entryCount: Int
        public let measuredEntries: Int

        public var unmeasuredEntries: Int { max(0, entryCount - measuredEntries) }

        public init(level: CapCoverageLevel, entryCount: Int, measuredEntries: Int) {
            self.level = level
            self.entryCount = entryCount
            self.measuredEntries = measuredEntries
        }
    }

    /// True when this entry's snapshot carries label-sourced cap figures.
    private static func hasCapData(_ p: PerServing) -> Bool {
        p.sodiumMg > 0 || p.addedSugarG > 0 || p.saturatedFatG > 0
    }

    /// Coverage from the day's log. An empty day is `.none` (nothing to measure).
    public static func capCoverage(entries: [FoodLogEntryDTO]) -> CapCoverage {
        guard !entries.isEmpty else {
            return CapCoverage(level: .none, entryCount: 0, measuredEntries: 0)
        }
        let measured = entries.reduce(into: 0) { acc, e in
            if hasCapData(e.perServing) { acc += 1 }
        }
        let level: CapCoverageLevel = measured == 0
            ? .none
            : (measured == entries.count ? .full : .partial)
        return CapCoverage(level: level, entryCount: entries.count, measuredEntries: measured)
    }

    /// Weaker fallback for callers that only have the summed day. A sum can prove
    /// that *something* was measured, never that everything was — so this returns
    /// `.partial` rather than `.full` whenever any cap figure is positive.
    public static func capCoverage(totals: DailyTotals) -> CapCoverage {
        let anyMeasured = totals.sodiumMg > 0 || totals.addedSugarG > 0 || totals.saturatedFatG > 0
        return CapCoverage(level: anyMeasured ? .partial : .none,
                           entryCount: 0, measuredEntries: 0)
    }
}
