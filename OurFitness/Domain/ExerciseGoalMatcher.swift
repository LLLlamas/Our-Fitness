// Free-text training-goal → exercise suggester (pure Swift, no SwiftUI/SwiftData).
//
// Given a plain sentence like "I'm trying to get a bigger back and shoulders",
// this maps the words to the muscles they imply and ranks the curated
// `ExerciseInfo.catalog` by how well each exercise hits those muscles. Each
// suggestion carries a research-backed reason taken straight from the curated
// `Meta.benefits` — the app never fabricates the why.
//
// This is BOTH the on-device fallback for `WorkoutSuggestionService` (when Apple
// Intelligence is unavailable) and the ground truth the model is grounded in:
// the model only ever selects exercise names that exist here, so the muscle data
// and MET stay deterministic.

import Foundation

public enum ExerciseGoalMatcher {

    /// One ranked exercise recommendation for a goal.
    public struct GoalSuggestion: Sendable, Identifiable {
        public let exerciseName: String
        /// Primary movers (research muscle names), for display.
        public let muscleGroups: [String]
        /// The "why" to show prominently — a research-backed benefit statement.
        public let reason: String
        /// An optional second supporting research note.
        public let researchNote: String?
        public let met: Double
        public let isIsometric: Bool
        public let tracksWeight: Bool
        public let repRange: ClosedRange<Int>
        public var id: String { exerciseName }

        public init(
            exerciseName: String, muscleGroups: [String], reason: String,
            researchNote: String?, met: Double, isIsometric: Bool,
            tracksWeight: Bool, repRange: ClosedRange<Int>
        ) {
            self.exerciseName = exerciseName
            self.muscleGroups = muscleGroups
            self.reason = reason
            self.researchNote = researchNote
            self.met = met
            self.isIsometric = isIsometric
            self.tracksWeight = tracksWeight
            self.repRange = repRange
        }
    }

    /// Convenience: build a `GoalSuggestion` from a catalog entry, overriding the
    /// prominent reason (e.g. with an AI-written one) when provided.
    public static func suggestion(
        from entry: ExerciseInfo.CatalogExercise, reason: String? = nil
    ) -> GoalSuggestion {
        GoalSuggestion(
            exerciseName: entry.name,
            muscleGroups: entry.muscleGroups,
            reason: reason ?? entry.meta.benefits.first ?? "",
            researchNote: entry.meta.benefits.first,
            met: entry.meta.met,
            isIsometric: entry.isIsometric,
            tracksWeight: entry.tracksWeight,
            repRange: entry.repRange
        )
    }

    /// Rank the catalog against a free-text goal. Returns up to `limit` suggestions,
    /// most relevant first. `mode` gives a light tilt — Build toward loadable,
    /// progressable lifts; Circuit toward higher calorie-burn, joint-friendly work —
    /// applied only to exercises the goal already makes relevant, so it never
    /// overrides the muscle match. Falls back to compound staples when no body part
    /// is recognised so the user always gets a sensible answer.
    public static func suggestions(for goalText: String, mode: Mode, limit: Int = 5) -> [GoalSuggestion] {
        let lower = goalText.lowercased()

        // 1) Which muscle keywords does the goal imply?
        var targets = Set<String>()
        for (phrases, muscles) in goalMuscleMap {
            if phrases.contains(where: { lower.contains($0) }) {
                targets.formUnion(muscles)
            }
        }

        // 2) Did the user name a specific exercise? Give it a strong head start.
        let directlyNamed = ExerciseInfo.catalog.filter { lower.contains($0.name.lowercased()) }

        let pool = ExerciseInfo.catalog
        let ranked = pool
            .map { entry -> (entry: ExerciseInfo.CatalogExercise, score: Double) in
                let base = score(entry, targets: targets, directlyNamed: directlyNamed)
                // Mode tilt only nudges exercises that are already a match.
                return (entry, base > 0 ? base + modeBias(entry, mode: mode) : 0)
            }
            .filter { $0.score > 0 }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.entry.meta.met != b.entry.meta.met { return a.entry.meta.met > b.entry.meta.met }
                return a.entry.name < b.entry.name
            }

        let chosen: [ExerciseInfo.CatalogExercise]
        if ranked.isEmpty {
            // No recognised body part — recommend the highest-yield compounds.
            let staples = ["Squat", "Deadlift", "Bench Press", "Pull-up", "Overhead Press"]
            chosen = staples.compactMap { name in pool.first { $0.name == name } }
        } else {
            chosen = ranked.prefix(limit).map(\.entry)
        }

