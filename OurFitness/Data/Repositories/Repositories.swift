// Repository helpers over ModelContext.
// UI uses these (or @Query) instead of writing raw SwiftData predicates everywhere.
// Keep mutation paths small and consistent.

import Foundation
import SwiftData

public enum Repos {

    // MARK: - Profiles

    public static func listProfiles(_ ctx: ModelContext) -> [ProfileDTO] {
        let desc = FetchDescriptor<ProfileModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    public static func setHealthGranted(_ ctx: ModelContext, profileId: UUID, granted: Bool) {
        let target = profileId
        let desc = FetchDescriptor<ProfileModel>(predicate: #Predicate { $0.id == target })
        if let existing = try? ctx.fetch(desc).first {
            existing.healthGranted = granted
            existing.updatedAt = Date()
            try? ctx.save()
        }
    }

    /// Create a brand-new profile. Computes MacroTargets from the supplied
    /// vitals so callers don't need to thread Targets.compute themselves.
    @discardableResult
    public static func createProfile(
        _ ctx: ModelContext,
        name: String,
        mode: Mode,
        sex: Sex,
        heightIn: Double,
        weightLb: Double,
        age: Int,
        activity: ActivityLevel,
        healthGranted: Bool = false
    ) -> ProfileDTO {
        let vitals = Targets.ProfileVitals(
            sex: sex, weightLb: weightLb, heightIn: heightIn, age: age, activity: activity
        )
        let dto = ProfileDTO(
            name: name, mode: mode, sex: sex,
            heightIn: heightIn, weightLb: weightLb, age: age, activity: activity,
            computedTargets: Targets.compute(mode: mode, vitals: vitals),
            healthGranted: healthGranted
        )
        ctx.insert(ProfileModel(snapshot: dto))
        try? ctx.save()
        return dto
    }

    public static func saveProfile(_ ctx: ModelContext, _ p: ProfileDTO) {
        let target = p.id
        let desc = FetchDescriptor<ProfileModel>(
            predicate: #Predicate { $0.id == target }
        )
        if let existing = try? ctx.fetch(desc).first {
            existing.apply(p)
        } else {
            ctx.insert(ProfileModel(snapshot: p))
        }
        try? ctx.save()
    }

    // MARK: - Exercises

    public static func listExercises(_ ctx: ModelContext) -> [ExerciseDTO] {
        let desc = FetchDescriptor<ExerciseModel>(
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    public static func exercises(_ ctx: ModelContext, forProfile profileId: UUID) -> [ExerciseDTO] {
        let desc = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate { $0.profileId == profileId },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    @discardableResult
    public static func createExercise(
        _ ctx: ModelContext,
        profileId: UUID,
        name: String,
        defaultRepsBottom: Int,
        defaultRepsTop: Int,
        tracksWeight: Bool
    ) -> ExerciseDTO {
        let dto = ExerciseDTO(
            id: "ex-\(profileId.uuidString.prefix(8))-\(UUID().uuidString.prefix(8))",
            name: name,
            category: tracksWeight ? .compound : .bodyweight,
            muscleGroups: [],
            equipment: tracksWeight ? [.dumbbell] : [.bodyweight],
            defaultRepRange: [defaultRepsBottom, defaultRepsTop],
            availableForMode: [.build, .circuit],
            profileId: profileId
        )
        ctx.insert(ExerciseModel(snapshot: dto))
        try? ctx.save()
        return dto
    }

    public static func deleteExercise(_ ctx: ModelContext, id: String) {
        let desc = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.id == id })
        if let target = try? ctx.fetch(desc).first {
            ctx.delete(target)
            try? ctx.save()
        }
    }

    // MARK: - Food log

    public static func listFoodLog(_ ctx: ModelContext, userId: UUID, date: String? = nil) -> [FoodLogEntryDTO] {
        var desc: FetchDescriptor<FoodLogEntryModel>
        if let date {
            desc = FetchDescriptor<FoodLogEntryModel>(
                predicate: #Predicate { $0.userId == userId && $0.date == date },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
        } else {
            desc = FetchDescriptor<FoodLogEntryModel>(
                predicate: #Predicate { $0.userId == userId },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        }
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    public static func addFoodLog(_ ctx: ModelContext, _ entry: FoodLogEntryDTO) {
        ctx.insert(FoodLogEntryModel(snapshot: entry))
        try? ctx.save()
    }

    public static func deleteFoodLog(_ ctx: ModelContext, id: UUID) {
        let desc = FetchDescriptor<FoodLogEntryModel>(predicate: #Predicate { $0.id == id })
        if let target = try? ctx.fetch(desc).first {
            ctx.delete(target)
            try? ctx.save()
        }
    }

    // MARK: - Workouts + sets

    public static func startWorkout(_ ctx: ModelContext, userId: UUID, programId: String?) -> UUID {
        let id = UUID()
        ctx.insert(WorkoutModel(id: id, userId: userId, programId: programId))
        try? ctx.save()
        return id
    }

    public static func endWorkout(_ ctx: ModelContext, id: UUID) {
        let desc = FetchDescriptor<WorkoutModel>(predicate: #Predicate { $0.id == id })
        if let w = try? ctx.fetch(desc).first {
            w.endedAt = Date()
            try? ctx.save()
        }
    }

    public static func addSet(_ ctx: ModelContext, _ s: WorkoutSetDTO) {
        ctx.insert(WorkoutSetModel(snapshot: s))
        try? ctx.save()
    }

    public static func setHistory(_ ctx: ModelContext, userId: UUID, exerciseId: String, limit: Int = 50) -> [WorkoutSetDTO] {
        var desc = FetchDescriptor<WorkoutSetModel>(
            predicate: #Predicate { $0.userId == userId && $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = limit
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    // MARK: - Body + markers

    public static func listBody(_ ctx: ModelContext, userId: UUID) -> [BodyMetricDTO] {
        let desc = FetchDescriptor<BodyMetricModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    public static func addBody(_ ctx: ModelContext, _ b: BodyMetricDTO) {
        ctx.insert(BodyMetricModel(snapshot: b))
        try? ctx.save()
    }

    public static func listMarkers(_ ctx: ModelContext, userId: UUID) -> [HealthMarkerDTO] {
        let desc = FetchDescriptor<HealthMarkerModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    public static func addMarker(_ ctx: ModelContext, _ m: HealthMarkerDTO) {
        ctx.insert(HealthMarkerModel(snapshot: m))
        try? ctx.save()
    }

    // MARK: - Steps

    public static func listSteps(_ ctx: ModelContext, userId: UUID, limit: Int = 365) -> [StepCountDTO] {
        var desc = FetchDescriptor<StepCountModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        desc.fetchLimit = limit
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    // MARK: - Pilates sessions

    public static func logPilatesSession(_ ctx: ModelContext, _ s: PilatesSessionDTO) {
        ctx.insert(PilatesSessionModel(snapshot: s))
        try? ctx.save()
    }

    public static func recentPilatesSessions(
        _ ctx: ModelContext, profileId: UUID, limit: Int = 5
    ) -> [PilatesSessionDTO] {
        var desc = FetchDescriptor<PilatesSessionModel>(
            predicate: #Predicate { $0.profileId == profileId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        desc.fetchLimit = limit
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    public static func pilatesSessionsThisWeek(
        _ ctx: ModelContext, profileId: UUID, now: Date = Date()
    ) -> [PilatesSessionDTO] {
        let all = listPilatesSessions(ctx, profileId: profileId)
        return Movement.sessionsThisWeek(all, now: now)
    }

    public static func listPilatesSessions(
        _ ctx: ModelContext, profileId: UUID
    ) -> [PilatesSessionDTO] {
        let desc = FetchDescriptor<PilatesSessionModel>(
            predicate: #Predicate { $0.profileId == profileId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    // MARK: - Cardio sessions

    public static func logCardio(_ ctx: ModelContext, _ s: CardioSessionDTO) {
        ctx.insert(CardioSessionModel(snapshot: s))
        try? ctx.save()
    }

    public static func listCardio(
        _ ctx: ModelContext, profileId: UUID, limit: Int = 50
    ) -> [CardioSessionDTO] {
        var desc = FetchDescriptor<CardioSessionModel>(
            predicate: #Predicate { $0.profileId == profileId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        desc.fetchLimit = limit
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    /// UPSERT by (userId, date). Used by both manual entry and HealthKit sync.
    public static func setSteps(_ ctx: ModelContext, userId: UUID, date: String, steps: Int, source: StepSource) {
        let desc = FetchDescriptor<StepCountModel>(
            predicate: #Predicate { $0.userId == userId && $0.date == date }
        )
        if let existing = try? ctx.fetch(desc).first {
            existing.steps = steps
            existing.sourceRaw = source.rawValue
            existing.updatedAt = Date()
        } else {
            ctx.insert(StepCountModel(snapshot: StepCountDTO(
                userId: userId, date: date, steps: steps, source: source
            )))
        }
        try? ctx.save()
    }
}
