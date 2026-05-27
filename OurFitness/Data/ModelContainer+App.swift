// SwiftData ModelContainer factory + in-memory variant for tests/previews.

import Foundation
import SwiftData

public enum AppModelContainer {

    /// On-disk container persisted to the app's default location.
    /// Automatically falls back to an in-memory store when running under XCTest
    /// (detected via the XCTestConfigurationFilePath env var that xcodebuild injects
    /// into the test host process), so the on-disk store never crashes the test runner.
    ///
    /// If the migration fails (e.g. a broken stage landed in TestFlight), the store
    /// is deleted and rebuilt empty rather than leaving the app permanently unlaunchable.
    public static func make() -> ModelContainer {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return makeInMemory()
        }
        let config = ModelConfiguration()
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: SchemaV3.self),
                migrationPlan: OurFitnessMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            // Migration failed — delete the corrupt/unmigrateable store and start fresh.
            // Both TestFlight users lose local data only if migration itself is broken;
            // a broken migration already means the app is unlaunchable without this path.
            let storeURL = config.url
            try? FileManager.default.removeItem(at: storeURL)
            // Also remove the accompanying WAL journal files (SwiftData uses .store-shm / .store-wal).
            let shmURL = storeURL.appendingPathExtension("shm")
            let walURL = storeURL.appendingPathExtension("wal")
            try? FileManager.default.removeItem(at: shmURL)
            try? FileManager.default.removeItem(at: walURL)
            do {
                return try ModelContainer(
                    for: Schema(versionedSchema: SchemaV3.self),
                    migrationPlan: OurFitnessMigrationPlan.self,
                    configurations: [ModelConfiguration()]
                )
            } catch {
                fatalError("Could not initialize ModelContainer even after store reset: \(error)")
            }
        }
    }

    /// In-memory variant — used by tests, previews, and onboarding seed-only runs.
    public static func makeInMemory() -> ModelContainer {
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: SchemaV3.self),
                configurations: [
                    ModelConfiguration(isStoredInMemoryOnly: true)
                ]
            )
        } catch {
            fatalError("Could not initialize in-memory ModelContainer: \(error)")
        }
    }
}
