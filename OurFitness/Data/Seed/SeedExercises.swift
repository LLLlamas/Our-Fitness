// Lift catalog. Append; don't reorder existing entries (ids are stable).
//
// `availableForMode` gates exercises by mode. Reset stripped strength in §5 of
// the implementation plan — strength entries here stay seeded but only surface
// for Build. Cardio and mobility carry over to both modes.

import Foundation

public enum SeedExercises {
    private static let buildOnly: [Mode] = [.build]
    private static let both: [Mode]      = [.build, .reset]

    public static let all: [ExerciseDTO] = [
        // Barbell compounds — Build only
        .init(id: "ex-back-squat",     name: "Back Squat",         category: .compound, muscleGroups: ["quads","glutes","core"], equipment: [.barbell], defaultRepRange: [5,8], availableForMode: buildOnly),
        .init(id: "ex-front-squat",    name: "Front Squat",        category: .compound, muscleGroups: ["quads","core"], equipment: [.barbell], defaultRepRange: [5,8], availableForMode: buildOnly),
        .init(id: "ex-deadlift",       name: "Conventional Deadlift", category: .compound, muscleGroups: ["hamstrings","glutes","back"], equipment: [.barbell], defaultRepRange: [3,6], availableForMode: buildOnly),
        .init(id: "ex-rdl",            name: "Romanian Deadlift",  category: .compound, muscleGroups: ["hamstrings","glutes"], equipment: [.barbell,.dumbbell], defaultRepRange: [6,10], availableForMode: buildOnly),
        .init(id: "ex-bench-press",    name: "Bench Press",        category: .compound, muscleGroups: ["chest","triceps","front-delts"], equipment: [.barbell], defaultRepRange: [5,8], availableForMode: buildOnly),
        .init(id: "ex-overhead-press", name: "Overhead Press",     category: .compound, muscleGroups: ["shoulders","triceps"], equipment: [.barbell,.dumbbell], defaultRepRange: [5,8], availableForMode: buildOnly),
        .init(id: "ex-barbell-row",    name: "Barbell Row",        category: .compound, muscleGroups: ["back","biceps"], equipment: [.barbell], defaultRepRange: [6,10], availableForMode: buildOnly),
        .init(id: "ex-hip-thrust",     name: "Hip Thrust",         category: .compound, muscleGroups: ["glutes","hamstrings"], equipment: [.barbell], defaultRepRange: [8,12], availableForMode: buildOnly),

        // Dumbbell compounds — Build only
        .init(id: "ex-db-bench",          name: "DB Bench Press",    category: .compound, muscleGroups: ["chest","triceps"], equipment: [.dumbbell], defaultRepRange: [8,12], availableForMode: buildOnly),
        .init(id: "ex-db-row",            name: "DB Row",            category: .compound, muscleGroups: ["back","biceps"], equipment: [.dumbbell], defaultRepRange: [8,12], availableForMode: buildOnly),
        .init(id: "ex-db-incline-bench", name: "DB Incline Bench",  category: .compound, muscleGroups: ["upper-chest","shoulders"], equipment: [.dumbbell], defaultRepRange: [8,12], availableForMode: buildOnly),
        .init(id: "ex-db-shoulder-press", name: "DB Shoulder Press", category: .compound, muscleGroups: ["shoulders","triceps"], equipment: [.dumbbell], defaultRepRange: [8,12], availableForMode: buildOnly),
        .init(id: "ex-db-walking-lunge", name: "DB Walking Lunge",  category: .compound, muscleGroups: ["quads","glutes"], equipment: [.dumbbell], defaultRepRange: [10,12], availableForMode: buildOnly),
        .init(id: "ex-db-goblet-squat",  name: "Goblet Squat",       category: .compound, muscleGroups: ["quads","glutes"], equipment: [.dumbbell,.kettlebell], defaultRepRange: [10,15], availableForMode: buildOnly),

        // Cable / machine — Build only
        .init(id: "ex-lat-pulldown",  name: "Lat Pulldown",      category: .compound, muscleGroups: ["back","biceps"], equipment: [.cable,.machine], defaultRepRange: [8,12], availableForMode: buildOnly),
        .init(id: "ex-cable-row",     name: "Seated Cable Row",  category: .compound, muscleGroups: ["back","biceps"], equipment: [.cable], defaultRepRange: [8,12], availableForMode: buildOnly),
        .init(id: "ex-leg-press",     name: "Leg Press",         category: .compound, muscleGroups: ["quads","glutes"], equipment: [.machine], defaultRepRange: [8,12], availableForMode: buildOnly),
        .init(id: "ex-leg-curl",      name: "Leg Curl",          category: .isolation, muscleGroups: ["hamstrings"], equipment: [.machine], defaultRepRange: [10,15], availableForMode: buildOnly),
        .init(id: "ex-leg-extension", name: "Leg Extension",     category: .isolation, muscleGroups: ["quads"], equipment: [.machine], defaultRepRange: [10,15], availableForMode: buildOnly),

        // Isolation — Build only
        .init(id: "ex-db-curl",         name: "DB Curl",         category: .isolation, muscleGroups: ["biceps"], equipment: [.dumbbell], defaultRepRange: [10,15], availableForMode: buildOnly),
        .init(id: "ex-tricep-pushdown", name: "Tricep Pushdown", category: .isolation, muscleGroups: ["triceps"], equipment: [.cable], defaultRepRange: [10,15], availableForMode: buildOnly),
        .init(id: "ex-lateral-raise",   name: "Lateral Raise",   category: .isolation, muscleGroups: ["side-delts"], equipment: [.dumbbell], defaultRepRange: [12,20], availableForMode: buildOnly),
        .init(id: "ex-face-pull",       name: "Face Pull",       category: .isolation, muscleGroups: ["rear-delts","upper-back"], equipment: [.cable,.band], defaultRepRange: [12,20], availableForMode: buildOnly),
        .init(id: "ex-calf-raise",      name: "Calf Raise",      category: .isolation, muscleGroups: ["calves"], equipment: [.machine,.dumbbell], defaultRepRange: [10,15], availableForMode: buildOnly),

        // Bodyweight strength — Build only (Plank stays mobility-ish but lives in strength tracker)
        .init(id: "ex-pushup",       name: "Push-Up",            category: .bodyweight, muscleGroups: ["chest","triceps"], equipment: [.bodyweight], defaultRepRange: [8,25], availableForMode: buildOnly),
        .init(id: "ex-pullup",       name: "Pull-Up",            category: .bodyweight, muscleGroups: ["back","biceps"], equipment: [.bodyweight], defaultRepRange: [3,12], availableForMode: buildOnly),
        .init(id: "ex-chinup",       name: "Chin-Up",            category: .bodyweight, muscleGroups: ["back","biceps"], equipment: [.bodyweight], defaultRepRange: [3,12], availableForMode: buildOnly),
        .init(id: "ex-dip",          name: "Dip",                category: .bodyweight, muscleGroups: ["chest","triceps"], equipment: [.bodyweight], defaultRepRange: [5,15], availableForMode: buildOnly),
        .init(id: "ex-plank",        name: "Plank",              category: .bodyweight, muscleGroups: ["core"], equipment: [.bodyweight], availableForMode: buildOnly),
        .init(id: "ex-bw-lunge",     name: "Bodyweight Lunge",   category: .bodyweight, muscleGroups: ["quads","glutes"], equipment: [.bodyweight], defaultRepRange: [10,20], availableForMode: buildOnly),
        .init(id: "ex-glute-bridge", name: "Glute Bridge",       category: .bodyweight, muscleGroups: ["glutes"], equipment: [.bodyweight], defaultRepRange: [10,20], availableForMode: buildOnly),

        // Cardio — both modes (Reset uses for active-energy minutes)
        .init(id: "ex-zone2-walk",        name: "Zone 2 Walk",            category: .cardio, muscleGroups: ["cardio"], equipment: [.none], availableForMode: both),
        .init(id: "ex-zone2-bike",        name: "Zone 2 Bike",            category: .cardio, muscleGroups: ["cardio"], equipment: [.machine], availableForMode: both),
        .init(id: "ex-incline-treadmill", name: "Incline Treadmill Walk", category: .cardio, muscleGroups: ["cardio"], equipment: [.machine], availableForMode: both),
        .init(id: "ex-intervals",         name: "Interval Run",           category: .cardio, muscleGroups: ["cardio"], equipment: [.none], availableForMode: both),
        .init(id: "ex-basketball",        name: "Basketball (open run)",  category: .cardio, muscleGroups: ["cardio"], equipment: [.none], availableForMode: both),

        // Mobility — both modes
        .init(id: "ex-couch-stretch",  name: "Couch Stretch",       category: .mobility, muscleGroups: ["hip-flexors"], equipment: [.none], availableForMode: both),
        .init(id: "ex-90-90",          name: "90/90 Hip Mobility",  category: .mobility, muscleGroups: ["hips"], equipment: [.none], availableForMode: both),
        .init(id: "ex-thoracic-rot",   name: "Thoracic Rotation",   category: .mobility, muscleGroups: ["upper-back"], equipment: [.none], availableForMode: both),
    ]
}
