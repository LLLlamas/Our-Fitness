// Idempotent seeding on app launch.
// Profiles are NOT seeded — onboarding creates them.

import Foundation
import SwiftData

public enum Seeder {

    public static func seedAll(_ ctx: ModelContext) {
        seedExercises(ctx)
        seedFoods(ctx)
        seedPrograms(ctx)
        try? ctx.save()
    }

    private static func seedExercises(_ ctx: ModelContext) {
        for e in SeedExercises.all {
            Repos.upsertExercise(ctx, e)
        }
    }

    private static func seedFoods(_ ctx: ModelContext) {
        for f in SeedFoodsBuild.all + SeedFoodsReset.all {
            Repos.upsertFood(ctx, f)
        }
    }

    private static func seedPrograms(_ ctx: ModelContext) {
        for p in SeedPrograms.all {
            Repos.upsertProgram(ctx, p)
        }
    }
}
