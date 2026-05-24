// SwiftData @Model classes. Mirror the Domain DTOs.
// Each model exposes a `snapshot` computed property that returns the matching DTO,
// so domain functions never need to touch SwiftData types.
//
// Schema versioning lives in Data/Schema.swift.

import Foundation
import SwiftData

// MARK: - Profile

@Model
public final class ProfileModel {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var modeRaw: String
    public var sexRaw: String
    public var heightIn: Double
    public var weightLb: Double
    public var age: Int
    public var activityRaw: String
    public var lowAppetite: Bool
    public var restrictions: [String]
    public var budgetWeeklyUsd: Double?
    /// JSON-encoded MacroTargets. Targets recompute when profile vitals change.
    public var targetsJSON: Data
    public var createdAt: Date
    public var updatedAt: Date

    public init(snapshot s: ProfileDTO) {
        self.id = s.id
        self.name = s.name
        self.modeRaw = s.mode.rawValue
        self.sexRaw = s.sex.rawValue
        self.heightIn = s.heightIn
        self.weightLb = s.weightLb
        self.age = s.age
        self.activityRaw = s.activity.rawValue
        self.lowAppetite = s.lowAppetite
        self.restrictions = s.restrictions
        self.budgetWeeklyUsd = s.budgetWeeklyUsd
        self.targetsJSON = (try? JSONEncoder().encode(s.computedTargets)) ?? Data()
        self.createdAt = s.createdAt
        self.updatedAt = s.updatedAt
    }

    public var snapshot: ProfileDTO {
        ProfileDTO(
            id: id, name: name,
            mode: Mode(rawValue: modeRaw) ?? .build,
            sex: Sex(rawValue: sexRaw) ?? .male,
            heightIn: heightIn, weightLb: weightLb, age: age,
            activity: ActivityLevel(rawValue: activityRaw) ?? .moderate,
            lowAppetite: lowAppetite,
            restrictions: restrictions,
            budgetWeeklyUsd: budgetWeeklyUsd,
            computedTargets: (try? JSONDecoder().decode(MacroTargets.self, from: targetsJSON))
                ?? MacroTargets(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, stepsDaily: 0),
            createdAt: createdAt, updatedAt: updatedAt
        )
    }

    public func apply(_ s: ProfileDTO) {
        self.name = s.name
        self.modeRaw = s.mode.rawValue
        self.sexRaw = s.sex.rawValue
        self.heightIn = s.heightIn
        self.weightLb = s.weightLb
        self.age = s.age
        self.activityRaw = s.activity.rawValue
        self.lowAppetite = s.lowAppetite
        self.restrictions = s.restrictions
        self.budgetWeeklyUsd = s.budgetWeeklyUsd
        self.targetsJSON = (try? JSONEncoder().encode(s.computedTargets)) ?? Data()
        self.updatedAt = Date()
    }
}

// MARK: - Exercise

@Model
public final class ExerciseModel {
    @Attribute(.unique) public var id: String
    public var name: String
    public var categoryRaw: String
    public var muscleGroups: [String]
    public var equipmentRaw: [String]
    public var defaultRepRange: [Int]?

    public init(snapshot s: ExerciseDTO) {
        self.id = s.id
        self.name = s.name
        self.categoryRaw = s.category.rawValue
        self.muscleGroups = s.muscleGroups
        self.equipmentRaw = s.equipment.map(\.rawValue)
        self.defaultRepRange = s.defaultRepRange
    }

    public var snapshot: ExerciseDTO {
        ExerciseDTO(
            id: id, name: name,
            category: ExerciseCategory(rawValue: categoryRaw) ?? .compound,
            muscleGroups: muscleGroups,
            equipment: equipmentRaw.compactMap(Equipment.init(rawValue:)),
            defaultRepRange: defaultRepRange
        )
    }
}

// MARK: - Program

@Model
public final class ProgramModel {
    @Attribute(.unique) public var id: String
    public var name: String
    public var modeFitRaw: [String]
    public var progressionRaw: String
    public var notes: String?
    /// JSON-encoded [ProgramDayDTO] — kept flat to avoid a chatty nested-relationship graph.
    public var scheduleJSON: Data

    public init(snapshot s: ProgramDTO) {
        self.id = s.id
        self.name = s.name
        self.modeFitRaw = s.modeFit.map(\.rawValue)
        self.progressionRaw = s.progression.rawValue
        self.notes = s.notes
        self.scheduleJSON = (try? JSONEncoder().encode(s.schedule)) ?? Data()
    }

    public var snapshot: ProgramDTO {
        ProgramDTO(
            id: id, name: name,
            modeFit: modeFitRaw.compactMap(Mode.init(rawValue:)),
            schedule: (try? JSONDecoder().decode([ProgramDayDTO].self, from: scheduleJSON)) ?? [],
            progression: ProgressionScheme(rawValue: progressionRaw) ?? .linear,
            notes: notes
        )
    }
}

// MARK: - Workout + sets

@Model
public final class WorkoutModel {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var programId: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var notes: String?

    public init(id: UUID = UUID(), userId: UUID, programId: String?,
                startedAt: Date = Date(), endedAt: Date? = nil, notes: String? = nil) {
        self.id = id
        self.userId = userId
        self.programId = programId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
    }
}

@Model
public final class WorkoutSetModel {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var exerciseId: String
    public var workoutId: UUID?
    public var weightLb: Double?
    public var reps: Int
    public var rpe: Double?
    public var notes: String?
    public var timestamp: Date

