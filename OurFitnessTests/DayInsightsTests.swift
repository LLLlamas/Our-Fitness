import XCTest

final class DayInsightsTests: XCTestCase {

    private let targets = MacroTargets(calories: 2000, proteinG: 150, carbsG: 200, fatG: 60, stepsDaily: 8000)

    private func totals(cal: Int, protein: Int) -> DailyTotals {
        var t = DailyTotals()
        t.calories = cal
        t.proteinG = protein
        return t
    }

    private func ids(today: DayInsights.Day, yesterday: DayInsights.Day,
                     goal: FitnessGoal = .lose, limit: Int = 10) -> [String] {
        DayInsights.compute(today: today, yesterday: yesterday, fitnessGoal: goal,
                            targets: targets, stepsGoal: 8000, waterGoalFlOz: 64,
                            limit: limit).map(\.id)
    }

    func testNothingLoggedYesterdaySaysSoAndMakesNoFoodClaim() {
        let r = ids(today: .init(), yesterday: .init())
        XCTAssertEqual(r, ["food-unlogged"])
    }

    func testLoseGoalFlagsCaloriesOverByMoreThanTenPercent() {
        let over = DayInsights.Day(totals: totals(cal: 2300, protein: 150), foodLogged: true)
        XCTAssertTrue(ids(today: .init(), yesterday: over).contains("cal-over"))
        let slight = DayInsights.Day(totals: totals(cal: 2150, protein: 150), foodLogged: true)
        XCTAssertFalse(ids(today: .init(), yesterday: slight).contains("cal-over"))
    }

    func testGainGoalFlagsCaloriesUnderAndNeverOver() {
        let under = DayInsights.Day(totals: totals(cal: 1500, protein: 150), foodLogged: true)
        XCTAssertTrue(ids(today: .init(), yesterday: under, goal: .gain).contains("cal-under"))
        let over = DayInsights.Day(totals: totals(cal: 2600, protein: 150), foodLogged: true)
        XCTAssertFalse(ids(today: .init(), yesterday: over, goal: .gain).contains("cal-over"))
    }

    func testProteinShortAndHit() {
        let short = DayInsights.Day(totals: totals(cal: 2000, protein: 100), foodLogged: true)
        XCTAssertTrue(ids(today: .init(), yesterday: short).contains("protein-short"))
        let hit = DayInsights.Day(totals: totals(cal: 2000, protein: 160), foodLogged: true)
        XCTAssertTrue(ids(today: .init(), yesterday: hit).contains("protein-hit"))
        // Already met today: no "two in a row" prompt.
        let doneToday = DayInsights.Day(totals: totals(cal: 1000, protein: 150), foodLogged: true)
        XCTAssertFalse(ids(today: doneToday, yesterday: hit).contains("protein-hit"))
    }

    func testStepsNeedYesterdayDataAndSkipOnceTodayIsHit() {
        XCTAssertFalse(ids(today: .init(), yesterday: .init(steps: 0)).contains("steps-short"))
        XCTAssertTrue(ids(today: .init(steps: 1000), yesterday: .init(steps: 4000)).contains("steps-short"))
        XCTAssertTrue(ids(today: .init(steps: 1000), yesterday: .init(steps: 9000)).contains("steps-hit"))
        let r = ids(today: .init(steps: 8000), yesterday: .init(steps: 4000))
        XCTAssertFalse(r.contains("steps-short"))
    }

    func testStepsWalkMinutesRoundUpToFive() {
        let r = DayInsights.stepsInsight(today: .init(steps: 6000), yesterday: .init(steps: 4000), goal: 8000)
        // 2,000 steps at 100/min = 20 minutes.
        XCTAssertEqual(r?.detail.contains("20-minute walk"), true)
    }

    func testWaterZeroIsNoClaim() {
        XCTAssertNil(DayInsights.waterInsight(yesterday: .init(waterFlOz: 0), goal: 64))
        XCTAssertNotNil(DayInsights.waterInsight(yesterday: .init(waterFlOz: 20), goal: 64))
        XCTAssertNil(DayInsights.waterInsight(yesterday: .init(waterFlOz: 60), goal: 64))
    }

    func testTrainedYesterdaySuggestsRecoveryOnlyWhenNotTrainedToday() {
        XCTAssertTrue(ids(today: .init(), yesterday: .init(trained: true)).contains("train-recover"))
        XCTAssertFalse(ids(today: .init(trained: true), yesterday: .init(trained: true)).contains("train-recover"))
    }

    func testLimitCapsTheList() {
        let y = DayInsights.Day(totals: totals(cal: 2500, protein: 50), foodLogged: true,
                                steps: 3000, waterFlOz: 10, trained: true)
        XCTAssertEqual(DayInsights.compute(today: .init(), yesterday: y, fitnessGoal: .lose,
                                           targets: targets, stepsGoal: 8000, waterGoalFlOz: 64).count, 3)
    }
}
