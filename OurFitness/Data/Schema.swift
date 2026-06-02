// SwiftData schema versioning.
//
// V1/V2 are retained as historical references — what actually shipped to
// TestFlight before the V3 cutover. They are no longer reachable: builds 26/27
// crashed on launch because the staged lightweight migration threw an Obj-C
// NSException at stage construction (see ModelContainer+App.swift for context),
// and we sidestepped it by moving to a fresh store URL. No migration plan runs
// today; the live container opens V3 from scratch.
//
// To migrate the schema going forward:
//   1. Define a new VersionedSchema (e.g. SchemaV5) with the new model types
//   2. For STRUCTURAL changes (renaming/splitting/retyping existing entities):
//      write a `.custom` MigrationStage that opens both stores manually —
//      lightweight *staged* migrations have proven fragile in this codebase.
//      For purely ADDITIVE changes (a new optional column or a whole new entity,
//      like WaterEntryModel in V4), no staged plan is needed — the container
//      opens the new schema directly and SwiftData auto-migrates additively.
//   3. Bump `AppSchema.current`
// NEVER edit a shipped schema in place.

import Foundation
import SwiftData

public enum SchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            ProfileModel.self,
            ExerciseModel.self,
            ProgramModel.self,
            WorkoutModel.self,
            WorkoutSetModel.self,
            FoodModel.self,
            FoodLogEntryModel.self,
            BodyMetricModel.self,
            HealthMarkerModel.self,
            StepCountModel.self,
            PilatesSessionModel.self,
        ]
    }
}

/// V2 adds: per-profile custom exercises (ExerciseModel.profileId, optional for
/// back-compat) and CardioSessionModel. ExerciseModel.profileId is optional so
/// the migration is lightweight — V1 rows decode with nil and are no longer
/// surfaced (seed exercises were dropped along with the food library).
public enum SchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            ProfileModel.self,
            ExerciseModel.self,
            ProgramModel.self,
            WorkoutModel.self,
            WorkoutSetModel.self,
            FoodModel.self,
            FoodLogEntryModel.self,
            BodyMetricModel.self,
            HealthMarkerModel.self,
            StepCountModel.self,
            PilatesSessionModel.self,
            CardioSessionModel.self,
        ]
    }
}

/// V3 adds: ExerciseModel.loadLb + ExerciseModel.kindRaw (for known-load
/// exercises like carrying a baby/stroller), WorkoutSetModel.caloriesEst,
/// and CardioSessionModel.caloriesEst. All new fields are optional / have
/// safe defaults — V2 rows migrate lightweight with nil/"reps".
public enum SchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            ProfileModel.self,
            ExerciseModel.self,
            ProgramModel.self,
            WorkoutModel.self,
            WorkoutSetModel.self,
            FoodModel.self,
            FoodLogEntryModel.self,
            BodyMetricModel.self,
            HealthMarkerModel.self,
            StepCountModel.self,
            PilatesSessionModel.self,
            CardioSessionModel.self,
        ]
    }
}

/// V4 adds `WaterEntryModel` (per-tap water intake log). Purely additive — a new
/// entity, no changes to existing ones. SwiftData applies the new table via
/// automatic lightweight migration when the container opens V4 against an
/// existing V3 store; we deliberately ship NO staged `MigrationPlan` (the
/// `NSLightweightMigrationStage` path is what threw the uncatchable Obj-C
/// exception in builds 26/27 — see ModelContainer+App.swift). Automatic additive
/// migration is the same mechanism that absorbed the `isIsometric`/`holdSeconds`
/// field additions without a plan.
public enum SchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            ProfileModel.self,
            ExerciseModel.self,
            ProgramModel.self,
            WorkoutModel.self,
            WorkoutSetModel.self,
            FoodModel.self,
            FoodLogEntryModel.self,
            BodyMetricModel.self,
            HealthMarkerModel.self,
            StepCountModel.self,
            PilatesSessionModel.self,
            CardioSessionModel.self,
            WaterEntryModel.self,
        ]
    }
}

/// V5 adds `ActivitySessionModel` (Live Sessions — timed, duration-based
/// activities like basketball/soccer/swimming). Purely additive — a new entity,
/// no changes to existing ones, exactly like `WaterEntryModel` in V4. SwiftData
/// applies the new table via automatic lightweight migration when the container
/// opens V5 against an existing V4 store; we deliberately ship NO staged
/// `MigrationPlan` (the `NSLightweightMigrationStage` path is what threw the
/// uncatchable Obj-C exception in builds 26/27 — see ModelContainer+App.swift).
public enum SchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            ProfileModel.self,
            ExerciseModel.self,
            ProgramModel.self,
            WorkoutModel.self,
            WorkoutSetModel.self,
            FoodModel.self,
            FoodLogEntryModel.self,
            BodyMetricModel.self,
            HealthMarkerModel.self,
            StepCountModel.self,
            PilatesSessionModel.self,
            CardioSessionModel.self,
            WaterEntryModel.self,
            ActivitySessionModel.self,
        ]
    }
}

/// V6 adds `SavedMealTemplateModel` (personal, reusable ingredient-level meal
/// templates). Purely additive — a new entity, exactly like `WaterEntryModel` in
/// V4 and `ActivitySessionModel` in V5. The new optional `FoodLogEntryModel
/// .ingredientsJSON` column is a lightweight addition that does NOT itself need a
/// version bump (SwiftData adds it automatically) — only the new entity triggers
/// V6. SwiftData applies both via automatic lightweight migration when the
/// container opens V6 against an existing V5 store; we deliberately ship NO staged
/// `MigrationPlan` (the `NSLightweightMigrationStage` path is what threw the
/// uncatchable Obj-C exception in builds 26/27 — see ModelContainer+App.swift).
public enum SchemaV6: VersionedSchema {
    public static let versionIdentifier = Schema.Version(6, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            ProfileModel.self,
            ExerciseModel.self,
            ProgramModel.self,
            WorkoutModel.self,
            WorkoutSetModel.self,
            FoodModel.self,
            FoodLogEntryModel.self,
            BodyMetricModel.self,
            HealthMarkerModel.self,
            StepCountModel.self,
            PilatesSessionModel.self,
            CardioSessionModel.self,
            WaterEntryModel.self,
            ActivitySessionModel.self,
            SavedMealTemplateModel.self,
        ]
    }
}

public enum AppSchema {
    public static let current: any VersionedSchema.Type = SchemaV6.self
}
