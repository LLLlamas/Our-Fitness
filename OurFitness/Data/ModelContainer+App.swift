// SwiftData ModelContainer factory + in-memory variant for tests/previews.
//
// Migration history note: builds 26 and 27 crashed on launch because SwiftData's
// staged migration (V1→V2→V3) tripped NSLightweightMigrationStage's version-checksum
// validator with an Obj-C NSException — uncatchable from Swift try/catch. The two
// known TestFlight users had no recoverable path forward, so this file uses a fresh
// store URL (`OurFitness.store`) and drops the migration plan entirely. The old
// `default.store` is left on disk untouched; if anyone needs a forensic pull later
// it's still there. Future schema bumps should ship a real custom-stage migration
// rather than reusing the legacy default-URL store.

import Foundation
import SwiftData

public enum AppModelContainer {

    public static func make() -> ModelContainer {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return makeInMemory()
        }
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: SchemaV4.self),
                configurations: [ModelConfiguration(url: storeURL())]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    public static func makeInMemory() -> ModelContainer {
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: SchemaV4.self),
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
        } catch {
            fatalError("Could not initialize in-memory ModelContainer: \(error)")
        }
    }

    private static func storeURL() -> URL {
        let fm = FileManager.default
        let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = (appSupport ?? URL.documentsDirectory)
            .appendingPathComponent("OurFitness", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("OurFitness.store")
    }
}
