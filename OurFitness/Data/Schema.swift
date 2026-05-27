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
//   1. Define a new VersionedSchema (SchemaV4) with the new model types
//   2. Write a `.custom` MigrationStage that opens both stores manually —
//      lightweight stages have proven fragile in this codebase
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

public enum AppSchema {
    public static let current: any VersionedSchema.Type = SchemaV3.self
}
