// SwiftData ModelContainer factory + in-memory variant for tests/previews.

import Foundation
import SwiftData

public enum AppModelContainer {

    /// On-disk container persisted to the app's default location.
    public static func make() -> ModelContainer {
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                migrationPlan: OurFitnessMigrationPlan.self,
                configurations: [ModelConfiguration()]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    /// In-memory variant — used by tests, previews, and onboarding seed-only runs.
    public static func makeInMemory() -> ModelContainer {
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: SchemaV1.self),
                configurations: [
                    ModelConfiguration(isStoredInMemoryOnly: true)
                ]
            )
        } catch {
            fatalError("Could not initialize in-memory ModelContainer: \(error)")
        }
    }
}
