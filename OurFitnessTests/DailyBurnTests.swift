import XCTest

/// `DailyBurn.breakdown` is the per-source split the Move card consumes. These
/// pin the split, the two walk-exclusion rules, and the fact that the breakdown
/// and the long-standing `metEstimate` can never disagree.
final class DailyBurnTests: XCTestCase {

    private let uid = UUID()
    private let bodyWeightLb = 180.0

    // MARK: Fixtures

    private func set(kcal: Double) -> WorkoutSetDTO {
        WorkoutSetDTO(userId: uid, exerciseId: "ex", reps: 8, caloriesEst: kcal)
    }

    private func cardio(_ type: CardioType, kcal: Double) -> CardioSessionDTO {
        CardioSessionDTO(profileId: uid, type: type, durationMinutes: 20, caloriesEst: kcal)
    }

    private func pilates(minutes: Int) -> PilatesSessionDTO {
        PilatesSessionDTO(profileId: uid, durationMinutes: minutes, focusAreas: [.core])
    }

    private func activity(_ id: String, kcal: Double) -> ActivitySessionDTO {
        ActivitySessionDTO(profileId: uid, activityId: id, activityName: id,
                           met: 7.0, durationMinutes: 30, expectedMinutes: 30,
                           caloriesEst: kcal)
    }

    private func breakdown(
        steps: Int = 0,
        sets: [WorkoutSetDTO] = [],
        cardio: [CardioSessionDTO] = [],
        pilates: [PilatesSessionDTO] = [],
        activities: [ActivitySessionDTO] = []
    ) -> DailyBurn.Breakdown {
        DailyBurn.breakdown(steps: steps, sets: sets, cardio: cardio, pilates: pilates,
                            activities: activities, bodyWeightLb: bodyWeightLb)
    }

    // MARK: Empty day

    func test_breakdown_emptyDay_isAllZero() {
        let b = breakdown()
        XCTAssertEqual(b.stepsKcal, 0)
        XCTAssertEqual(b.setsKcal, 0)
        XCTAssertEqual(b.cardioKcal, 0)
        XCTAssertEqual(b.pilatesKcal, 0)
        XCTAssertEqual(b.activitiesKcal, 0)
        XCTAssertEqual(b.trainingKcal, 0)
        XCTAssertEqual(b.totalKcal, 0)
        XCTAssertEqual(b.total, 0)
    }

    // MARK: Per-source split

    func test_breakdown_splitsBySource() {
        let b = breakdown(
            steps: 10_000,
            sets: [set(kcal: 40), set(kcal: 60)],
            cardio: [cardio(.run, kcal: 200)],
            pilates: [pilates(minutes: 30)],
            activities: [activity("activity-soccer", kcal: 300)]
        )
        XCTAssertEqual(
            b.stepsKcal,
            CalorieEstimator.caloriesForSteps(steps: 10_000, bodyWeightLb: bodyWeightLb),
            accuracy: 0.0001
        )
        XCTAssertEqual(b.setsKcal, 100, accuracy: 0.0001)
        XCTAssertEqual(b.cardioKcal, 200, accuracy: 0.0001)
        XCTAssertEqual(
            b.pilatesKcal,
            CalorieEstimator.caloriesForPilates(minutes: 30, bodyWeightLb: bodyWeightLb),
            accuracy: 0.0001
        )
        XCTAssertEqual(b.activitiesKcal, 300, accuracy: 0.0001)
    }

    /// 60 min pilates (MET 3.0) at 180 lb = 3.0 × 81.6466266 kg × 1 hr = 244.9398798.
    func test_breakdown_pilates_exact_kcal() {
        let b = breakdown(pilates: [pilates(minutes: 60)])
        XCTAssertEqual(b.pilatesKcal, 244.9398798, accuracy: 0.0001)
        XCTAssertEqual(b.trainingKcal, 244.9398798, accuracy: 0.0001)
        XCTAssertEqual(b.total, 245)
    }

    // MARK: Walk exclusions (steps already count that movement)

    func test_breakdown_excludesLoggedWalksFromCardio() {
        let b = breakdown(cardio: [cardio(.walk, kcal: 150), cardio(.bike, kcal: 90)])
        XCTAssertEqual(b.cardioKcal, 90, accuracy: 0.0001)
    }

    func test_breakdown_excludesWalkingLiveActivity() {
        let b = breakdown(activities: [
            activity(ActivityCatalog.walkingId, kcal: 120),
            activity("activity-basketball-game", kcal: 400)
        ])
        XCTAssertEqual(b.activitiesKcal, 400, accuracy: 0.0001)
    }

    func test_walkingId_isInTheCatalog() {
        XCTAssertNotNil(ActivityCatalog.activity(id: ActivityCatalog.walkingId))
    }

    // MARK: Training vs total

    func test_trainingKcal_excludesSteps_totalIncludesThem() {
        let b = breakdown(steps: 8_000, sets: [set(kcal: 50)])
        XCTAssertEqual(b.trainingKcal, 50, accuracy: 0.0001)
        XCTAssertEqual(b.totalKcal, b.stepsKcal + 50, accuracy: 0.0001)
        XCTAssertGreaterThan(b.stepsKcal, 0)
    }

    // MARK: Agreement with metEstimate

    func test_breakdownTotal_matchesMetEstimate() {
        let steps = 7_431
        let sets = [set(kcal: 41.3), set(kcal: 17.9)]
        let cardioSessions = [cardio(.walk, kcal: 99), cardio(.elliptical, kcal: 123.4)]
        let pilatesSessions = [pilates(minutes: 25), pilates(minutes: 45)]
        let activities = [
            activity(ActivityCatalog.walkingId, kcal: 55),
            activity("activity-tennis", kcal: 212.7)
        ]
        let b = DailyBurn.breakdown(
            steps: steps, sets: sets, cardio: cardioSessions, pilates: pilatesSessions,
            activities: activities, bodyWeightLb: bodyWeightLb
        )
        let legacy = DailyBurn.metEstimate(
            steps: steps, sets: sets, cardio: cardioSessions, pilates: pilatesSessions,
            activities: activities, bodyWeightLb: bodyWeightLb
        )
        XCTAssertEqual(b.total, legacy)
    }

    /// Sets with no stored estimate contribute nothing rather than crashing or
    /// guessing — the log-time estimate is the only source for strength burn.
    func test_breakdown_setsWithoutEstimate_contributeNothing() {
        let bare = WorkoutSetDTO(userId: uid, exerciseId: "ex", reps: 5)
        let b = breakdown(sets: [bare, set(kcal: 30)])
        XCTAssertEqual(b.setsKcal, 30, accuracy: 0.0001)
    }
}
