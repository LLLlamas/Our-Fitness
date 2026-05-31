// Pure value types used by Domain/* functions and view state.
// SwiftData @Model classes (Data/Models/*) mirror these and expose
// a `snapshot` accessor that returns the matching struct.
//
// Rule: never import SwiftData or SwiftUI from this file.

import Foundation

// MARK: - Enums

public enum Mode: String, Codable, CaseIterable, Sendable {
    case build
    // Raw value pinned to "reset" so SwiftData rows persisted before the
    // Circuit rename keep decoding cleanly. Symbol/UI copy renamed; bump a
    // schema version before changing this raw value.
    case circuit = "reset"

    public var displayName: String {
        switch self {
        case .build:   return "Build"
        case .circuit: return "Circuit"
        }
    }
}

public enum Sex: String, Codable, CaseIterable, Sendable {
    case male, female
}

public enum ActivityLevel: String, Codable, CaseIterable, Sendable {
    case sedentary, light, moderate, active, veryActive

    public var multiplier: Double {
        switch self {
        case .sedentary:  return 1.2
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .active:     return 1.725
        case .veryActive: return 1.9
        }
    }

    public var label: String {
        switch self {
        case .sedentary:  return "Sedentary"
        case .light:      return "Light (1–2x/wk)"
        case .moderate:   return "Moderate (3–5x)"
        case .active:     return "Active (6–7x)"
        case .veryActive: return "Very Active"
        }
    }
}

public enum Slot: String, Codable, CaseIterable, Sendable {
    case pre, breakfast, postWorkout = "post-workout", lunch, snack, dinner, other

    public var label: String {
        switch self {
        case .postWorkout: return "post-workout"
        default:           return rawValue
        }
    }
}

public enum FoodCategory: String, Codable, CaseIterable, Sendable {
    case smoothie, breakfast, main, snack, drink, side, soup, bowl
}

public enum CostTier: String, Codable, Sendable {
    case low, mid, high
}

public enum ExerciseCategory: String, Codable, Sendable {
    case compound, isolation, bodyweight, cardio, mobility
}

public enum Equipment: String, Codable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight, band, kettlebell, none
}

public enum ExerciseKind: String, Codable, CaseIterable, Sendable {
    case reps, duration
}

public enum ProgressionScheme: String, Codable, Sendable {
    case linear
    case doubleProgression = "double-progression"
    case rpeBased = "rpe-based"
}

public enum HealthMarkerKind: String, Codable, CaseIterable, Sendable {
    case bpSystolic       = "bp_systolic"
    case bpDiastolic      = "bp_diastolic"
    case ldl
    case hdl
    case triglycerides
    case totalCholesterol = "total_cholesterol"
    case a1c
    case fastingGlucose   = "fasting_glucose"
    case restingHR        = "resting_hr"
}

public enum StepSource: String, Codable, Sendable {
    case manual, appleHealth = "apple-health"
}

// MARK: - DTOs

public struct MacroTargets: Codable, Equatable, Sendable {
    public var calories: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int
    public var stepsDaily: Int
    // Legacy caps (formerly Reset-only). Retained on the data model; UI no longer renders them.
    public var sodiumMgMax: Int?
    public var addedSugarGMax: Int?
    public var saturatedFatGMax: Int?
    public var fiberGMin: Int?

    public init(
        calories: Int, proteinG: Int, carbsG: Int, fatG: Int, stepsDaily: Int,
        sodiumMgMax: Int? = nil, addedSugarGMax: Int? = nil,
        saturatedFatGMax: Int? = nil, fiberGMin: Int? = nil
    ) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.stepsDaily = stepsDaily
        self.sodiumMgMax = sodiumMgMax
        self.addedSugarGMax = addedSugarGMax
        self.saturatedFatGMax = saturatedFatGMax
        self.fiberGMin = fiberGMin
    }
}