    public init(snapshot s: WorkoutSetDTO) {
        self.id = s.id
        self.userId = s.userId
        self.exerciseId = s.exerciseId
        self.workoutId = s.workoutId
        self.weightLb = s.weightLb
        self.reps = s.reps
        self.rpe = s.rpe
        self.notes = s.notes
        self.timestamp = s.timestamp
    }

    public var snapshot: WorkoutSetDTO {
        WorkoutSetDTO(id: id, userId: userId, exerciseId: exerciseId,
                      workoutId: workoutId, weightLb: weightLb, reps: reps,
                      rpe: rpe, notes: notes, timestamp: timestamp)
    }
}

// MARK: - Food + log

@Model
public final class FoodModel {
    @Attribute(.unique) public var id: String
    public var name: String
    public var modeFitRaw: [String]
    public var categoryRaw: String
    public var recipe: String?
    public var servings: Double
    public var perServingJSON: Data
    public var costUsd: Double
    public var costTierRaw: String
    public var prepMinutes: Int
    public var allergens: [String]
    public var ingredients: [String]
    public var tags: [String]
    public var appetiteFriendly: Bool

    public init(snapshot s: FoodDTO) {
        self.id = s.id
        self.name = s.name
        self.modeFitRaw = s.modeFit.map(\.rawValue)
        self.categoryRaw = s.category.rawValue
        self.recipe = s.recipe
        self.servings = s.servings
        self.perServingJSON = (try? JSONEncoder().encode(s.perServing)) ?? Data()
        self.costUsd = s.costUsd
        self.costTierRaw = s.costTier.rawValue
        self.prepMinutes = s.prepMinutes
        self.allergens = s.allergens
        self.ingredients = s.ingredients
        self.tags = s.tags
        self.appetiteFriendly = s.appetiteFriendly
    }

    public var snapshot: FoodDTO {
        FoodDTO(
            id: id, name: name,
            modeFit: modeFitRaw.compactMap(Mode.init(rawValue:)),
            category: FoodCategory(rawValue: categoryRaw) ?? .main,
            recipe: recipe, servings: servings,
            perServing: (try? JSONDecoder().decode(PerServing.self, from: perServingJSON)) ?? .zero,
            costUsd: costUsd,
            costTier: CostTier(rawValue: costTierRaw) ?? .low,
            prepMinutes: prepMinutes,
            allergens: allergens, ingredients: ingredients, tags: tags,
            appetiteFriendly: appetiteFriendly
        )
    }
}

@Model
public final class FoodLogEntryModel {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var date: String         // YYYY-MM-DD
    public var slotRaw: String
    public var foodId: String?
    public var customName: String?
    public var servings: Double
    public var perServingJSON: Data
    public var timestamp: Date

    public init(snapshot s: FoodLogEntryDTO) {
        self.id = s.id
        self.userId = s.userId
        self.date = s.date
        self.slotRaw = s.slot.rawValue
        self.foodId = s.foodId
        self.customName = s.customName
        self.servings = s.servings
        self.perServingJSON = (try? JSONEncoder().encode(s.perServing)) ?? Data()
        self.timestamp = s.timestamp
    }

    public var snapshot: FoodLogEntryDTO {
        FoodLogEntryDTO(
            id: id, userId: userId, date: date,
            slot: Slot(rawValue: slotRaw) ?? .other,
            foodId: foodId, customName: customName,
            servings: servings,
            perServing: (try? JSONDecoder().decode(PerServing.self, from: perServingJSON)) ?? .zero,
            timestamp: timestamp
        )
    }
}

// MARK: - Body + markers

@Model
public final class BodyMetricModel {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var date: String
    public var weightLb: Double?
    public var bodyFatPct: Double?
    public var waistIn: Double?
    public var notes: String?

    public init(snapshot s: BodyMetricDTO) {
        self.id = s.id
        self.userId = s.userId
        self.date = s.date
        self.weightLb = s.weightLb
        self.bodyFatPct = s.bodyFatPct
        self.waistIn = s.waistIn
        self.notes = s.notes
    }

    public var snapshot: BodyMetricDTO {
        BodyMetricDTO(id: id, userId: userId, date: date,
                      weightLb: weightLb, bodyFatPct: bodyFatPct,
                      waistIn: waistIn, notes: notes)
    }
}

@Model
public final class HealthMarkerModel {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var date: String
    public var kindRaw: String
    public var value: Double
    public var source: String?

    public init(snapshot s: HealthMarkerDTO) {
        self.id = s.id
        self.userId = s.userId
        self.date = s.date
        self.kindRaw = s.kind.rawValue
        self.value = s.value
        self.source = s.source
    }

    public var snapshot: HealthMarkerDTO {
        HealthMarkerDTO(id: id, userId: userId, date: date,
                        kind: HealthMarkerKind(rawValue: kindRaw) ?? .ldl,
                        value: value, source: source)
    }
}

// MARK: - Steps (one per user per day)

@Model
public final class StepCountModel {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var date: String
    public var steps: Int
    public var sourceRaw: String
    public var updatedAt: Date

    public init(snapshot s: StepCountDTO) {
        self.id = s.id
        self.userId = s.userId
        self.date = s.date
        self.steps = s.steps
        self.sourceRaw = s.source.rawValue
        self.updatedAt = s.updatedAt
    }

    public var snapshot: StepCountDTO {
        StepCountDTO(id: id, userId: userId, date: date, steps: steps,
                     source: StepSource(rawValue: sourceRaw) ?? .manual,
                     updatedAt: updatedAt)
    }
}
