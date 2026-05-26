// Idempotent seeding on app launch.
// Two fixed profiles (Build / Reset) are seeded once and never overwritten.

import Foundation
import SwiftData

public enum Seeder {

    public static func seedAll(_ ctx: ModelContext) {
        seedProfiles(ctx)
        seedExercises(ctx)
        seedFoods(ctx)
        seedPrograms(ctx)
        try? ctx.save()
    }

    private static func seedProfiles(_ ctx: ModelContext) {
        for p in SeedProfiles.all {
            let target = p.id
            let desc = FetchDescriptor<ProfileModel>(predicate: #Predicate { $0.id == target })
            if (try? ctx.fetch(desc).first) == nil {
                ctx.insert(ProfileModel(snapshot: p))
            }
        }
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
