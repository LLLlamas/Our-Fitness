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
    public var healthGranted: Bool = false
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
        self.healthGranted = s.healthGranted
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
            healthGranted: healthGranted,
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
        self.healthGranted = s.healthGranted
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
    /// Modes this exercise is offered in. Default covers existing rows so
    /// pre-gating data (mobility, cardio) keeps showing in both modes.
    public var availableForModeRaw: [String] = [Mode.build.rawValue, Mode.circuit.rawValue]
    /// Owning profile. Per-profile custom exercises landed in SchemaV2;
    /// legacy V1 rows decode with `nil` and surface to no profile.
    public var profileId: UUID?
    /// Known weight of the load being moved (e.g. baby, stroller). V3.
    public var loadLb: Double?
    /// "reps" or "duration". V3. Optional so the V2→V3 lightweight stage can
    /// backfill nil into existing rows; snapshot treats nil as .reps.
    public var kindRaw: String?
    /// True for isometric holds (plank, dead hang, etc.). Defaults false for all prior rows.
    public var isIsometric: Bool = false

    public init(snapshot s: ExerciseDTO) {
        self.id = s.id
        self.name = s.name
        self.categoryRaw = s.category.rawValue
        self.muscleGroups = s.muscleGroups
        self.equipmentRaw = s.equipment.map(\.rawValue)
        self.defaultRepRange = s.defaultRepRange
        self.availableForModeRaw = s.availableForMode.map(\.rawValue)
        self.profileId = s.profileId
        self.loadLb = s.loadLb
        self.kindRaw = s.kind.rawValue
        self.isIsometric = s.isIsometric
    }

    public var snapshot: ExerciseDTO {
        ExerciseDTO(
            id: id, name: name,
            category: ExerciseCategory(rawValue: categoryRaw) ?? .compound,
            muscleGroups: muscleGroups,
            equipment: equipmentRaw.compactMap(Equipment.init(rawValue:)),
            defaultRepRange: defaultRepRange,
            availableForMode: availableForModeRaw.compactMap(Mode.init(rawValue:)),
            profileId: profileId,
            loadLb: loadLb,
            kind: ExerciseKind(rawValue: kindRaw ?? ExerciseKind.reps.rawValue) ?? .reps,
            isIsometric: isIsometric
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
    /// MET-based kcal estimate computed at log time. V3.
    public var caloriesEst: Double?
    /// Hold duration in seconds for isometric exercises. reps stores hold count (1 per hold).
    public var holdSeconds: Int?

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
        self.caloriesEst = s.caloriesEst
        self.holdSeconds = s.holdSeconds
    }

    public var snapshot: WorkoutSetDTO {
        WorkoutSetDTO(id: id, userId: userId, exerciseId: exerciseId,
                      workoutId: workoutId, weightLb: weightLb, reps: reps,
                      rpe: rpe, notes: notes, timestamp: timestamp,
                      caloriesEst: caloriesEst, holdSeconds: holdSeconds)
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
    /// JSON-encoded [MealIngredient] for ingredient-level entries. Nil for legacy /
    /// single-food rows. Optional → automatic lightweight column addition (no schema bump).
    public var ingredientsJSON: Data?

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
        self.ingredientsJSON = s.ingredients.flatMap { try? JSONEncoder().encode($0) }
    }

    public var snapshot: FoodLogEntryDTO {
        FoodLogEntryDTO(
            id: id, userId: userId, date: date,
            slot: Slot(rawValue: slotRaw) ?? .other,
            foodId: foodId, customName: customName,
            servings: servings,
            perServing: (try? JSONDecoder().decode(PerServing.self, from: perServingJSON)) ?? .zero,
            timestamp: timestamp,
            ingredients: ingredientsJSON.flatMap { try? JSONDecoder().decode([MealIngredient].self, from: $0) }
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

// MARK: - Pilates sessions

@Model
public final class PilatesSessionModel {
    @Attribute(.unique) public var id: UUID
    public var profileId: UUID
    public var date: Date
    public var durationMinutes: Int
    public var focusAreasRaw: [String]
    public var notes: String?

    public init(snapshot s: PilatesSessionDTO) {
        self.id = s.id
        self.profileId = s.profileId
        self.date = s.date
        self.durationMinutes = s.durationMinutes
        self.focusAreasRaw = s.focusAreas.map(\.rawValue)
        self.notes = s.notes
    }

    public var snapshot: PilatesSessionDTO {
        PilatesSessionDTO(
            id: id, profileId: profileId, date: date,
            durationMinutes: durationMinutes,
            focusAreas: focusAreasRaw.compactMap(PilatesFocusArea.init(rawValue:)),
            notes: notes
        )
    }

    public func apply(_ s: PilatesSessionDTO) {
        self.profileId = s.profileId
        self.date = s.date
        self.durationMinutes = s.durationMinutes
        self.focusAreasRaw = s.focusAreas.map(\.rawValue)
        self.notes = s.notes
    }
}

// MARK: - Cardio sessions (Circuit)

@Model
public final class CardioSessionModel {
    @Attribute(.unique) public var id: UUID
    public var profileId: UUID
    public var date: Date
    public var typeRaw: String
    public var durationMinutes: Int
    public var distanceMiles: Double?
    public var rpe: Double?
    public var notes: String?
    /// MET-based kcal estimate computed at log time. V3.
    public var caloriesEst: Double?

    public init(snapshot s: CardioSessionDTO) {
        self.id = s.id
        self.profileId = s.profileId
        self.date = s.date
        self.typeRaw = s.type.rawValue
        self.durationMinutes = s.durationMinutes
        self.distanceMiles = s.distanceMiles
        self.rpe = s.rpe
        self.notes = s.notes
        self.caloriesEst = s.caloriesEst
    }

    public var snapshot: CardioSessionDTO {
        CardioSessionDTO(
            id: id, profileId: profileId, date: date,
            type: CardioType(rawValue: typeRaw) ?? .walk,
            durationMinutes: durationMinutes,
            distanceMiles: distanceMiles, rpe: rpe, notes: notes,
            caloriesEst: caloriesEst
        )
    }
}

// MARK: - Live activity sessions (V5)

@Model
public final class ActivitySessionModel {
    @Attribute(.unique) public var id: UUID
    public var profileId: UUID
    public var date: Date            // session start
    public var activityId: String
    public var activityName: String
    public var met: Double
    public var durationMinutes: Int  // actual elapsed
    public var expectedMinutes: Int  // planned
    /// MET-based kcal estimate computed at log time.
    public var caloriesEst: Double?
    public var notes: String?

    public init(snapshot s: ActivitySessionDTO) {
        self.id = s.id
        self.profileId = s.profileId
        self.date = s.date
        self.activityId = s.activityId
        self.activityName = s.activityName
        self.met = s.met
        self.durationMinutes = s.durationMinutes
        self.expectedMinutes = s.expectedMinutes
        self.caloriesEst = s.caloriesEst
        self.notes = s.notes
    }

    public var snapshot: ActivitySessionDTO {
        ActivitySessionDTO(
            id: id, profileId: profileId, date: date,
            activityId: activityId, activityName: activityName, met: met,
            durationMinutes: durationMinutes, expectedMinutes: expectedMinutes,
            caloriesEst: caloriesEst, notes: notes
        )
    }
}

// MARK: - Water intake (V4)

@Model
public final class WaterEntryModel {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var date: String      // YYYY-MM-DD local
    public var flOz: Double
    public var timestamp: Date

    public init(snapshot s: WaterEntryDTO) {
        self.id = s.id
        self.userId = s.userId
        self.date = s.date
        self.flOz = s.flOz
        self.timestamp = s.timestamp
    }

    public var snapshot: WaterEntryDTO {
        WaterEntryDTO(id: id, userId: userId, date: date, flOz: flOz, timestamp: timestamp)
    }
}

// MARK: - Saved meal templates (V6)

@Model
final class SavedMealTemplateModel {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var name: String
    var emoji: String
    var ingredientsJSON: Data
    var createdAt: Date

    var snapshot: SavedMealTemplateDTO {
        SavedMealTemplateDTO(
            id: id,
            userId: userId,
            name: name,
            emoji: emoji,
            ingredients: (try? JSONDecoder().decode([MealIngredient].self, from: ingredientsJSON)) ?? [],
            createdAt: createdAt
        )
    }

    init(snapshot s: SavedMealTemplateDTO) {
        self.id = s.id
        self.userId = s.userId
        self.name = s.name
        self.emoji = s.emoji
        self.ingredientsJSON = (try? JSONEncoder().encode(s.ingredients)) ?? Data()
        self.createdAt = s.createdAt
    }
}