public struct ProfileDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var mode: Mode
    public var sex: Sex
    public var heightIn: Double
    public var weightLb: Double
    public var age: Int
    public var activity: ActivityLevel
    public var lowAppetite: Bool
    public var restrictions: [String]
    public var budgetWeeklyUsd: Double?
    public var computedTargets: MacroTargets
    public var healthGranted: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        mode: Mode,
        sex: Sex,
        heightIn: Double,
        weightLb: Double,
        age: Int,
        activity: ActivityLevel,
        lowAppetite: Bool = false,
        restrictions: [String] = [],
        budgetWeeklyUsd: Double? = nil,
        computedTargets: MacroTargets,
        healthGranted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.sex = sex
        self.heightIn = heightIn
        self.weightLb = weightLb
        self.age = age
        self.activity = activity
        self.lowAppetite = lowAppetite
        self.restrictions = restrictions
        self.budgetWeeklyUsd = budgetWeeklyUsd
        self.computedTargets = computedTargets
        self.healthGranted = healthGranted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PerServing: Codable, Equatable, Sendable {
    public var calories: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int
    public var fiberG: Int
    public var sodiumMg: Int
    public var addedSugarG: Int
    public var saturatedFatG: Int

    public static let zero = PerServing(
        calories: 0, proteinG: 0, carbsG: 0, fatG: 0,
        fiberG: 0, sodiumMg: 0, addedSugarG: 0, saturatedFatG: 0
    )

    public init(
        calories: Int, proteinG: Int, carbsG: Int, fatG: Int,
        fiberG: Int = 0, sodiumMg: Int = 0, addedSugarG: Int = 0, saturatedFatG: Int = 0
    ) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sodiumMg = sodiumMg
        self.addedSugarG = addedSugarG
        self.saturatedFatG = saturatedFatG
    }
}

public struct FoodDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var modeFit: [Mode]
    public var category: FoodCategory
    public var recipe: String?
    public var servings: Double
    public var perServing: PerServing
    public var costUsd: Double
    public var costTier: CostTier
    public var prepMinutes: Int
    public var allergens: [String]
    public var ingredients: [String]
    public var tags: [String]
    public var appetiteFriendly: Bool

    public init(
        id: String, name: String, modeFit: [Mode], category: FoodCategory,
        recipe: String? = nil, servings: Double = 1, perServing: PerServing,
        costUsd: Double, costTier: CostTier, prepMinutes: Int = 5,
        allergens: [String] = [], ingredients: [String] = [], tags: [String] = [],
        appetiteFriendly: Bool = false
    ) {
        self.id = id
        self.name = name
        self.modeFit = modeFit
        self.category = category
        self.recipe = recipe
        self.servings = servings
        self.perServing = perServing
        self.costUsd = costUsd
        self.costTier = costTier
        self.prepMinutes = prepMinutes
        self.allergens = allergens
        self.ingredients = ingredients
        self.tags = tags
        self.appetiteFriendly = appetiteFriendly
    }
}

