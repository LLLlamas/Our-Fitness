// Pure helpers for the Circuit Train tab.
// Lives in Domain so it's unit-testable without standing up SwiftData/HealthKit.
//
//  - shouldFireMilestone: de-dupe step-count milestone toasts (3k / 5k / 8k / 10k)
//  - stepsDeltaVsYesterday: "ahead/behind yesterday at this hour" line
//  - pilatesWeeklyStreak: consecutive ISO weeks with ≥ goalSessions logged

import Foundation

public enum Movement {

    // MARK: - Step milestones

    /// Default step-count milestones for Circuit. Ordered ascending.
    public static let defaultStepMilestones: [Int] = [3_000, 5_000, 8_000, 10_000]

    /// Which milestone (if any) should fire *now*, given current steps and the
    /// set of milestones already fired today.
    ///
    /// Returns the largest unfired milestone ≤ `steps`, or `nil` if there's
    /// nothing new to celebrate. Caller is responsible for adding the returned
    /// value to its persisted `firedSet` (e.g. via `@AppStorage`) so the same
    /// milestone never re-fires the same day.
    public static func shouldFireMilestone(
        steps: Int,
        firedSet: Set<Int>,
        milestones: [Int] = defaultStepMilestones
    ) -> Int? {
        milestones
            .sorted()
            .last(where: { $0 <= steps && !firedSet.contains($0) })
    }

    /// Encode/decode helpers for storing the fired-milestone set as a single
    /// `@AppStorage` string (`@AppStorage` can't hold a `Set` directly).
    public static func encode(firedSet: Set<Int>) -> String {
        firedSet.sorted().map(String.init).joined(separator: ",")
    }

    public static func decode(firedSet raw: String) -> Set<Int> {
        Set(raw.split(separator: ",").compactMap { Int($0) })
    }

    // MARK: - Pace vs yesterday

    /// Compares today's steps so far against yesterday's steps at the same hour.
    /// `intradayToday` / `intradayYesterday` are 24-element arrays of *cumulative*
    /// steps at each hour boundary (index 0 = end of 12 AM hour … index 23 = end
    /// of 11 PM hour). `currentHour` is 0–23.
    ///
    /// Returns `today - yesterdayAtSameHour`. Positive = ahead. If either array
    /// is missing or wrong-shaped, returns 0 (degrade silently).
    public static func stepsDeltaVsYesterday(
        intradayToday: [Int],
        intradayYesterday: [Int],
        currentHour: Int
    ) -> Int {
        guard intradayToday.count == 24, intradayYesterday.count == 24 else { return 0 }
        let h = max(0, min(23, currentHour))
        let now = intradayToday[h]
        let then = intradayYesterday[h]
        return now - then
    }

    // MARK: - Pilates weekly streak

