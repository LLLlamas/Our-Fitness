import XCTest

final class MacroBudgetTests: XCTestCase {

    private func totals(cal: Int, p: Int, c: Int, f: Int,
                        fiber: Int = 0, sodium: Int = 0, sugar: Int = 0, satFat: Int = 0) -> DailyTotals {
        var t = DailyTotals()
        t.calories = cal; t.proteinG = p; t.carbsG = c; t.fatG = f
        t.fiberG = fiber; t.sodiumMg = sodium; t.addedSugarG = sugar; t.saturatedFatG = satFat
        return t
    }

    func test_macros_remaining_are_target_minus_total() {
        let targets = MacroTargets(calories: 2000, proteinG: 150, carbsG: 200, fatG: 60, stepsDaily: 8000)
        let r = MacroBudget.remaining(totals: totals(cal: 1200, p: 90, c: 100, f: 30), targets: targets)
        XCTAssertEqual(r.calories, 800)
        XCTAssertEqual(r.proteinG, 60)
        XCTAssertEqual(r.carbsG, 100)
        XCTAssertEqual(r.fatG, 30)
    }

    func test_build_targets_have_no_micro_caps() {
        // Build mode never configures the cardiometabolic caps.
        let v = Targets.ProfileVitals(sex: .male, weightLb: 180, heightIn: 70, age: 30, activity: .moderate)
        let targets = Targets.compute(fitnessGoal: .gain, vitals: v)
        let r = MacroBudget.remaining(totals: totals(cal: 0, p: 0, c: 0, f: 0), targets: targets)
        XCTAssertNil(r.sodiumMg)
        XCTAssertNil(r.addedSugarG)
        XCTAssertNil(r.saturatedFatG)
        XCTAssertNil(r.fiberG)
    }

    func test_circuit_caps_room_under_and_negative_when_over() {
        let v = Targets.ProfileVitals(sex: .female, weightLb: 160, heightIn: 65, age: 35, activity: .light)
        let targets = Targets.compute(fitnessGoal: .lose, vitals: v)
        // Sodium 1500 cap; log 1700 -> 200 over -> remaining negative.
        let r = MacroBudget.remaining(
            totals: totals(cal: 0, p: 0, c: 0, f: 0, sodium: 1700), targets: targets
        )
        XCTAssertNotNil(r.sodiumMg)
        XCTAssertEqual(r.sodiumMg, (targets.sodiumMgMax ?? 0) - 1700)
        XCTAssertLessThan(r.sodiumMg ?? 0, 0)
    }

    func test_circuit_fiber_is_negative_until_floor_met() {
        let v = Targets.ProfileVitals(sex: .female, weightLb: 160, heightIn: 65, age: 35, activity: .light)
        let targets = Targets.compute(fitnessGoal: .lose, vitals: v)
        let floor = targets.fiberGMin ?? 35
        // Below floor -> negative; at/above floor -> >= 0.
        let under = MacroBudget.remaining(totals: totals(cal: 0, p: 0, c: 0, f: 0, fiber: 10), targets: targets)
        XCTAssertEqual(under.fiberG, 10 - floor)
        XCTAssertLessThan(under.fiberG ?? 0, 0)
        let met = MacroBudget.remaining(totals: totals(cal: 0, p: 0, c: 0, f: 0, fiber: floor), targets: targets)
        XCTAssertEqual(met.fiberG, 0)
    }

    // MARK: - Cap coverage
    //
    // Sodium / added sugar / saturated fat exist in no curated or USDA food row —
    // only a scanned nutrition label supplies them. These assert we can tell
    // "nothing measured it" from "intake was low".

    private let uid = UUID()

    /// A curated-database log: calories…fiber, and nothing for the three caps.
    private func curatedEntry(cal: Int = 400, fiber: Int = 5) -> FoodLogEntryDTO {
        FoodLogEntryDTO(
            userId: uid, date: "2026-05-27", slot: .lunch, foodId: "oats",
            perServing: PerServing(calories: cal, proteinG: 20, carbsG: 40, fatG: 10,
                                   fiberG: fiber)
        )
    }

