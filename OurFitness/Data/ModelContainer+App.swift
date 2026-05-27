// SwiftData ModelContainer factory + in-memory variant for tests/previews.

import Foundation
import SwiftData

public enum AppModelContainer {

    /// On-disk container persisted to the app's default location.
    /// Automatically falls back to an in-memory store when running under XCTest
    /// (detected via the XCTestConfigurationFilePath env var that xcodebuild injects
    /// into the test host process), so the on-disk store never crashes the test runner.
    public static func make() -> ModelContainer {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return makeInMemory()
        }
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: SchemaV2.self),
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
                for: Schema(versionedSchema: SchemaV2.self),
                configurations: [
                    ModelConfiguration(isStoredInMemoryOnly: true)
                ]
            )
        } catch {
            fatalError("Could not initialize in-memory ModelContainer: \(error)")
        }
    }
}
