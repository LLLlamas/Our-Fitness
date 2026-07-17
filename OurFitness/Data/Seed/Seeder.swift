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
        // Backstops the built-in "Plants" reminder group for profiles created
        // before the Reminders tab shipped. New profiles get it directly from
        // Repos.createProfile; this just catches everyone else on next launch.
        for profile in Repos.listProfiles(ctx) {
            Repos.ensurePlantsGroup(ctx, userId: profile.id)
        }
    }
}
