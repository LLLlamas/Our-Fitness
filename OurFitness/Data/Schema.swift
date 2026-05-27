// SwiftData schema versioning.
// To migrate the schema:
//   1. Define a new VersionedSchema (SchemaV2) with the new model types
//   2. Add a MigrationStage to OurFitnessMigrationPlan
//   3. Bump `currentSchema` below
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

public enum OurFitnessMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}

public enum AppSchema {
    public static let current: any VersionedSchema.Type = SchemaV2.self
}
