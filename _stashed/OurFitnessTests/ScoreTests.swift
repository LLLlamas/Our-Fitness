import XCTest

final class ScoreTests: XCTestCase {

    private func mkFood(_ overrides: (inout FoodDTO) -> Void = { _ in }) -> FoodDTO {
        var f = FoodDTO(
            id: "t", name: "t", modeFit: [.build], category: .main,
            perServing: PerServing(calories: 500, proteinG: 30, carbsG: 50, fatG: 20,
                                   fiberG: 5, sodiumMg: 400, addedSugarG: 5, saturatedFatG: 4),
            costUsd: 3, costTier: .mid
        )
        overrides(&f)
        return f
    }

    func test_bell_peaks_at_target() {
        XCTAssertEqual(Score.bell(value: 100, target: 100, tolerance: 50), 1)
        XCTAssertEqual(Score.bell(value: 50,  target: 100, tolerance: 50), 0)
        XCTAssertEqual(Score.bell(value: 150, target: 100, tolerance: 50), 0)
    }

    func test_rampUp_clamps_0_to_1() {
        XCTAssertEqual(Score.rampUp(0, ceiling: 10), 0)
        XCTAssertEqual(Score.rampUp(5, ceiling: 10), 0.5)
        XCTAssertEqual(Score.rampUp(20, ceiling: 10), 1)
    }

    func test_rampDown_inverse() {
        XCTAssertEqual(Score.rampDown(0, ceiling: 10), 1)
        XCTAssertEqual(Score.rampDown(10, ceiling: 10), 0)
        XCTAssertEqual(Score.rampDown(20, ceiling: 10), 0)
    }

    func test_respectsCap_handles_nil_headroom() {
        XCTAssertEqual(Score.respectsCap(value: 100, headroom: nil), 1)
        XCTAssertEqual(Score.respectsCap(value: 100, headroom: 0), 0)
        XCTAssertEqual(Score.respectsCap(value: 50,  headroom: 100), 0.5)
    }

    func test_macroFit_rejects_blowout() {
        var f = mkFood()
        f.perServing = PerServing(calories: 1600, proteinG: 30, carbsG: 50, fatG: 20)
        let fit = Score.macroFit(f, remaining: RemainingMacros(calories: 1000, proteinG: 30, carbsG: 50, fatG: 20))
        XCTAssertEqual(fit, 0)
    }

    func test_calsPerDollar() {
        XCTAssertEqual(Score.calsPerDollar(mkFood()), 500.0/3.0, accuracy: 0.001)
    }

    func test_proteinPerCal() {
        XCTAssertEqual(Score.proteinPerCal(mkFood()), 30.0/500.0, accuracy: 0.001)
    }
}
