// Weekly hard-set volume per muscle group, and what to add (pure Swift).
//
// Counts the sets logged in the current Monday-anchored ISO week
// (`Dates.startOfISOWeek`, same week as Today / Train / Progress) for each major
// muscle group, compares them with a weekly target, and writes ONE short
// recommendation per group that is short of it, naming an exercise the user's
// kit (`HomeEquipment`) can do.
//
// SOURCES (checked 2026-10-18 against the published abstracts):
//   - Schoenfeld BJ, Ogborn D, Krieger JW. "Dose-response relationship between
//     weekly resistance training volume and increases in muscle mass: A systematic
//     review and meta-analysis." J Sports Sci 2017;35(11):1073-82. 15 studies.
//     Finding: a graded dose-response — more weekly sets per muscle, more growth
//     (each added set ≈ +0.37% gain). Studied bands were <5, 5-9 and 10+ weekly
//     sets per muscle; the three-band comparison was only a trend (P = 0.074), the
//     continuous and lower-vs-higher comparisons were significant (P = 0.002 / 0.03).
//     The paper does NOT establish an upper limit, so none is stated here.
//   - Schoenfeld BJ, Grgic J, Ogborn D, Krieger JW. "Strength and hypertrophy
//     adaptations between low- vs. high-load resistance training: a systematic
//     review and meta-analysis." J Strength Cond Res 2017;31(12):3508-23. 21 studies,
//     every set taken to momentary failure: muscle growth was similar across loads
//     (≤60% vs >60% of 1RM); heavy loads were better only for 1RM strength. Basis for
//     the "light dumbbells still work if sets go to failure" copy.
//
// WHAT IS A SET HERE: every logged set of a resistance exercise (not cardio or
// mobility). The app records no failure signal (RPE is never entered), so it
// cannot tell a hard set from an easy one; the copy asks for hard sets instead.
// A set counts once toward every group in its exercise's primary movers (including
// pressing and pulling that also trains a delt or biceps), a simplification.

import Foundation

public enum MuscleVolume {

    /// Weekly sets per muscle to aim for: the top band (10+) in Schoenfeld,
    /// Ogborn & Krieger 2017. A target to reach, not a proven threshold.
    public static let weeklySetTarget = 10

    /// The major groups the meta-analysis speaks to. Core, forearms, traps and
    /// lower back are left out: no sourced target covers them here.
    public enum Group: String, CaseIterable, Sendable {
        case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves

        public var title: String {
            switch self {
            case .chest:      return "Chest"
            case .back:       return "Back"
            case .shoulders:  return "Shoulders"
            case .biceps:     return "Biceps"
            case .triceps:    return "Triceps"
            case .quads:      return "Quads"
            case .hamstrings: return "Hamstrings"
            case .glutes:     return "Glutes"
            case .calves:     return "Calves"
            }
        }
    }

    /// There is deliberately no "above range" status: no upper limit is sourced.
    public enum Status: Equatable, Sendable {
        case below
        case reached
    }

    public struct Row: Equatable, Identifiable, Sendable {
        public let group: Group
        public let sets: Int
        public var id: Group { group }
        public var status: Status { sets >= MuscleVolume.weeklySetTarget ? .reached : .below }
    }

    public struct Recommendation: Equatable, Identifiable, Sendable {
        public let group: Group
        public let sets: Int
        /// An exercise the user's kit can do for this group; nil when none fits.
        public let exerciseName: String?
        public var id: Group { group }
        /// One short line, e.g. "Back: 4 of 10 sets this week. Add Pull-up."
        public var text: String {
            let base = "\(group.title): \(sets) of \(MuscleVolume.weeklySetTarget) sets this week."
            return exerciseName.map { base + " Add \($0)." } ?? base
        }
    }

    /// One line for the footer when anything is short: the point of the low-load
    /// study (growth is similar across loads when sets reach failure) plus the
    /// progression levers for when the dumbbells can't get heavier.
    public static let lightLoadTip =
        "Light weights build muscle when sets go to failure. Can't add weight? Slow the lowering, pause at the stretch, add reps, or go one-sided."

    // MARK: Muscle name → group

