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
        let targets = Targets.compute(mode: .build, vitals: v)
        let r = MacroBudget.remaining(totals: totals(cal: 0, p: 0, c: 0, f: 0), targets: targets)
        XCTAssertNil(r.sodiumMg)
        XCTAssertNil(r.addedSugarG)
        XCTAssertNil(r.saturatedFatG)
        XCTAssertNil(r.fiberG)
    }

    func test_circuit_caps_room_under_and_negative_when_over() {
        let v = Targets.ProfileVitals(sex: .female, weightLb: 160, heightIn: 65, age: 35, activity: .light)
        let targets = Targets.compute(mode: .circuit, vitals: v)
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
        let targets = Targets.compute(mode: .circuit, vitals: v)
        let floor = targets.fiberGMin ?? 35
        // Below floor -> negative; at/above floor -> >= 0.
        let under = MacroBudget.remaining(totals: totals(cal: 0, p: 0, c: 0, f: 0, fiber: 10), targets: targets)
        XCTAssertEqual(under.fiberG, 10 - floor)
        XCTAssertLessThan(under.fiberG ?? 0, 0)
        let met = MacroBudget.remaining(totals: totals(cal: 0, p: 0, c: 0, f: 0, fiber: floor), targets: targets)
        XCTAssertEqual(met.fiberG, 0)
    }
}