public struct ExerciseDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var category: ExerciseCategory
    public var muscleGroups: [String]
    public var equipment: [Equipment]
    public var defaultRepRange: [Int]?  // [bottom, top]
    /// Modes this exercise is offered in. Defaults to both modes when decoding
    /// legacy rows. Now that exercises are per-profile (V2), this field is
    /// effectively informational; rep counter sources from `profileId`.
    public var availableForMode: [Mode]
    public var profileId: UUID?
    public var loadLb: Double?
    public var kind: ExerciseKind
    public var isIsometric: Bool

    public init(
        id: String, name: String, category: ExerciseCategory,
        muscleGroups: [String], equipment: [Equipment],
        defaultRepRange: [Int]? = nil,
        availableForMode: [Mode] = [.build, .circuit],
        profileId: UUID? = nil,
        loadLb: Double? = nil,
        kind: ExerciseKind = .reps,
        isIsometric: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.muscleGroups = muscleGroups
        self.equipment = equipment
        self.defaultRepRange = defaultRepRange
        self.availableForMode = availableForMode
        self.profileId = profileId
        self.loadLb = loadLb
        self.kind = kind
        self.isIsometric = isIsometric
    }

    // Codable: tolerate older payloads with no availableForMode/profileId/loadLb/kind/isIsometric field.
    private enum CodingKeys: String, CodingKey {
        case id, name, category, muscleGroups, equipment, defaultRepRange, availableForMode, profileId, loadLb, kind, isIsometric
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.category = try c.decode(ExerciseCategory.self, forKey: .category)
        self.muscleGroups = try c.decode([String].self, forKey: .muscleGroups)
        self.equipment = try c.decode([Equipment].self, forKey: .equipment)
        self.defaultRepRange = try c.decodeIfPresent([Int].self, forKey: .defaultRepRange)
        self.availableForMode = try c.decodeIfPresent([Mode].self, forKey: .availableForMode)
            ?? [.build, .circuit]
        self.profileId = try c.decodeIfPresent(UUID.self, forKey: .profileId)
        self.loadLb = try c.decodeIfPresent(Double.self, forKey: .loadLb)
        self.kind = try c.decodeIfPresent(ExerciseKind.self, forKey: .kind) ?? .reps
        self.isIsometric = try c.decodeIfPresent(Bool.self, forKey: .isIsometric) ?? false
    }
}

// MARK: - Pilates

public enum PilatesFocusArea: String, Codable, CaseIterable, Sendable {
    case core, lowerBack = "lower-back", hips, fullBody = "full-body", flexibility

    public var label: String {
        switch self {
        case .core:        return "Core"
        case .lowerBack:   return "Lower Back"
        case .hips:        return "Hips"
        case .fullBody:    return "Full Body"
        case .flexibility: return "Flexibility"
        }
    }
}

public struct PilatesSessionDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var profileId: UUID
    public var date: Date
    public var durationMinutes: Int
    public var focusAreas: [PilatesFocusArea]
    public var notes: String?

    public init(id: UUID = UUID(), profileId: UUID, date: Date = Date(),
                durationMinutes: Int, focusAreas: [PilatesFocusArea],
                notes: String? = nil) {
        self.id = id
        self.profileId = profileId
        self.date = date
        self.durationMinutes = durationMinutes
        self.focusAreas = focusAreas
        self.notes = notes
    }
}

public struct ProgramSetSpec: Codable, Equatable, Sendable {
    public var exerciseId: String
    public var sets: Int
    public var repsBottom: Int
    public var repsTop: Int
    public var rpeCap: Double?
    public var restSeconds: Int?

    public init(exerciseId: String, sets: Int, repsBottom: Int, repsTop: Int,
                rpeCap: Double? = nil, restSeconds: Int? = nil) {
        self.exerciseId = exerciseId
        self.sets = sets
        self.repsBottom = repsBottom
        self.repsTop = repsTop
        self.rpeCap = rpeCap
        self.restSeconds = restSeconds
    }
}

public struct ProgramDayDTO: Codable, Equatable, Sendable {
    public var label: String
    public var blocks: [ProgramSetSpec]
    public init(label: String, blocks: [ProgramSetSpec]) {
        self.label = label
        self.blocks = blocks
    }
}

public struct ProgramDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var modeFit: [Mode]
    public var schedule: [ProgramDayDTO]
    public var progression: ProgressionScheme
    public var notes: String?
    public init(id: String, name: String, modeFit: [Mode],
                schedule: [ProgramDayDTO], progression: ProgressionScheme, notes: String? = nil) {
        self.id = id
        self.name = name
        self.modeFit = modeFit
        self.schedule = schedule
        self.progression = progression
        self.notes = notes
    }
}

