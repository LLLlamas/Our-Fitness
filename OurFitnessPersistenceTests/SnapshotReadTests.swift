import XCTest
import SwiftData

@MainActor
final class SnapshotReadTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([FoodLogEntryModel.self, WaterEntryModel.self, StepCountModel.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        ])
    }

    func testFoodWindowIncludesBothBoundariesAndScopesProfile() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let user = UUID()
        let other = UUID()
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        func add(_ owner: UUID, _ day: String, _ offset: TimeInterval) -> UUID {
            let entry = FoodLogEntryDTO(userId: owner, date: day, slot: .other,
                                       perServing: .zero, timestamp: anchor.addingTimeInterval(offset))
            ctx.insert(FoodLogEntryModel(snapshot: entry))
            return entry.id
        }
        let first = add(user, "2026-08-15", 10)
        let last = add(user, "2026-09-13", 30)
        let middle = add(user, "2026-08-25", 20)
        _ = add(user, "2026-08-14", 40)
        _ = add(user, "2026-09-14", 50)
        _ = add(other, "2026-09-13", 60)
        try ctx.save()

        let rows = Repos.foodLogs(ctx, userId: user, inDayRange: "2026-08-15"..."2026-09-13")
        XCTAssertEqual(rows.map(\.id), [last, middle, first])
        // Day keys, not receipt timestamps, define membership for backdated logs.
        XCTAssertEqual(rows.count, 3)
    }

    func testDailyWaterAndStepsExcludeHistoryAndOtherProfiles() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let user = UUID()
        let other = UUID()
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        for (owner, day, amount) in [(user, "2026-09-13", 8.0), (user, "2026-09-13", 16.0),
                                      (user, "2026-09-12", 32.0), (other, "2026-09-13", 64.0)] {
            ctx.insert(WaterEntryModel(snapshot: WaterEntryDTO(
                userId: owner, date: day, flOz: amount, timestamp: anchor)))
        }
        for (owner, day, count) in [(user, "2026-09-13", 8000), (user, "2026-09-12", 9000),
                                     (other, "2026-09-13", 10000)] {
            ctx.insert(StepCountModel(snapshot: StepCountDTO(
                userId: owner, date: day, steps: count, updatedAt: anchor)))
        }
        try ctx.save()

        XCTAssertEqual(Water.total(Repos.water(ctx, userId: user, on: "2026-09-13"), on: "2026-09-13"), 24)
        XCTAssertEqual(Repos.steps(ctx, userId: user, on: "2026-09-13").map(\.steps), [8000])
        XCTAssertTrue(Repos.water(ctx, userId: user, on: "2026-09-14").isEmpty)
        XCTAssertTrue(Repos.steps(ctx, userId: user, on: "2026-09-14").isEmpty)
    }

    func testBoundedReadPreservesAffinityAndTotalsAcrossFiveYears() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let user = UUID()
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let keys = Dates.lastNDays(365 * 5, end: end)
        // Six logs daily models a long-lived installation without baking timing
        // expectations into CI. Compare actual results and report diagnostic cost.
        for (dayIndex, day) in keys.enumerated() {
            for slot in 0..<6 {
                ctx.insert(FoodLogEntryModel(snapshot: FoodLogEntryDTO(
                    userId: user, date: day, slot: .other, foodId: "fixture-\(slot % 3)",
                    perServing: .zero,
                    timestamp: end.addingTimeInterval(Double((dayIndex - keys.count) * 86400 + slot))
                )))
            }
        }
        try ctx.save()
        let start = ContinuousClock.now
        let all = Repos.listFoodLog(ctx, userId: user)
        let fullDuration = start.duration(to: .now)
        let window = Dates.lastNDays(30, end: end)
        let boundedStart = ContinuousClock.now
        let bounded = Repos.foodLogs(ctx, userId: user, inDayRange: window.first!...window.last!)
        let boundedDuration = boundedStart.duration(to: .now)

        XCTAssertEqual(all.count, 10_950)
        XCTAssertEqual(bounded.count, 180)
        XCTAssertEqual(FoodAffinity.frequencyByFoodId(all, end: end),
                       FoodAffinity.frequencyByFoodId(bounded, end: end))
        XCTAssertEqual(DailyTotals.totals(from: all.filter { $0.date == window.last! }),
                       DailyTotals.totals(from: bounded.filter { $0.date == window.last! }))
        print("Snapshot read diagnostic: \(all.count) rows \(fullDuration); \(bounded.count) rows \(boundedDuration) (warm in-memory store)")
    }
}