    /// A scanned-label log: carries the cap figures.
    private func labelEntry(sodium: Int = 480, sugar: Int = 12, satFat: Int = 4) -> FoodLogEntryDTO {
        FoodLogEntryDTO(
            userId: uid, date: "2026-05-27", slot: .snack, customName: "Scanned food",
            perServing: PerServing(calories: 200, proteinG: 8, carbsG: 25, fatG: 9,
                                   fiberG: 2, sodiumMg: sodium, addedSugarG: sugar,
                                   saturatedFatG: satFat)
        )
    }

    func test_cap_coverage_is_none_for_curated_only_log() {
        let c = MacroBudget.capCoverage(entries: [curatedEntry(), curatedEntry()])
        XCTAssertEqual(c.level, .none)
        XCTAssertEqual(c.entryCount, 2)
        XCTAssertEqual(c.measuredEntries, 0)
        XCTAssertEqual(c.unmeasuredEntries, 2)
    }

    func test_cap_coverage_is_none_for_empty_day() {
        let c = MacroBudget.capCoverage(entries: [])
        XCTAssertEqual(c.level, .none)
        XCTAssertEqual(c.entryCount, 0)
    }

    func test_cap_coverage_is_partial_when_only_some_entries_are_labelled() {
        let c = MacroBudget.capCoverage(entries: [curatedEntry(), labelEntry(), curatedEntry()])
        XCTAssertEqual(c.level, .partial)
        XCTAssertEqual(c.entryCount, 3)
        XCTAssertEqual(c.measuredEntries, 1)
        XCTAssertEqual(c.unmeasuredEntries, 2)
    }

    func test_cap_coverage_is_full_when_every_entry_is_labelled() {
        let c = MacroBudget.capCoverage(entries: [labelEntry(), labelEntry(sodium: 90)])
        XCTAssertEqual(c.level, .full)
        XCTAssertEqual(c.unmeasuredEntries, 0)
    }

    func test_one_positive_cap_figure_vouches_for_the_other_two_on_that_entry() {
        // A label reading 0 g added sugar / 0 g sat fat is a measured zero, not a
        // gap — sodium being present proves the entry came through a label.
        let c = MacroBudget.capCoverage(entries: [labelEntry(sodium: 300, sugar: 0, satFat: 0)])
        XCTAssertEqual(c.level, .full)
    }

    func test_cap_coverage_from_totals_never_claims_full() {
        // A sum can prove something was measured, never that everything was.
        XCTAssertEqual(MacroBudget.capCoverage(totals: totals(cal: 900, p: 40, c: 90, f: 20)).level,
                       .none)
        XCTAssertEqual(
            MacroBudget.capCoverage(
                totals: totals(cal: 900, p: 40, c: 90, f: 20, sodium: 480)
            ).level,
            .partial
        )
    }

    func test_remaining_with_entries_hides_cap_headroom_when_nothing_measured_it() {
        let v = Targets.ProfileVitals(sex: .female, weightLb: 160, heightIn: 65, age: 35, activity: .light)
        let targets = Targets.compute(fitnessGoal: .lose, vitals: v)
        let log = [curatedEntry(fiber: 9), curatedEntry(fiber: 9)]
        let t = totals(cal: 800, p: 40, c: 80, f: 20, fiber: 18)

        let r = MacroBudget.remaining(totals: t, targets: targets, entries: log)
        // No food measured the caps -> no headroom figure at all.
        XCTAssertNil(r.sodiumMg)
        XCTAssertNil(r.addedSugarG)
        XCTAssertNil(r.saturatedFatG)
        // Fiber is carried by every curated food, so it keeps working.
        XCTAssertEqual(r.fiberG, 18 - (targets.fiberGMin ?? 0))
        XCTAssertEqual(r.calories, targets.calories - 800)
    }