        return chosen.prefix(limit).map { entry in
            GoalSuggestion(
                exerciseName: entry.name,
                muscleGroups: entry.muscleGroups,
                reason: entry.meta.benefits.first ?? "",
                researchNote: entry.meta.benefits.dropFirst().first,
                met: entry.meta.met,
                isIsometric: entry.isIsometric,
                tracksWeight: entry.tracksWeight,
                repRange: entry.repRange
            )
        }
    }

    /// Score one exercise against the target muscle keywords. Primary movers count
    /// double; a directly named exercise gets a large flat bonus.
    private static func score(
        _ entry: ExerciseInfo.CatalogExercise,
        targets: Set<String>,
        directlyNamed: [ExerciseInfo.CatalogExercise]
    ) -> Double {
        var s = 0.0
        if directlyNamed.contains(where: { $0.name == entry.name }) { s += 100 }
        guard !targets.isEmpty else { return s }
        for muscle in entry.muscleGroups {
            let m = muscle.lowercased()
            if targets.contains(where: { m.contains($0) }) { s += 2 }
        }
        for muscle in entry.secondaryMuscles {
            let m = muscle.lowercased()
            if targets.contains(where: { m.contains($0) }) { s += 1 }
        }
        return s
    }

    /// A small mode tilt (≤2, well under a muscle match) that breaks ties toward the
    /// kind of training each mode is built around.
    private static func modeBias(_ entry: ExerciseInfo.CatalogExercise, mode: Mode) -> Double {
        switch mode {
        case .build:
            // Hypertrophy: favour loadable, progressable lifts.
            return entry.tracksWeight ? 1.0 : 0
        case .circuit:
            // Fat-loss / cardiometabolic: favour higher calorie-burn + joint-friendly work.
            var b = 0.0
            if entry.meta.met >= 5.0 { b += 1.0 }
            if entry.isIsometric { b += 0.5 }
            if !entry.tracksWeight { b += 0.5 }
            return b
        }
    }

    // MARK: - Goal vocabulary

    /// Everyday body-part words → the anatomical muscle-name substrings used in
    /// `ExerciseInfo.Meta.muscleGroups`. Matched by substring so "shoulders" pulls
    /// every delt, "back" pulls lats/traps/rhomboids/erectors, etc.
    private static let goalMuscleMap: [(phrases: [String], muscles: [String])] = [
        (["back", "v-taper", "v taper", "wider", "lat"],
         ["lat", "rhomboid", "trap", "erector", "teres", "rear delt"]),
        (["shoulder", "delt", "boulder"],
         ["delt", "rotator", "trap"]),
        (["trap", "neck"],
         ["trap", "levator"]),
        (["chest", "pec", "bench"],
         ["pectoral"]),
        (["arm", "guns"],
         ["bicep", "tricep", "brachi", "forearm", "anconeus"]),
        (["bicep", "curl"],
         ["bicep", "brachi"]),
        (["tricep"],
         ["tricep", "anconeus"]),
        (["leg", "lower body", "wheels"],
         ["quad", "hamstring", "glute", "gastrocnemius", "soleus", "adductor"]),
        (["quad", "thigh", "thighs"],
         ["quad"]),
        (["hamstring", "ham string"],
         ["hamstring"]),
        (["glute", "butt", "booty", "posterior"],
         ["glute", "hamstring", "erector"]),
        (["calf", "calves"],
         ["gastrocnemius", "soleus"]),
        (["core", "abs", "ab ", "six pack", "six-pack", "stomach", "midsection"],
         ["abdominis", "oblique", "hip flexor"]),
        (["grip", "forearm"],
         ["forearm", "grip"]),
        (["posture", "upper back"],
         ["rhomboid", "trap", "rear delt", "erector"]),
        (["full body", "everything", "overall", "athletic", "strength"],
         ["quad", "glute", "lat", "pectoral", "delt", "hamstring", "erector"]),
        (["lower back", "low back", "spinal health", "spine health", "bad back", "fix my back", "back pain", "herniated", "lumbar", "deadlift strength"],
         ["erector", "glute", "hamstring"]),
        (["love handles", "muffin top", "obliques", "side abs", "side of my waist", "trim my sides", "side bend"],
         ["oblique", "abdominis"]),
        (["hip flexors", "tight hips", "hip flexor", "kick higher", "high knees"],
         ["hip flexor", "quad"]),
        (["rotator cuff", "shoulder health", "healthy shoulders", "shoulder stability", "fix my shoulder", "shoulder impingement", "shoulder pain", "bulletproof shoulders"],
         ["rotator", "rear delt", "rhomboid"]),
        (["rear delts", "rear delt", "back of my shoulders", "3d shoulders", "round shoulders look", "capped delts"],
         ["rear delt", "rotator", "rhomboid"]),
        (["upper chest", "top of my chest", "upper pecs", "incline chest", "clavicular"],
         ["pectoral", "anterior delt"]),
        // Inner thigh = adductors only — keeping glute/quad backups wrongly surfaced
        // posterior-chain and even hip-ABduction (the opposite) work.
        (["inner thighs", "inner thigh", "thigh gap", "groin strength", "adductor", "squeeze my thighs"],
         ["adductor"]),
        (["outer glutes", "hip stability", "side glutes", "gluteus medius", "hip drop", "stronger hips", "lateral hip"],
         ["medius", "glute", "hip stabil"]),
        (["thicker neck", "neck strength", "traps and neck", "yoke"],
         ["trap", "levator"]),
        (["mobility", "flexibility", "more flexible", "range of motion", "loosen up", "stiff", "limber", "supple"],
         ["hip flexor", "erector", "glute", "hamstring"]),
        (["explosive", "power", "more powerful", "vertical jump", "jump higher", "dunk", "explosiveness", "fast twitch"],
         ["glute", "quad", "hamstring", "gastrocnemius"]),
        (["conditioning", "endurance", "stamina", "work capacity", "less winded", "gas tank", "muscular endurance"],
         ["quad", "glute", "pectoral", "lat", "abdominis"]),
        (["tone", "toned", "definition", "defined", "cutting", "shredded", "ripped", "get lean", "lean out"],
         ["quad", "glute", "pectoral", "lat", "delt", "abdominis", "hamstring", "bicep", "tricep"]),
        (["bigger butt", "round butt", "perky butt", "build my booty", "booty gains", "glute growth", "fuller glutes", "peach"],
         ["glute", "hamstring"]),
        (["waist taper", "v shape", "wider lats", "broad back", "shoulder to waist", "wider frame", "broad shoulders"],
         ["lat", "lateral delt", "teres", "rhomboid"]),
        (["grip strength", "stronger grip", "crush grip", "weak grip", "hand strength", "forearm size", "vascular forearms"],
         ["forearm", "grip", "brachi"]),
        (["athleticism", "more athletic", "sports performance", "all-around athlete", "field sport"],
         ["glute", "quad", "hamstring", "erector", "abdominis", "gastrocnemius", "soleus"]),
        (["balance", "stability", "more stable", "stop wobbling", "single leg", "ankle stability", "steady"],
         ["glute", "quad", "soleus", "abdominis"]),
        (["skinny legs", "chicken legs", "twig legs", "skip leg day", "build my legs up", "thin legs"],
         ["quad", "hamstring", "glute", "gastrocnemius", "adductor"]),
        (["thicker legs", "thicker thighs", "bigger thighs"],
         ["quad", "glute", "hamstring"]),
        (["bigger arms", "sleeve busters", "fill my sleeves", "bigger guns", "arm size", "thicker arms"],
         ["bicep", "tricep", "brachi", "forearm"]),
        (["bicep peak", "taller biceps", "underhand emphasis"],
         ["bicep", "brachi"]),
        (["horseshoe triceps", "horseshoe", "back of the arm", "lockout strength", "tricep size"],
         ["tricep", "anconeus"]),
        (["lower abs", "lower belly", "hold my legs up", "leg raises"],
         ["abdominis", "hip flexor"]),
        (["deep core", "stronger core brace", "anti-rotation", "stabilize my spine", "brace", "vacuum"],
         ["abdominis", "oblique", "erector"]),
        (["bench more", "stronger press", "pressing strength", "lockout my press", "push strength"],
         ["pectoral", "tricep", "anterior delt"]),
        (["pull stronger", "stronger pull", "first pull-up", "first pull up", "back strength", "do a pull-up"],
         ["lat", "bicep", "rhomboid", "teres", "forearm", "grip"]),
        (["sprint", "sprint faster", "run faster", "speed", "acceleration", "stride power"],
         ["glute", "hamstring", "quad", "gastrocnemius"]),
        (["fix my posture", "rounded shoulders", "hunched", "desk posture", "tech neck", "stand taller", "anti-slouch"],
         ["rhomboid", "middle trap", "rear delt", "erector", "rotator"]),
        (["stronger ankles", "ankle strength", "jumpers", "calf endurance", "lower legs", "diamond calves"],
         ["gastrocnemius", "soleus"]),
        (["functional", "everyday strength", "carry groceries", "pick things up", "real-world strength", "longevity"],
         ["glute", "hamstring", "erector", "quad", "lat", "forearm", "grip", "abdominis"]),
        (["serratus", "boxer muscle", "punch power", "rib muscles", "overhead reach"],
         ["serratus", "pectoral", "anterior delt"]),
        (["hourglass", "shapely waist", "snatched waist", "feminine curves"],
         ["glute", "oblique", "abdominis", "lat"]),
    ]
}
