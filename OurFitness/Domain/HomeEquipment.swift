// The kit the user actually has at home (pure Swift, no SwiftUI/SwiftData).
//
// A per-profile preference, NOT a schema field: the Train tab keeps it in
// `AppStorage` under `HomeEquipment.storageKey(profileId)` as the string from
// `encoded` ("20,1"). It filters what `ExerciseGoalMatcher` and
// `WorkoutSuggestionService` recommend and which exercise `MuscleVolume` names,
// so nothing is suggested that needs a machine, cable or barbell the user
// does not own.
//
// Which exercise needs what is an explicit table over the catalog names, not a
// guess from the words in a name; an exercise missing from the table is treated
// as needing other gear and is never recommended (a test fails if a catalog
// entry is missing, so a new entry cannot silently vanish from suggestions).

import Foundation

public struct HomeEquipment: Equatable, Sendable {

    /// Heaviest single dumbbell available, in pounds. 0 = no dumbbells.
    public var maxDumbbellLb: Int
    public var hasPullUpBar: Bool

    /// The kit the app is built around: two 20 lb dumbbells and a pull-up bar.
    public static let `default` = HomeEquipment(maxDumbbellLb: 20, hasPullUpBar: true)

    public init(maxDumbbellLb: Int, hasPullUpBar: Bool) {
        self.maxDumbbellLb = max(0, maxDumbbellLb)
        self.hasPullUpBar = hasPullUpBar
    }

    // MARK: Storage

    public static func storageKey(_ profileId: UUID) -> String { "equipment.\(profileId.uuidString)" }

    /// "<dumbbellLb>,<bar 0|1>", e.g. "20,1".
    public var encoded: String { "\(maxDumbbellLb),\(hasPullUpBar ? 1 : 0)" }

    /// Lenient: nil, empty or malformed storage reads as the default kit.
    public init(encoded: String?) {
        let parts = (encoded ?? "").split(separator: ",").map(String.init)
        if parts.count == 2, let lb = Int(parts[0]), lb >= 0, let bar = Int(parts[1]), bar == 0 || bar == 1 {
            maxDumbbellLb = lb
            hasPullUpBar = bar == 1
        } else {
            maxDumbbellLb = Self.default.maxDumbbellLb
            hasPullUpBar = Self.default.hasPullUpBar
        }
    }

    /// Picker choices for the dumbbell weight (0 = none).
    public static let dumbbellChoices: [Int] = [0, 5, 10, 15, 20, 25, 30, 35, 40, 50, 60, 70, 80]

    // MARK: Requirements

    public enum Requirement: Equatable, Sendable {
        case bodyweight
        case pullUpBar
        case dumbbell
        /// Barbell, machine, cable, bench, wheel… anything beyond the home kit.
        case other
    }

    public func canDo(_ requirement: Requirement) -> Bool {
        switch requirement {
        case .bodyweight: return true
        case .pullUpBar:  return hasPullUpBar
        case .dumbbell:   return maxDumbbellLb > 0
        case .other:      return false
        }
    }

    /// Whether the catalog exercise called `name` can be done with this kit.
    /// Unknown names answer false (see the file header).
    public func canDo(exerciseNamed name: String) -> Bool {
        canDo(Self.requirement(forExerciseNamed: name))
    }

    /// Requirement for each `ExerciseInfo.catalog` name. Judgement calls, so
    /// they are listed: Squat / Romanian Deadlift / Hip Thrust / Overhead Press
    /// are dumbbell-doable (goblet, dumbbell RDL, dumbbell on the hips, dumbbell
    /// press); Calf Raise and Russian Twist work with body weight alone; Deadlift
    /// and Kettlebell Swing are listed as barbell / kettlebell lifts.
    private static let table: [String: Requirement] = [
        "Ab Wheel Rollout": .other,
        "Back Extension": .other,
        "Barbell Row": .other,
        "Battle Ropes": .other,
        "Bench Press": .other,
        "Bicep Curl": .dumbbell,
        "Box Jump": .other,
        "Bulgarian Split Squat": .dumbbell,
        "Burpee": .bodyweight,
        "Calf Raise": .bodyweight,
        "Chest Fly": .dumbbell,
        "Chin-up": .pullUpBar,
        "Crunch": .bodyweight,
        "Dead Hang": .pullUpBar,
        "Deadlift": .other,
        "Dip": .other,
        "Dumbbell Row": .dumbbell,
        "Face Pull": .other,
        "Farmer Carry": .dumbbell,
        "Front Raise": .dumbbell,
        "Glute Bridge": .bodyweight,
        "Glute Kickback": .other,
        "Good Morning": .other,
        "Hanging Leg Raise": .pullUpBar,
        "Hip Abduction": .other,
        "Hip Adduction": .other,
        "Hip Thrust": .dumbbell,
        "Kettlebell Swing": .other,
        "L-sit": .bodyweight,
        "Lat Pulldown": .other,
        "Lateral Raise": .dumbbell,
        "Leg Curl": .other,
        "Leg Extension": .other,
        "Leg Press": .other,
        "Lunge": .bodyweight,
        "Mountain Climber": .bodyweight,
        "Overhead Press": .dumbbell,
        "Pike Push-up": .bodyweight,
        "Plank": .bodyweight,
        "Pull-over": .dumbbell,
        "Pull-up": .pullUpBar,
        "Push-up": .bodyweight,
        "Reverse Plank": .bodyweight,
        "Romanian Deadlift": .dumbbell,
        "Russian Twist": .bodyweight,
        "Shrug": .dumbbell,
        "Squat": .dumbbell,
        "Tricep Extension": .dumbbell,
        "Tricep Pushdown": .other,
        "Wall Sit": .bodyweight,
    ]

    /// Whether `name` has an explicit entry (as opposed to the `.other` default).
    public static func isListed(_ name: String) -> Bool { table[name] != nil }

    public static func requirement(forExerciseNamed name: String) -> Requirement {
        table[name] ?? .other
    }
}
