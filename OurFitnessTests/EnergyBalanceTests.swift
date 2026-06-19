import XCTest

final class EnergyBalanceTests: XCTestCase {

    // Pinned mid-day UTC so the day key is stable across CI timezones (noon UTC
    // lands on the same calendar day everywhere). Never bare Date().
    private let end = ISO8601DateFormatter().date(from: "2026-05-27T12:00:00Z")!
    private let dayKey = "2026-05-27"
    private let bodyWeightLb = 180.0
    private let uid = UUID()

    // MARK: Fixtures

    private func food(_ date: String, calories: Int) -> FoodLogEntryDTO {
        FoodLogEntryDTO(
            userId: uid, date: date, slot: .lunch,
            perServing: PerServing(calories: calories, proteinG: 0, carbsG: 0, fatG: 0)
        )
    }

    private func step(_ date: String, _ steps: Int) -> StepCountDTO {
        StepCountDTO(userId: uid, date: date, steps: steps)
    }

    /// A set with an explicit logged calorie estimate, timestamped at noon UTC on
    /// `date` so its day key matches the window key regardless of host timezone.
    private func set(_ date: String, kcal: Double) -> WorkoutSetDTO {
        let ts = ISO8601DateFormatter().date(from: "\(date)T12:00:00Z")!
        return WorkoutSetDTO(userId: uid, exerciseId: "ex", reps: 8,
                             timestamp: ts, caloriesEst: kcal)
    }

    // MARK: Known-day intake / burn / net

    func test_knownDay_intake_burn_net() {
        let rows = EnergyBalance.byDay(
            days: 7, end: end,
            foodLogs: [food(dayKey, calories: 500), food(dayKey, calories: 300)],
            steps: [step(dayKey, 10_000)],
            sets: [set(dayKey, kcal: 40), set(dayKey, kcal: 60)],
            cardio: [], pilates: [], activities: [],
            bodyWeightLb: bodyWeightLb
        )

        let today = rows.first { $0.day == dayKey }
        XCTAssertNotNil(today)
        // intake = 500 + 300
        XCTAssertEqual(today?.intake, 800)
        // burned = steps(10k @ 180lb ≈ 475) + logged sets (40 + 60)
        // 4.3 × (180×0.453592) × (10000/7392) + 100 = 574.946… → 575
        XCTAssertEqual(today?.burned, 575)
        XCTAssertEqual(today?.net, 225)   // 800 − 575
    }

    // MARK: Empty days are emitted as zero

    func test_emptyDay_is_zero() {
        let rows = EnergyBalance.byDay(
            days: 7, end: end,
            foodLogs: [food(dayKey, calories: 500)],
            steps: [step(dayKey, 10_000)],
            sets: [], cardio: [], pilates: [], activities: [],
            bodyWeightLb: bodyWeightLb
        )

        // A different day in the window with no data at all.
        let empty = rows.first { $0.day == "2026-05-25" }
        XCTAssertNotNil(empty)
        XCTAssertEqual(empty?.intake, 0)
        XCTAssertEqual(empty?.burned, 0)
        XCTAssertEqual(empty?.net, 0)
    }

    // MARK: Dense, oldest-first window

    func test_window_is_dense_and_oldest_first() {
        let rows = EnergyBalance.byDay(
            days: 7, end: end,
            foodLogs: [], steps: [], sets: [], cardio: [], pilates: [], activities: [],
            bodyWeightLb: bodyWeightLb
        )
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows.last?.day, dayKey)        // newest last
        XCTAssertEqual(rows.first?.day, "2026-05-21") // 7-day window, oldest first
        XCTAssertTrue(rows.allSatisfy { $0.intake == 0 && $0.burned == 0 })
    }

    // MARK: Averages skip empty days

    func test_averages_skip_empty_days() {
        let rows = EnergyBalance.byDay(
            days: 7, end: end,
            foodLogs: [food(dayKey, calories: 2000), food("2026-05-26", calories: 1000)],
            steps: [], sets: [], cardio: [], pilates: [], activities: [],
            bodyWeightLb: bodyWeightLb
        )
        // Two active days (2000 and 1000) → mean 1500, ignoring the 5 empty days.
        let avg = EnergyBalance.averages(rows)
        XCTAssertEqual(avg.intake, 1500)
        XCTAssertEqual(avg.burned, 0)
    }

    func test_averages_zero_when_nothing_logged() {
        let rows = EnergyBalance.byDay(
            days: 7, end: end,
            foodLogs: [], steps: [], sets: [], cardio: [], pilates: [], activities: [],
            bodyWeightLb: bodyWeightLb
        )
        let avg = EnergyBalance.averages(rows)
        XCTAssertEqual(avg.intake, 0)
        XCTAssertEqual(avg.burned, 0)
    }
}
