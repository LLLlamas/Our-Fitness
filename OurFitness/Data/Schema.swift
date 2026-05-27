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

public enum OurFitnessMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }
    public static var stages: [MigrationStage] { [] }
}

public enum AppSchema {
    public static let current: any VersionedSchema.Type = SchemaV1.self
}
