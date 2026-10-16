// Groups logged resistance sets into per-day training sessions (pure Swift).
//
// The Workouts tab shows only the CURRENT day's recent sets; the full cross-day
// history lives in the Progress tab and is built here. Mirrors the shape of
// Domain/EnergyBalance.swift: deterministic, no SwiftUI/SwiftData, unit-tested
// with a pinned `now`.

import Foundation

public enum TrainingHistory {

    /// One exercise's contribution within a single day.
    public struct ExerciseLine: Sendable, Identifiable {
        public let exerciseId: String
        public let name: String
        public let isIsometric: Bool
        /// Reps / minutes / hold seconds folded per exact weight — print it with
        /// `RepHistory.summary(line.tally, formatWeight:)` so every list reads alike.
        public let tally: RepHistory.Tally
        public let totalReps: Int
        public let totalHoldSeconds: Int
        public let calories: Int
        /// The underlying set ids (newest first) so the UI can offer per-set delete.
        public let setIds: [UUID]
        public var id: String { exerciseId }
    }

    /// All sets logged on one calendar day, grouped by exercise.
    public struct DaySession: Sendable, Identifiable {
        public let dayKey: String          // local YYYY-MM-DD
        public let exercises: [ExerciseLine]
        /// Logged rows that day (one per Save set / +1 tap), not a progress figure.
        public let totalSets: Int
        public let totalCalories: Int
        public var id: String { dayKey }
    }

    /// Build the per-day session list, most recent day first. Exercise names come
    /// from the supplied catalog of the user's exercises (id → name); sets whose
    /// exercise is unknown are labelled "Exercise" rather than dropped.
    public static func sessions(
        sets: [WorkoutSetDTO],
        exercises: [ExerciseDTO]
    ) -> [DaySession] {
        guard !sets.isEmpty else { return [] }

        let byId: [String: ExerciseDTO] = Dictionary(
            exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }
        )

        // dayKey -> exerciseId -> accumulating line.
        var days: [String: [String: Accumulator]] = [:]
        for s in sets {
            let key = Dates.dayKey(s.timestamp)
            days[key, default: [:]][s.exerciseId, default: Accumulator()]
                .add(s, exercise: byId[s.exerciseId])
        }

        return days
            .map { dayKey, exMap -> DaySession in
                let lines = exMap
                    .map { exerciseId, acc -> ExerciseLine in
                        ExerciseLine(
                            exerciseId: exerciseId,
                            name: acc.name,
                            isIsometric: acc.isIsometric,
                            tally: RepHistory.dayTally(
                                for: byId[exerciseId] ?? ExerciseDTO(
                                    id: exerciseId, name: acc.name, category: .compound,
                                    muscleGroups: [], equipment: []),
                                rows: acc.rows, dayKey: dayKey),
                            totalReps: acc.totalReps,
                            totalHoldSeconds: acc.totalHoldSeconds,
                            calories: acc.calories,
                            // Newest set first so the delete list reads top-down.
                            setIds: acc.entries.sorted { $0.0 > $1.0 }.map(\.1)
                        )
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                return DaySession(
                    dayKey: dayKey,
                    exercises: lines,
                    totalSets: lines.reduce(0) { $0 + $1.tally.rowCount },
                    totalCalories: lines.reduce(0) { $0 + $1.calories }
                )
            }
            // Lexicographic order on yyyy-MM-dd is chronological; newest first.
            .sorted { $0.dayKey > $1.dayKey }
    }

    // MARK: - Weekly volume

    /// REPS logged inside one Monday-anchored ISO week, across rep exercises only
    /// (`kind == .reps`, not isometric — holds and duration exercises are
    /// excluded, as are sets of unknown exercises). `weeksAgo: 0` is the current
    /// week, `1` the week before, and so on.
    ///
    /// Reps, not rows: ten +1 taps and one set of ten are the same ten reps.
    /// Weeks are ISO (Monday→Sunday) so the Progress tab's "this week" matches
    /// Today/Train, which have always used `Movement`'s Monday weeks.
    public static func repsInWeek(
        _ sets: [WorkoutSetDTO],
        exercises: [ExerciseDTO],
        weeksAgo: Int = 0,
        now: Date = Date()
    ) -> Int {
        let key = Dates.dayKey(Dates.startOfISOWeek(now, weeksAgo: weeksAgo))
        return RepHistory.weeklyRepTotals(sets: sets, exercises: exercises)[key] ?? 0
    }

    /// One point per ISO week that has at least one rep, over the last `weeks`
    /// weeks (including the current, partial one). Oldest first; the point's
    /// `date` is the week's Monday as a dayKey. Weeks with no reps are omitted
    /// rather than zero-filled — the chart plots what was actually logged.
    public static func weeklyRepCounts(
        _ sets: [WorkoutSetDTO],
        exercises: [ExerciseDTO],
        weeks: Int = 12,
        now: Date = Date()
    ) -> [Trends.Point] {
        guard weeks > 0 else { return [] }
        let cutoffKey = Dates.dayKey(Dates.startOfISOWeek(now, weeksAgo: weeks - 1))
        return RepHistory.weeklyRepTotals(sets: sets, exercises: exercises)
            .filter { $0.key >= cutoffKey }
            .map { Trends.Point(date: $0.key, value: Double($0.value)) }
            .sorted { $0.date < $1.date }
    }

    private struct Accumulator {
        var name: String = "Exercise"
        var isIsometric: Bool = false
        var rows: [WorkoutSetDTO] = []
        var totalReps: Int = 0
        var totalHoldSeconds: Int = 0
        var calories: Int = 0
        var entries: [(Date, UUID)] = []

        mutating func add(_ s: WorkoutSetDTO, exercise ex: ExerciseDTO?) {
            name = ex?.name ?? name
            isIsometric = ex?.isIsometric ?? isIsometric
            rows.append(s)
            totalReps += s.reps
            totalHoldSeconds += s.holdSeconds ?? 0
            calories += Int((s.caloriesEst ?? 0).rounded())
            entries.append((s.timestamp, s.id))
        }
    }
}
