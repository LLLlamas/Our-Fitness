// Lift catalog. Append; don't reorder existing entries (ids are stable).

import Foundation

public enum SeedExercises {
    public static let all: [ExerciseDTO] = [
        // Barbell compounds
        .init(id: "ex-back-squat",     name: "Back Squat",         category: .compound, muscleGroups: ["quads","glutes","core"], equipment: [.barbell], defaultRepRange: [5,8]),
        .init(id: "ex-front-squat",    name: "Front Squat",        category: .compound, muscleGroups: ["quads","core"], equipment: [.barbell], defaultRepRange: [5,8]),
        .init(id: "ex-deadlift",       name: "Conventional Deadlift", category: .compound, muscleGroups: ["hamstrings","glutes","back"], equipment: [.barbell], defaultRepRange: [3,6]),
        .init(id: "ex-rdl",            name: "Romanian Deadlift",  category: .compound, muscleGroups: ["hamstrings","glutes"], equipment: [.barbell,.dumbbell], defaultRepRange: [6,10]),
        .init(id: "ex-bench-press",    name: "Bench Press",        category: .compound, muscleGroups: ["chest","triceps","front-delts"], equipment: [.barbell], defaultRepRange: [5,8]),
        .init(id: "ex-overhead-press", name: "Overhead Press",     category: .compound, muscleGroups: ["shoulders","triceps"], equipment: [.barbell,.dumbbell], defaultRepRange: [5,8]),
        .init(id: "ex-barbell-row",    name: "Barbell Row",        category: .compound, muscleGroups: ["back","biceps"], equipment: [.barbell], defaultRepRange: [6,10]),
        .init(id: "ex-hip-thrust",     name: "Hip Thrust",         category: .compound, muscleGroups: ["glutes","hamstrings"], equipment: [.barbell], defaultRepRange: [8,12]),

        // Dumbbell compounds
        .init(id: "ex-db-bench",          name: "DB Bench Press",    category: .compound, muscleGroups: ["chest","triceps"], equipment: [.dumbbell], defaultRepRange: [8,12]),
        .init(id: "ex-db-row",            name: "DB Row",            category: .compound, muscleGroups: ["back","biceps"], equipment: [.dumbbell], defaultRepRange: [8,12]),
        .init(id: "ex-db-incline-bench", name: "DB Incline Bench",  category: .compound, muscleGroups: ["upper-chest","shoulders"], equipment: [.dumbbell], defaultRepRange: [8,12]),
        .init(id: "ex-db-shoulder-press", name: "DB Shoulder Press", category: .compound, muscleGroups: ["shoulders","triceps"], equipment: [.dumbbell], defaultRepRange: [8,12]),
        .init(id: "ex-db-walking-lunge", name: "DB Walking Lunge",  category: .compound, muscleGroups: ["quads","glutes"], equipment: [.dumbbell], defaultRepRange: [10,12]),
        .init(id: "ex-db-goblet-squat",  name: "Goblet Squat",       category: .compound, muscleGroups: ["quads","glutes"], equipment: [.dumbbell,.kettlebell], defaultRepRange: [10,15]),

        // Cable / machine
        .init(id: "ex-lat-pulldown",  name: "Lat Pulldown",      category: .compound, muscleGroups: ["back","biceps"], equipment: [.cable,.machine], defaultRepRange: [8,12]),
        .init(id: "ex-cable-row",     name: "Seated Cable Row",  category: .compound, muscleGroups: ["back","biceps"], equipment: [.cable], defaultRepRange: [8,12]),
        .init(id: "ex-leg-press",     name: "Leg Press",         category: .compound, muscleGroups: ["quads","glutes"], equipment: [.machine], defaultRepRange: [8,12]),
        .init(id: "ex-leg-curl",      name: "Leg Curl",          category: .isolation, muscleGroups: ["hamstrings"], equipment: [.machine], defaultRepRange: [10,15]),
        .init(id: "ex-leg-extension", name: "Leg Extension",     category: .isolation, muscleGroups: ["quads"], equipment: [.machine], defaultRepRange: [10,15]),

        // Isolation
        .init(id: "ex-db-curl",         name: "DB Curl",         category: .isolation, muscleGroups: ["biceps"], equipment: [.dumbbell], defaultRepRange: [10,15]),
        .init(id: "ex-tricep-pushdown", name: "Tricep Pushdown", category: .isolation, muscleGroups: ["triceps"], equipment: [.cable], defaultRepRange: [10,15]),
        .init(id: "ex-lateral-raise",   name: "Lateral Raise",   category: .isolation, muscleGroups: ["side-delts"], equipment: [.dumbbell], defaultRepRange: [12,20]),
        .init(id: "ex-face-pull",       name: "Face Pull",       category: .isolation, muscleGroups: ["rear-delts","upper-back"], equipment: [.cable,.band], defaultRepRange: [12,20]),
        .init(id: "ex-calf-raise",      name: "Calf Raise",      category: .isolation, muscleGroups: ["calves"], equipment: [.machine,.dumbbell], defaultRepRange: [10,15]),

        // Bodyweight
        .init(id: "ex-pushup",       name: "Push-Up",            category: .bodyweight, muscleGroups: ["chest","triceps"], equipment: [.bodyweight], defaultRepRange: [8,25]),
        .init(id: "ex-pullup",       name: "Pull-Up",            category: .bodyweight, muscleGroups: ["back","biceps"], equipment: [.bodyweight], defaultRepRange: [3,12]),
        .init(id: "ex-chinup",       name: "Chin-Up",            category: .bodyweight, muscleGroups: ["back","biceps"], equipment: [.bodyweight], defaultRepRange: [3,12]),
        .init(id: "ex-dip",          name: "Dip",                category: .bodyweight, muscleGroups: ["chest","triceps"], equipment: [.bodyweight], defaultRepRange: [5,15]),
        .init(id: "ex-plank",        name: "Plank",              category: .bodyweight, muscleGroups: ["core"], equipment: [.bodyweight]),
        .init(id: "ex-bw-lunge",     name: "Bodyweight Lunge",   category: .bodyweight, muscleGroups: ["quads","glutes"], equipment: [.bodyweight], defaultRepRange: [10,20]),
        .init(id: "ex-glute-bridge", name: "Glute Bridge",       category: .bodyweight, muscleGroups: ["glutes"], equipment: [.bodyweight], defaultRepRange: [10,20]),

        // Cardio
        .init(id: "ex-zone2-walk",        name: "Zone 2 Walk",            category: .cardio, muscleGroups: ["cardio"], equipment: [.none]),
        .init(id: "ex-zone2-bike",        name: "Zone 2 Bike",            category: .cardio, muscleGroups: ["cardio"], equipment: [.machine]),
        .init(id: "ex-incline-treadmill", name: "Incline Treadmill Walk", category: .cardio, muscleGroups: ["cardio"], equipment: [.machine]),
        .init(id: "ex-intervals",         name: "Interval Run",           category: .cardio, muscleGroups: ["cardio"], equipment: [.none]),
        .init(id: "ex-basketball",        name: "Basketball (open run)",  category: .cardio, muscleGroups: ["cardio"], equipment: [.none]),

        // Mobility
        .init(id: "ex-couch-stretch",  name: "Couch Stretch",       category: .mobility, muscleGroups: ["hip-flexors"], equipment: [.none]),
        .init(id: "ex-90-90",          name: "90/90 Hip Mobility",  category: .mobility, muscleGroups: ["hips"], equipment: [.none]),
        .init(id: "ex-thoracic-rot",   name: "Thoracic Rotation",   category: .mobility, muscleGroups: ["upper-back"], equipment: [.none]),
    ]
}