public struct WorkoutSetDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var exerciseId: String
    public var workoutId: UUID?
    public var weightLb: Double?
    public var reps: Int
    public var rpe: Double?
    public var notes: String?
    public var timestamp: Date
    public var caloriesEst: Double?
    /// Seconds held for isometric exercises. `reps` stores hold count (1 per completed hold).
    public var holdSeconds: Int?

    public init(id: UUID = UUID(), userId: UUID, exerciseId: String,
                workoutId: UUID? = nil, weightLb: Double? = nil, reps: Int,
                rpe: Double? = nil, notes: String? = nil, timestamp: Date = Date(),
                caloriesEst: Double? = nil, holdSeconds: Int? = nil) {
        self.id = id
        self.userId = userId
        self.exerciseId = exerciseId
        self.workoutId = workoutId
        self.weightLb = weightLb
        self.reps = reps
        self.rpe = rpe
        self.notes = notes
        self.timestamp = timestamp
        self.caloriesEst = caloriesEst
        self.holdSeconds = holdSeconds
    }

    // Codable: tolerate older payloads with no caloriesEst/holdSeconds field.
    private enum CodingKeys: String, CodingKey {
        case id, userId, exerciseId, workoutId, weightLb, reps, rpe, notes, timestamp, caloriesEst, holdSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.userId = try c.decode(UUID.self, forKey: .userId)
        self.exerciseId = try c.decode(String.self, forKey: .exerciseId)
        self.workoutId = try c.decodeIfPresent(UUID.self, forKey: .workoutId)
        self.weightLb = try c.decodeIfPresent(Double.self, forKey: .weightLb)
        self.reps = try c.decode(Int.self, forKey: .reps)
        self.rpe = try c.decodeIfPresent(Double.self, forKey: .rpe)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.timestamp = try c.decode(Date.self, forKey: .timestamp)
        self.caloriesEst = try c.decodeIfPresent(Double.self, forKey: .caloriesEst)
        self.holdSeconds = try c.decodeIfPresent(Int.self, forKey: .holdSeconds)
    }
}

public struct FoodLogEntryDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var date: String          // YYYY-MM-DD local
    public var slot: Slot
    public var foodId: String?
    public var customName: String?
    public var servings: Double
    public var perServing: PerServing  // denormalized snapshot
    public var timestamp: Date

    public init(id: UUID = UUID(), userId: UUID, date: String, slot: Slot,
                foodId: String? = nil, customName: String? = nil, servings: Double = 1,
                perServing: PerServing, timestamp: Date = Date()) {
        self.id = id
        self.userId = userId
        self.date = date
        self.slot = slot
        self.foodId = foodId
        self.customName = customName
        self.servings = servings
        self.perServing = perServing
        self.timestamp = timestamp
    }
}

public struct BodyMetricDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var date: String
    public var weightLb: Double?
    public var bodyFatPct: Double?
    public var waistIn: Double?
    public var notes: String?

    public init(id: UUID = UUID(), userId: UUID, date: String,
                weightLb: Double? = nil, bodyFatPct: Double? = nil,
                waistIn: Double? = nil, notes: String? = nil) {
        self.id = id
        self.userId = userId
        self.date = date
        self.weightLb = weightLb
        self.bodyFatPct = bodyFatPct
        self.waistIn = waistIn
        self.notes = notes
    }
}

public struct HealthMarkerDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var date: String
    public var kind: HealthMarkerKind
    public var value: Double
    public var source: String?

    public init(id: UUID = UUID(), userId: UUID, date: String,
                kind: HealthMarkerKind, value: Double, source: String? = nil) {
        self.id = id
        self.userId = userId
        self.date = date
        self.kind = kind
        self.value = value
        self.source = source
    }
}

public struct StepCountDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var date: String          // YYYY-MM-DD; one per user per day
    public var steps: Int
    public var source: StepSource
    public var updatedAt: Date

    public init(id: UUID = UUID(), userId: UUID, date: String, steps: Int,
                source: StepSource = .manual, updatedAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.date = date
        self.steps = steps
        self.source = source
        self.updatedAt = updatedAt
    }
}

