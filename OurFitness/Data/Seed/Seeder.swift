// Idempotent seeding on app launch.
//
// Foods, programs, and profiles are not auto-seeded. Profiles are created via
// ProfileCreationView (which seeds the three starter movements through
// Repos.createProfile); other exercises are per-profile and added by the user;
// the food library and starter programs were stashed pending a fresh take.

import Foundation
import SwiftData

public enum Seeder {
    public static func seedAll(_ ctx: ModelContext) {
        // Backstops the built-in "Plants" and "Medication" reminder groups for
        // profiles created before those groups shipped. New profiles get both
        // directly from Repos.createProfile; this just catches everyone else on
        // next launch. Both calls are idempotent.
        for profile in Repos.listProfiles(ctx) {
            Repos.ensurePlantsGroup(ctx, userId: profile.id)
            Repos.ensureMedicationGroup(ctx, userId: profile.id)
        }
        // Heart-health micros now apply to every goal; recompute stored targets
        // that predate that (nil micros). Idempotent.
        Repos.backfillHeartHealthTargets(ctx)
        // Fixed-load rows carry the load they were done at; stamps pre-existing
        // ones once (flagged, so it can never touch rows after a load edit).
        Repos.backfillFixedLoadWeightsOnce(ctx)
    }
}
