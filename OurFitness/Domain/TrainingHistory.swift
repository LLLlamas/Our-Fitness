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
        public let setCount: Int
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
            var dayMap = days[key] ?? [:]
            var acc = dayMap[s.exerciseId] ?? Accumulator()
            let ex = byId[s.exerciseId]
            acc.name = ex?.name ?? acc.name
            acc.isIsometric = ex?.isIsometric ?? acc.isIsometric
            acc.setCount += 1
            acc.totalReps += s.reps
            acc.totalHoldSeconds += s.holdSeconds ?? 0
            acc.calories += Int((s.caloriesEst ?? 0).rounded())
            acc.entries.append((s.timestamp, s.id))
            dayMap[s.exerciseId] = acc
            days[key] = dayMap
        }

        return days
            .map { dayKey, exMap -> DaySession in
                let lines = exMap
                    .map { exerciseId, acc -> ExerciseLine in
                        ExerciseLine(
                            exerciseId: exerciseId,
                            name: acc.name,
                            isIsometric: acc.isIsometric,
                            setCount: acc.setCount,
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
                    totalSets: lines.reduce(0) { $0 + $1.setCount },
                    totalCalories: lines.reduce(0) { $0 + $1.calories }
                )
            }
            // Lexicographic order on yyyy-MM-dd is chronological; newest first.
            .sorted { $0.dayKey > $1.dayKey }
    }

    private struct Accumulator {
        var name: String = "Exercise"
        var isIsometric: Bool = false
        var setCount: Int = 0
        var totalReps: Int = 0
        var totalHoldSeconds: Int = 0
        var calories: Int = 0
        var entries: [(Date, UUID)] = []
    }
}