// MARK: - Derived view-model types

public struct DailyTotals: Equatable, Sendable {
    public var calories: Int = 0
    public var proteinG: Int = 0
    public var carbsG: Int = 0
    public var fatG: Int = 0
    public var fiberG: Int = 0
    public var sodiumMg: Int = 0
    public var addedSugarG: Int = 0
    public var saturatedFatG: Int = 0

    public static let zero = DailyTotals()

    public init() {}

    public static func totals(from entries: [FoodLogEntryDTO]) -> DailyTotals {
        entries.reduce(into: DailyTotals.zero) { acc, e in
            let p = e.perServing
            acc.calories      += p.calories
            acc.proteinG      += p.proteinG
            acc.carbsG        += p.carbsG
            acc.fatG          += p.fatG
            acc.fiberG        += p.fiberG
            acc.sodiumMg      += p.sodiumMg
            acc.addedSugarG   += p.addedSugarG
            acc.saturatedFatG += p.saturatedFatG
        }
    }
}

public struct RemainingMacros: Equatable, Sendable {
    public var calories: Int
    public var proteinG: Int
    public var carbsG: Int
    public var fatG: Int
    public var sodiumMg: Int?
    public var addedSugarG: Int?
    public var saturatedFatG: Int?
    public var fiberG: Int?       // negative until floor met

    public init(calories: Int, proteinG: Int, carbsG: Int, fatG: Int,
                sodiumMg: Int? = nil, addedSugarG: Int? = nil,
                saturatedFatG: Int? = nil, fiberG: Int? = nil) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.sodiumMg = sodiumMg
        self.addedSugarG = addedSugarG
        self.saturatedFatG = saturatedFatG
        self.fiberG = fiberG
    }
}

// MARK: - Cardio sessions (Circuit)

public enum CardioType: String, Codable, CaseIterable, Sendable {
    case walk, run, bike, swim, elliptical, other

    public var label: String {
        switch self {
        case .walk:       return "Walk"
        case .run:        return "Run"
        case .bike:       return "Bike"
        case .swim:       return "Swim"
        case .elliptical: return "Elliptical"
        case .other:      return "Other"
        }
    }
}

public struct CardioSessionDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var profileId: UUID
    public var date: Date
    public var type: CardioType
    public var durationMinutes: Int
    public var distanceMiles: Double?
    public var rpe: Double?
    public var notes: String?
    public var caloriesEst: Double?

    public init(id: UUID = UUID(), profileId: UUID, date: Date = Date(),
                type: CardioType, durationMinutes: Int,
                distanceMiles: Double? = nil, rpe: Double? = nil,
                notes: String? = nil, caloriesEst: Double? = nil) {
        self.id = id
        self.profileId = profileId
        self.date = date
        self.type = type
        self.durationMinutes = durationMinutes
        self.distanceMiles = distanceMiles
        self.rpe = rpe
        self.notes = notes
        self.caloriesEst = caloriesEst
    }

    // Codable: tolerate older payloads with no caloriesEst field.
    private enum CodingKeys: String, CodingKey {
        case id, profileId, date, type, durationMinutes, distanceMiles, rpe, notes, caloriesEst
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.profileId = try c.decode(UUID.self, forKey: .profileId)
        self.date = try c.decode(Date.self, forKey: .date)
        self.type = try c.decode(CardioType.self, forKey: .type)
        self.durationMinutes = try c.decode(Int.self, forKey: .durationMinutes)
        self.distanceMiles = try c.decodeIfPresent(Double.self, forKey: .distanceMiles)
        self.rpe = try c.decodeIfPresent(Double.self, forKey: .rpe)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.caloriesEst = try c.decodeIfPresent(Double.self, forKey: .caloriesEst)
    }
}