    /// Maps one `ExerciseInfo` muscle label ("Pectorals", "Anterior delts",
    /// "Biceps (supinated emphasis)"…) to a group; nil for muscles outside the nine.
    /// Order matters: "delt" before "lat" so "Lateral delts" is a shoulder, not a lat.
    public static func group(forMuscle label: String) -> Group? {
        let m = label.lowercased()
        if m.contains("pectoral") { return .chest }
        if m.contains("delt") { return .shoulders }
        if m.contains("biceps") || m.contains("brachialis") { return .biceps }
        if m.contains("triceps") { return .triceps }
        if m.contains("quad") { return .quads }
        if m.contains("hamstring") { return .hamstrings }
        if m.contains("glute") { return .glutes }
        if m.contains("gastrocnemius") || m.contains("soleus") || m.contains("calves") || m.contains("calf") { return .calves }
        if m.hasPrefix("lat") || m.contains("rhomboid") || m.contains("middle trap") || m.contains("teres") { return .back }
        return nil
    }

    /// Groups an exercise trains as a primary mover. Curated exercises use the
    /// `ExerciseInfo` library; custom ones fall back to the muscles stored on the
    /// exercise. Cardio and mobility never count.
    public static func groups(for exercise: ExerciseDTO) -> Set<Group> {
        guard exercise.category != .cardio, exercise.category != .mobility else { return [] }
        let labels = ExerciseInfo.hasCuratedMeta(for: exercise)
            ? ExerciseInfo.meta(for: exercise).muscleGroups
            : exercise.muscleGroups
        return Set(labels.compactMap(group(forMuscle:)))
    }

    // MARK: Weekly counts

    /// Sets per group in the ISO week containing `now` (Monday 00:00 → next Monday),
    /// one row per group in `Group.allCases` order, zero rows included.
    public static func weekly(sets: [WorkoutSetDTO], exercises: [ExerciseDTO], now: Date) -> [Row] {
        let start = Dates.startOfISOWeek(now, weeksAgo: 0)
        let end = Dates.startOfISOWeek(now, weeksAgo: -1)
        var groupsById: [String: Set<Group>] = [:]
        for ex in exercises { groupsById[ex.id] = groups(for: ex) }

        var counts: [Group: Int] = [:]
        for s in sets where s.timestamp >= start && s.timestamp < end && s.reps > 0 {
            for g in groupsById[s.exerciseId] ?? [] { counts[g, default: 0] += 1 }
        }
        return Group.allCases.map { Row(group: $0, sets: counts[$0] ?? 0) }
    }

    // MARK: Recommendations

    /// Exercise picks per group, best home option first. Every name is an
    /// `ExerciseInfo.catalog` entry; the first one the kit can do wins.
    private static let picks: [Group: [String]] = [
        .chest:      ["Push-up", "Chest Fly"],
        .back:       ["Pull-up", "Chin-up", "Dumbbell Row"],
        .shoulders:  ["Pike Push-up", "Lateral Raise", "Overhead Press"],
        .biceps:     ["Chin-up", "Bicep Curl"],
        .triceps:    ["Tricep Extension", "Push-up"],
        .quads:      ["Bulgarian Split Squat", "Lunge", "Squat"],
        .hamstrings: ["Romanian Deadlift", "Glute Bridge"],
        .glutes:     ["Hip Thrust", "Glute Bridge"],
        .calves:     ["Calf Raise"],
    ]

    /// The exercise to name for a group, or nil if nothing fits the kit.
    public static func exercise(for group: Group, equipment: HomeEquipment) -> String? {
        (picks[group] ?? []).first { equipment.canDo(exerciseNamed: $0) }
    }

    /// One recommendation per group below the target, biggest shortfall first
    /// (ties in `Group.allCases` order), at most `limit`.
    public static func recommendations(
        rows: [Row], equipment: HomeEquipment, limit: Int = 3
    ) -> [Recommendation] {
        let order = Dictionary(uniqueKeysWithValues: Group.allCases.enumerated().map { ($1, $0) })
        return rows
            .filter { $0.status == .below }
            .sorted { a, b in
                a.sets != b.sets ? a.sets < b.sets : (order[a.group] ?? 0) < (order[b.group] ?? 0)
            }
            .prefix(limit)
            .map { Recommendation(group: $0.group, sets: $0.sets,
                                  exerciseName: exercise(for: $0.group, equipment: equipment)) }
    }
}