    func test_remaining_with_entries_keeps_cap_headroom_once_something_measured_it() {
        let v = Targets.ProfileVitals(sex: .female, weightLb: 160, heightIn: 65, age: 35, activity: .light)
        let targets = Targets.compute(fitnessGoal: .lose, vitals: v)
        let log = [curatedEntry(), labelEntry(sodium: 700)]
        let t = totals(cal: 600, p: 28, c: 65, f: 19, sodium: 700, sugar: 12, satFat: 4)

        let r = MacroBudget.remaining(totals: t, targets: targets, entries: log)
        XCTAssertEqual(r.sodiumMg, (targets.sodiumMgMax ?? 0) - 700)
        XCTAssertEqual(r.addedSugarG, (targets.addedSugarGMax ?? 0) - 12)
        XCTAssertEqual(r.saturatedFatG, (targets.saturatedFatGMax ?? 0) - 4)
    }

    func test_remaining_without_entries_is_unchanged() {
        // The original two-argument entry point keeps its old behaviour exactly.
        let v = Targets.ProfileVitals(sex: .female, weightLb: 160, heightIn: 65, age: 35, activity: .light)
        let targets = Targets.compute(fitnessGoal: .lose, vitals: v)
        let t = totals(cal: 800, p: 40, c: 80, f: 20)
        let r = MacroBudget.remaining(totals: t, targets: targets)
        XCTAssertEqual(r.sodiumMg, targets.sodiumMgMax)
        XCTAssertEqual(r.addedSugarG, targets.addedSugarGMax)
    }

    // MARK: - Servings scaling
    //
    // `perServing` × `servings`. Most logging paths pre-scale and leave servings
    // at 1; the label scanner stores an unscaled panel figure plus a count, and
    // its multi-serving entries used to be counted once — every macro read low.

    func test_totalNutrition_is_identity_when_servings_is_one() {
        let e = curatedEntry(cal: 400, fiber: 5)
        XCTAssertEqual(e.servings, 1)
        XCTAssertEqual(e.totalNutrition, e.perServing)
    }

    func test_totalNutrition_scales_every_field_by_servings() {
        var e = labelEntry(sodium: 480, sugar: 12, satFat: 4)
        e.servings = 2
        let t = e.totalNutrition
        XCTAssertEqual(t.calories, 400)        // 200 * 2
        XCTAssertEqual(t.proteinG, 16)         // 8 * 2
        XCTAssertEqual(t.carbsG, 50)           // 25 * 2
        XCTAssertEqual(t.fatG, 18)             // 9 * 2
        XCTAssertEqual(t.fiberG, 4)            // 2 * 2
        XCTAssertEqual(t.sodiumMg, 960)        // 480 * 2
        XCTAssertEqual(t.addedSugarG, 24)      // 12 * 2
        XCTAssertEqual(t.saturatedFatG, 8)     // 4 * 2
    }

    func test_totalNutrition_rounds_half_servings() {
        var e = curatedEntry(cal: 401, fiber: 5)
        e.servings = 0.5
        let t = e.totalNutrition
        XCTAssertEqual(t.calories, 201)        // 200.5 rounds to 201
        XCTAssertEqual(t.proteinG, 10)         // 20 * 0.5
        XCTAssertEqual(t.fiberG, 3)            // 2.5 rounds to 3
    }

    func test_dailyTotals_counts_a_two_serving_entry_twice() {
        var two = labelEntry(sodium: 480, sugar: 12, satFat: 4)
        two.servings = 2
        let scaled = DailyTotals.totals(from: [two])
        let single = DailyTotals.totals(from: [labelEntry(sodium: 480, sugar: 12, satFat: 4)])
        XCTAssertEqual(scaled.calories, single.calories * 2)
        XCTAssertEqual(scaled.sodiumMg, single.sodiumMg * 2)
        XCTAssertEqual(scaled.calories, 400)
    }
}