    /// Consecutive weeks (ending at `now`'s week) where the user logged at least
    /// `goalSessions` Pilates sessions. The current week counts even if the goal
    /// isn't yet met — it's a grace zone, matching `Streaks.currentStreak`.
    /// Returns 0 when there's no data.
    public static func pilatesWeeklyStreak(
        sessions: [PilatesSessionDTO],
        goalSessions: Int = 3,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> Int {
        guard goalSessions > 0 else { return 0 }
        var cal = calendar
        cal.firstWeekday = 2  // Monday — ISO weeks

        // Bucket sessions by their week-start date.
        var counts: [Date: Int] = [:]
        for s in sessions {
            if let weekStart = cal.dateInterval(of: .weekOfYear, for: s.date)?.start {
                counts[weekStart, default: 0] += 1
            }
        }

        guard var cursor = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        let thisWeekStart = cursor

        var streak = 0
        while true {
            let n = counts[cursor] ?? 0
            if n >= goalSessions {
                streak += 1
            } else if cursor == thisWeekStart {
                // grace: current week not yet at goal — slide back without breaking
            } else {
                break
            }
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    // MARK: - Step weekly streak

    /// Consecutive ISO weeks (ending at `now`'s week) where the user hit
    /// `dailyGoal` on at least `daysPerWeek` of the 7 days. Default rule:
    /// **5 of 7 days at goal** — strict enough to be a real streak, lenient
    /// enough to allow a rest day or a sick day without nuking the run.
    ///
    /// Grace zone matches `pilatesWeeklyStreak`: the current week never breaks
    /// the chain (it's still in progress); it only *adds* to the streak once
    /// it crosses the threshold.
    public static func stepWeeklyStreak(
        steps: [StepCountDTO],
        dailyGoal: Int,
        daysPerWeek: Int = 5,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> Int {
        guard dailyGoal > 0, daysPerWeek > 0 else { return 0 }
        var cal = calendar
        cal.firstWeekday = 2  // Monday — ISO weeks

        // Count days-at-goal per week-start. Parse dayKeys via Dates so the
        // domain layer stays free of date-format duplication.
        var hits: [Date: Int] = [:]
        for s in steps where s.steps >= dailyGoal {
            guard let d = Dates.date(fromDayKey: s.date),
                  let weekStart = cal.dateInterval(of: .weekOfYear, for: d)?.start
            else { continue }
            hits[weekStart, default: 0] += 1
        }

        guard var cursor = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        let thisWeekStart = cursor

        var streak = 0
        while true {
            let n = hits[cursor] ?? 0
            if n >= daysPerWeek {
                streak += 1
            } else if cursor == thisWeekStart {
                // grace: current week not yet at threshold — slide back
            } else {
                break
            }
            guard let prev = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    // MARK: - Circuit copy

    /// Short "why this matters" blurb shown under each Circuit card.
    /// Cites the documented effect of the modality on cardiovascular markers.
    public static func circuitFocusBlurb(for kind: CircuitFocusKind) -> String {
        switch kind {
        case .steps:
            return "Daily steps are the #1 lever for BP, insulin sensitivity, and LDL."
        case .pilates:
            return "Pilates builds core strength and joint stability — supports BP regulation."
        case .cardio:
            return "Zone-2 cardio raises HDL, lowers triglycerides, and trains aerobic capacity."
        }
    }

    public enum CircuitFocusKind: Sendable {
        case steps, pilates, cardio
    }

    // MARK: - Post-exercise nutrition hints

    /// What the body needs after a given type of movement, and which muscles
    /// were primarily worked. Surfaced in exercise info sheets.
    public struct PostExerciseHint: Sendable {
        public let musclesWorked: [String]
        public let primaryNeed: String
        public let recoveryFoods: [String]
        public let windowMinutes: Int
    }

    public static func postExerciseHint(for exercise: ExerciseDTO) -> PostExerciseHint {
        let muscles: [String] = exercise.muscleGroups.isEmpty
            ? categoryMuscles(exercise.category)
            : exercise.muscleGroups
        let hasLoad = (exercise.loadLb ?? 0) > 0

        if exercise.kind == .duration {
            return PostExerciseHint(
                musclesWorked: muscles,
                primaryNeed: "Carbs + hydration to restock energy",
                recoveryFoods: ["banana + nut butter", "smoothie", "oatmeal + berries"],
                windowMinutes: 45
            )
        } else if hasLoad {
            return PostExerciseHint(
                musclesWorked: muscles,
                primaryNeed: "Protein (20–30 g) to repair muscle",
                recoveryFoods: ["Greek yogurt + fruit", "eggs + toast", "chicken + rice"],
                windowMinutes: 30
            )
        } else {
            return PostExerciseHint(
                musclesWorked: muscles,
                primaryNeed: "Protein + hydration",
                recoveryFoods: ["cottage cheese", "turkey wrap", "protein shake"],
                windowMinutes: 60
            )
        }
    }

    public static func postPilatesHint(areas: [PilatesFocusArea]) -> PostExerciseHint {
        let muscles = Array(Set(areas.flatMap(\.muscles)))
        return PostExerciseHint(
            musclesWorked: muscles.isEmpty ? ["core", "posture stabilisers"] : muscles,
            primaryNeed: "Anti-inflammatory protein (20–25 g)",
            recoveryFoods: ["salmon + veg", "Greek yogurt", "berries + almonds"],
            windowMinutes: 60
        )
    }

    private static func categoryMuscles(_ cat: ExerciseCategory) -> [String] {
        switch cat {
        case .compound:   return ["multiple muscle groups"]
        case .isolation:  return ["targeted muscle group"]
        case .bodyweight: return ["core", "upper body", "lower body"]
        case .cardio:     return ["cardiovascular system", "lower body"]
        case .mobility:   return ["joints", "connective tissue"]
        }
    }

    /// Sessions falling inside the calendar week containing `now`.
    public static func sessionsThisWeek(
        _ sessions: [PilatesSessionDTO],
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> [PilatesSessionDTO] {
        var cal = calendar
        cal.firstWeekday = 2
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return sessions.filter { week.contains($0.date) }
    }
}

// MARK: - PilatesFocusArea muscle groups

public extension PilatesFocusArea {
    var muscles: [String] {
        switch self {
        case .core:        return ["transverse abdominis", "obliques", "rectus abdominis"]
        case .lowerBack:   return ["erector spinae", "multifidus", "glutes"]
        case .hips:        return ["hip flexors", "glutes", "piriformis"]
        case .fullBody:    return ["core", "glutes", "upper back", "shoulders"]
        case .flexibility: return ["hip flexors", "hamstrings", "thoracic extensors"]
        }
    }
}
