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
        // Heart-health micros now apply to every goal; recompute stored targets
        // that predate that (nil micros). Idempotent.
        Repos.backfillHeartHealthTargets(ctx)
    }
}
