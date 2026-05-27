// Idempotent seeding on app launch.
//
// Post-Circuit refactor: foods, exercises, programs, and profiles are no
// longer auto-seeded. Profiles are created via ProfileCreationView; exercises
// are per-profile and added by the user; the food library and starter
// programs were stashed pending a fresh take.

import Foundation
import SwiftData

public enum Seeder {
    public static func seedAll(_ ctx: ModelContext) {
        // Intentionally empty. Retained as the App's launch hook so future
        // first-launch seeding has a single call site to land in.
    }
}
