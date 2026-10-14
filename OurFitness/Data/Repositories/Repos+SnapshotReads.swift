// Bounded reads for current-state consumers such as the watch snapshot.
// Full history APIs remain available for history and streak calculations.

import Foundation
import SwiftData

extension Repos {
    /// Inclusive local day-key range; the same calendar keys FoodAffinity uses.
    /// Most-recent first preserves the watch's first-hit food-name/macro lookup.
    public static func foodLogs(
        _ ctx: ModelContext, userId: UUID, inDayRange days: ClosedRange<String>
    ) -> [FoodLogEntryDTO] {
        let first = days.lowerBound
        let last = days.upperBound
        let descriptor = FetchDescriptor<FoodLogEntryModel>(
            predicate: #Predicate { $0.userId == userId && $0.date >= first && $0.date <= last },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? ctx.fetch(descriptor).map(\.snapshot)) ?? []
    }

    public static func water(_ ctx: ModelContext, userId: UUID, on day: String) -> [WaterEntryDTO] {
        let descriptor = FetchDescriptor<WaterEntryModel>(
            predicate: #Predicate { $0.userId == userId && $0.date == day },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return (try? ctx.fetch(descriptor).map(\.snapshot)) ?? []
    }

    public static func steps(_ ctx: ModelContext, userId: UUID, on day: String) -> [StepCountDTO] {
        let descriptor = FetchDescriptor<StepCountModel>(
            predicate: #Predicate { $0.userId == userId && $0.date == day }
        )
        return (try? ctx.fetch(descriptor).map(\.snapshot)) ?? []
    }
}
