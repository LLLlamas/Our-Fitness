// Repository helpers over ModelContext.
// UI uses these (or @Query) instead of writing raw SwiftData predicates everywhere.
// Keep mutation paths small and consistent.

import Foundation
import SwiftData

public enum Repos {

    // MARK: - Imperative fetches for non-@Query consumers
    //
    // Features/ reads through @Query (architectural rule 3), so `listProfiles`,
    // `listFoodLog` (Food log section) and `listSavedTemplates` (Saved meal
    // templates section) can look callerless. They are NOT: `WatchSyncService`
    // and `Seeder` call all three, and `OurFitnessPersistenceTests` compiles
    // Data/ (unlike the hostless OurFitnessTests, which only compiles Domain/).
    // A dead-code sweep deleted them on grep evidence from one branch alone and
    // would have broken the watch app at merge. Do not remove without grepping
    // every target that compiles Data/ — the watch sync path included.

    public static func listProfiles(_ ctx: ModelContext) -> [ProfileDTO] {
        let desc = FetchDescriptor<ProfileModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    // MARK: - Profiles

    @discardableResult
    public static func setHealthGranted(_ ctx: ModelContext, profileId: UUID, granted: Bool) -> Bool {
        RepositoryWrite.perform(ctx) {
            let target = profileId
            let desc = FetchDescriptor<ProfileModel>(predicate: #Predicate { $0.id == target })
            if let existing = try ctx.fetch(desc).first {
                existing.healthGranted = granted
                existing.updatedAt = Date()
            }
        }
    }

    /// Create a brand-new profile. Computes MacroTargets from the supplied
    /// vitals so callers don't need to thread Targets.compute themselves.
    @discardableResult
    public static func createProfile(
        _ ctx: ModelContext,
        name: String,
        fitnessGoal: FitnessGoal,
        sex: Sex,
        heightIn: Double,
        weightLb: Double,
        age: Int,
        activity: ActivityLevel,
        healthGranted: Bool = false
    ) -> ProfileDTO? {
        let vitals = Targets.ProfileVitals(
            sex: sex, weightLb: weightLb, heightIn: heightIn, age: age, activity: activity
        )
        let dto = ProfileDTO(
            name: name, fitnessGoal: fitnessGoal, sex: sex,
            heightIn: heightIn, weightLb: weightLb, age: age, activity: activity,
            computedTargets: Targets.compute(fitnessGoal: fitnessGoal, vitals: vitals),
            healthGranted: healthGranted
        )
        let saved = RepositoryWrite.perform(ctx) {
            ctx.insert(ProfileModel(snapshot: dto))
            try seedStarterMovements(ctx, profileId: dto.id)
        }
        return saved ? dto : nil
    }

    /// Seeds the three parenting movements every new profile starts with,
    /// whatever its goal. Idempotent: skips any exercise already present for the
    /// profile with a matching name. Called only from `createProfile` — changing
    /// goal never seeds, and existing profiles are not backfilled.
    private static func seedStarterMovements(_ ctx: ModelContext, profileId: UUID) throws {
        let descriptor = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.profileId == profileId })
        let existing = Set(try ctx.fetch(descriptor).map(\.name))
        let seeds: [(name: String, loadLb: Double, kind: ExerciseKind, muscles: [String])] = [
            ("Lifted Baby",     30, .reps,     ["biceps", "core", "upper back", "glutes"]),
            ("Lifted Stroller", 25, .reps,     ["shoulders", "arms", "core"]),
            ("Carried Baby",    30, .duration, ["core", "lower back", "posture stabilisers"]),
        ]
        for s in seeds where !existing.contains(s.name) {
            let dto = ExerciseDTO(
                id: "ex-\(profileId.uuidString.prefix(8))-\(UUID().uuidString.prefix(8))",
                name: s.name, category: .bodyweight, muscleGroups: s.muscles,
                equipment: [.bodyweight], defaultRepRange: [8, 12],
                availableForMode: [.gain, .lose], profileId: profileId,
                loadLb: s.loadLb, kind: s.kind, isIsometric: false)
            ctx.insert(ExerciseModel(snapshot: dto))
        }
    }

    /// Update mutable vitals on a profile and recompute its macro/step targets
    /// from the new values. Pass only the fields that changed; the rest are kept.
    /// This is the single write path that keeps `profile.weightLb` (and the other
    /// vitals) current, so every recommendation surface that reads them — calorie
    /// targets, protein, water goal, step/rep/isometric calorie burn — tracks the
    /// user's actual current numbers instead of the onboarding snapshot.
    /// Returns the updated DTO, or nil if the profile no longer exists.
    @discardableResult
    public static func updateVitals(
        _ ctx: ModelContext,
        profileId: UUID,
        weightLb: Double? = nil,
        heightIn: Double? = nil,
        age: Int? = nil,
        sex: Sex? = nil,
        activity: ActivityLevel? = nil
    ) -> ProfileDTO? {
        var updatedProfile: ProfileDTO?
        let saved = RepositoryWrite.perform(ctx) {
            let target = profileId
            let desc = FetchDescriptor<ProfileModel>(predicate: #Predicate { $0.id == target })
            guard let model = try ctx.fetch(desc).first else { throw RepositoryWriteError.missingRecord }

            if let v = weightLb { model.weightLb = v }
            if let v = heightIn { model.heightIn = v }
            if let v = age      { model.age = v }
            if let v = sex      { model.sexRaw = v.rawValue }
            if let v = activity { model.activityRaw = v.rawValue }

            try recomputeTargets(model)
            updatedProfile = model.snapshot
        }
        return saved ? updatedProfile : nil
    }

    /// Re-point `profile.weightLb` at the user's latest known body weight,
    /// recomputing targets. Call after a weight is logged (Progress tab) or synced
    /// from Apple Health so the profile — the single source recommendations read —
    /// reflects current weight.
    ///
    /// Pass `weightLb` when the caller already holds the authoritative latest value
    /// (e.g. the freshest Apple Health sample, which aggregates app-logged weights
    /// too — see `ProgressView` writing back via `writeWeightLb`). Omit it to derive
    /// the value from the most recent logged `BodyMetric` row instead.
    ///
    /// No-op when no weight is known or it already matches (0.1 lb tolerance avoids a
    /// needless recompute on float noise). Returns the updated DTO, or nil if nothing changed.
    @discardableResult
    public static func syncCurrentWeight(
        _ ctx: ModelContext, profileId: UUID, weightLb: Double? = nil
    ) -> ProfileDTO? {
        // `listBody` sorts by the `YYYY-MM-DD` date string ascending, so `.last`
        // (the last non-nil weight) is the most recent logged reading.
        guard let latest = weightLb ?? listBody(ctx, userId: profileId).compactMap(\.weightLb).last
        else { return nil }
        let target = profileId
        let desc = FetchDescriptor<ProfileModel>(predicate: #Predicate { $0.id == target })
        guard let model = try? ctx.fetch(desc).first else { return nil }
        guard abs(model.weightLb - latest) >= 0.1 else { return nil }
        return updateVitals(ctx, profileId: profileId, weightLb: latest)
    }

    /// Switch a profile's fitness goal at will. Recomputes macro/step targets
    /// from the profile's existing vitals (logs are goal-agnostic and untouched).
    /// Never seeds anything. Returns the updated DTO, or nil if the profile no
    /// longer exists or the save failed.
    @discardableResult
    public static func updateGoal(_ ctx: ModelContext, profileId: UUID, to newGoal: FitnessGoal) -> ProfileDTO? {
        var updatedProfile: ProfileDTO?
        let saved = RepositoryWrite.perform(ctx) {
            let target = profileId
            let desc = FetchDescriptor<ProfileModel>(predicate: #Predicate { $0.id == target })
            guard let model = try ctx.fetch(desc).first else { throw RepositoryWriteError.missingRecord }

            let current = model.snapshot
            guard current.fitnessGoal != newGoal else { updatedProfile = current; return }

            model.modeRaw = newGoal.rawValue   // legacy column name; stores the goal
            try recomputeTargets(model)
            updatedProfile = model.snapshot
        }
        return saved ? updatedProfile : nil
    }

    /// The one target-recompute path: re-derives `targetsJSON` from the model's
    /// current goal + vitals and stamps `updatedAt`. Shared by `updateVitals`,
    /// `updateGoal` and `Seeder`'s heart-health backstop. Call inside a
    /// `RepositoryWrite.perform` block — it does not save.
    static func recomputeTargets(_ model: ProfileModel) throws {
        let profile = model.snapshot
        model.targetsJSON = try JSONEncoder().encode(
            Targets.compute(fitnessGoal: profile.fitnessGoal, vitals: profile.vitals)
        )
        model.updatedAt = Date()
    }

    /// Launch backstop (called by `Seeder.seedAll`): heart-health micros became
    /// universal, but targets are stored, so a profile last computed under the
    /// old gain-goal rules still has nil fiber/sodium/added-sugar/sat-fat on disk.
    /// Recomputes exactly those profiles through `recomputeTargets`; idempotent —
    /// once recomputed, the micros are present and the profile is skipped.
    @discardableResult
    static func backfillHeartHealthTargets(_ ctx: ModelContext) -> Bool {
        RepositoryWrite.perform(ctx) {
            for model in try ctx.fetch(FetchDescriptor<ProfileModel>()) {
                let t = model.snapshot.computedTargets
                guard t.fiberGMin == nil || t.sodiumMgMax == nil
                        || t.addedSugarGMax == nil || t.saturatedFatGMax == nil else { continue }
                try recomputeTargets(model)
            }
        }
    }

    // MARK: - Exercises

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
        tracksWeight: Bool,
        loadLb: Double? = nil,
        kind: ExerciseKind = .reps,
        muscleGroups: [String] = [],
        isIsometric: Bool = false
    ) -> ExerciseDTO? {
        let dto = ExerciseDTO(
            id: "ex-\(profileId.uuidString.prefix(8))-\(UUID().uuidString.prefix(8))",
            name: name,
            category: tracksWeight ? .compound : .bodyweight,
            muscleGroups: muscleGroups,
            equipment: tracksWeight ? [.dumbbell] : [.bodyweight],
            defaultRepRange: [defaultRepsBottom, defaultRepsTop],
            availableForMode: [.gain, .lose],
            profileId: profileId,
            loadLb: loadLb,
            kind: kind,
            isIsometric: isIsometric
        )
        ctx.insert(ExerciseModel(snapshot: dto))
        guard RepositoryWrite.perform(ctx) else { return nil }
        return dto
    }

    /// Largest fixed load `updateExercise` accepts. Not a medical limit — it
    /// exists so a fat-fingered 3000 is refused rather than stored.
    public static let maxFixedLoadLb: Double = 1000

    /// Edit an exercise's name and/or its fixed load (the baby grew). Pass only
    /// what changed. Returns false, writing nothing, when the exercise is gone, the
    /// name is blank after trimming, or `loadLb` is asked of an exercise that has
    /// no fixed load, or is not a finite number in (0, `maxFixedLoadLb`]. Passing
    /// neither is a successful no-op.
    ///
    /// **A new load applies only to rows logged afterwards.** Rows store the
    /// load they were done at (`weightLb`), but one that predates the stamping
    /// still has nil there and means "the exercise's load". So, in the SAME
    /// transaction and before the new value lands, every nil-weight non-hold row
    /// of this exercise is stamped with the OLD load — history is never re-read at
    /// the new weight, and a failed save rolls both back together.
    @discardableResult
    public static func updateExercise(
        _ ctx: ModelContext, id: String, name: String? = nil, loadLb newLoad: Double? = nil
    ) -> Bool {
        RepositoryWrite.perform(ctx) {
            let exDesc = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.id == id })
            guard let model = try ctx.fetch(exDesc).first else { throw RepositoryWriteError.missingRecord }

            // Validate everything before touching anything.
            var trimmedName: String?
            if let name {
                let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { throw ExerciseEditError.invalid }
                trimmedName = t
            }
            if let newLoad {
                guard model.loadLb != nil, newLoad.isFinite, newLoad > 0, newLoad <= maxFixedLoadLb
                else { throw ExerciseEditError.invalid }
            }

            if let oldLoad = model.loadLb, let newLoad, newLoad != oldLoad {
                try stampUnweightedRows(ctx, exerciseId: id, loadLb: oldLoad)
                model.loadLb = newLoad
            }
            if let trimmedName, trimmedName != model.name { model.name = trimmedName }
        }
    }

    private enum ExerciseEditError: Error { case invalid }

    /// Stamps `loadLb` onto every non-hold row of the exercise that has no weight
    /// yet. Call inside a `RepositoryWrite.perform` block — it does not save.
    private static func stampUnweightedRows(_ ctx: ModelContext, exerciseId: String, loadLb: Double) throws {
        let setDesc = FetchDescriptor<WorkoutSetModel>(predicate: #Predicate { $0.exerciseId == exerciseId })
        for row in try ctx.fetch(setDesc) where row.weightLb == nil && row.holdSeconds == nil {
            row.weightLb = loadLb
        }
    }

    /// One-time launch backfill (called by `Seeder.seedAll`, behind a version
    /// flag): stamps every non-hold, nil-weight row of every fixed-load exercise
    /// with that exercise's current `loadLb`. Correct because, until
    /// `updateExercise`, a load could not change. Idempotent on its own (a stamped
    /// row is skipped), but the Seeder flag is what stops it ever running again
    /// after a load has been edited. Rows of exercises with no `loadLb`, and holds,
    /// are never touched.
    @discardableResult
    static func backfillFixedLoadWeights(_ ctx: ModelContext) -> Bool {
        RepositoryWrite.perform(ctx) {
            for exercise in try ctx.fetch(FetchDescriptor<ExerciseModel>()) {
                guard let load = exercise.loadLb else { continue }
                try stampUnweightedRows(ctx, exerciseId: exercise.id, loadLb: load)
            }
        }
    }

    /// UserDefaults flag for `backfillFixedLoadWeightsOnce`. Bump the suffix only
    /// to deliberately re-run a corrected backfill.
    static let fixedLoadBackfillKey = "backfill.fixedLoadWeights.v1"

    /// What `Seeder.seedAll` calls. Runs `backfillFixedLoadWeights` once per
    /// install: until `updateExercise` a load could not change, so stamping nil
    /// rows with the current load was right then and is wrong afterwards. The flag
    /// is what guarantees it never re-stamps anything at an edited load. Not set
    /// when the save fails, so the next launch retries.
    @discardableResult
    static func backfillFixedLoadWeightsOnce(_ ctx: ModelContext, defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: fixedLoadBackfillKey) else { return true }
        guard backfillFixedLoadWeights(ctx) else { return false }
        defaults.set(true, forKey: fixedLoadBackfillKey)
        return true
    }

    /// Deletes an exercise and cascade-deletes every set logged against it, so
    /// no orphaned WorkoutSetModel rows linger (they reference exerciseId by string).
    @discardableResult
    public static func deleteExercise(_ ctx: ModelContext, id: String) -> Bool {
        RepositoryWrite.perform(ctx) {
            // Delete the sets first so we never risk leaving orphans if the save
            // boundary moves (e.g. autosave) between the two deletes.
            let setDesc = FetchDescriptor<WorkoutSetModel>(predicate: #Predicate { $0.exerciseId == id })
            for s in try ctx.fetch(setDesc) {
                ctx.delete(s)
            }
            let exDesc = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.id == id })
            if let target = try ctx.fetch(exDesc).first {
                ctx.delete(target)
            }
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

    @discardableResult
    public static func addFoodLog(_ ctx: ModelContext, _ entry: FoodLogEntryDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(FoodLogEntryModel(snapshot: entry))
        }
    }

    @discardableResult
    public static func deleteFoodLog(_ ctx: ModelContext, id: UUID) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<FoodLogEntryModel>(predicate: #Predicate { $0.id == id })
            if let target = try ctx.fetch(desc).first {
                ctx.delete(target)
            }
        }
    }

    @discardableResult
    public static func updateFoodLog(_ ctx: ModelContext, _ entry: FoodLogEntryDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            let id = entry.id
            let descriptor = FetchDescriptor<FoodLogEntryModel>(
                predicate: #Predicate { $0.id == id }
            )
            guard let model = try ctx.fetch(descriptor).first else { throw RepositoryWriteError.missingRecord }
            model.slotRaw = entry.slot.rawValue
            model.customName = entry.customName
            model.servings = entry.servings
            model.perServingJSON = try JSONEncoder().encode(entry.perServing)
            model.ingredientsJSON = try entry.ingredients.map { try JSONEncoder().encode($0) }
        }
    }

    // MARK: - Saved meal templates

    @discardableResult
    public static func addSavedTemplate(_ ctx: ModelContext, _ template: SavedMealTemplateDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(SavedMealTemplateModel(snapshot: template))
        }
    }

    public static func listSavedTemplates(_ ctx: ModelContext, userId: UUID) -> [SavedMealTemplateDTO] {
        let descriptor = FetchDescriptor<SavedMealTemplateModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? ctx.fetch(descriptor))?.map(\.snapshot) ?? []
    }

    @discardableResult
    public static func deleteSavedTemplate(_ ctx: ModelContext, id: UUID) -> Bool {
        RepositoryWrite.perform(ctx) {
            let id = id
            let descriptor = FetchDescriptor<SavedMealTemplateModel>(
                predicate: #Predicate { $0.id == id }
            )
            if let model = try ctx.fetch(descriptor).first {
                ctx.delete(model)
            }
        }
    }

    // MARK: - Workouts + sets

    @discardableResult
    public static func addSet(_ ctx: ModelContext, _ s: WorkoutSetDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(WorkoutSetModel(snapshot: s))
        }
    }

    public static func setHistory(_ ctx: ModelContext, userId: UUID, exerciseId: String, limit: Int = 50) -> [WorkoutSetDTO] {
        var desc = FetchDescriptor<WorkoutSetModel>(
            predicate: #Predicate { $0.userId == userId && $0.exerciseId == exerciseId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = limit
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    /// This week vs last week reps (and the one own-history note) from the profile's
    /// WHOLE set history, read fresh from the store so a set just written by
    /// `addSet` is already in it. Used by the once-a-week toast after a logged set.
    public static func weeklyReps(_ ctx: ModelContext, userId: UUID, now: Date = Date()) -> RepHistory.WeeklyReps {
        let desc = FetchDescriptor<WorkoutSetModel>(predicate: #Predicate { $0.userId == userId })
        let sets = (try? ctx.fetch(desc).map(\.snapshot)) ?? []
        return RepHistory.weeklyReps(sets: sets, exercises: exercises(ctx, forProfile: userId), now: now)
    }

    @discardableResult
    public static func deleteSet(_ ctx: ModelContext, id: UUID) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<WorkoutSetModel>(predicate: #Predicate { $0.id == id })
            if let target = try ctx.fetch(desc).first {
                ctx.delete(target)
            }
        }
    }

    /// Correct a logged set after the fact — a mistyped weight, an over-counted
    /// rep, a hold that ran short. The counterpart to `deleteSet`: before this
    /// existed, 135 lb fat-fingered as 1350 could only be deleted and re-logged.
    ///
    /// **Recomputes `caloriesEst`.** That figure is a MET estimate frozen at log
    /// time, so leaving it alone after a reps/weight/hold change would leave a
    /// number the set no longer supports — the same reason
    /// `updateActivitySession` recomputes from its stored MET. A set row stores
    /// no MET, so the estimate is re-derived by `setCaloriesEstimate` below.
    ///
    /// Callers pass the complete new shape (reps, weight, hold); `reps` is
    /// clamped to at least 1, and for an isometric row it stays the hold count
    /// (pass the existing value — only `holdSeconds` is the user's edit there).
    /// `timestamp` is deliberately untouched: this corrects what was logged, not
    /// when. Returns false (nothing written) if the set or its exercise is gone.
    @discardableResult
    public static func updateSet(
        _ ctx: ModelContext,
        id: UUID,
        reps: Int,
        weightLb: Double?,
        holdSeconds: Int? = nil,
        bodyWeightLb: Double
    ) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<WorkoutSetModel>(predicate: #Predicate { $0.id == id })
            guard let target = try ctx.fetch(desc).first else { throw RepositoryWriteError.missingRecord }
            let exId = target.exerciseId
            let exDesc = FetchDescriptor<ExerciseModel>(predicate: #Predicate { $0.id == exId })
            guard let exercise = try ctx.fetch(exDesc).first?.snapshot else {
                throw RepositoryWriteError.missingRecord
            }

            let newReps = max(1, reps)
            let newHold = holdSeconds.map { max(1, $0) }
            // A fixed-load row keeps the load it was done at: the edit's weight
            // if it gave one, else the row's stamped weight, else (a row from
            // before stamping) the exercise's load. Priced at THAT load, never
            // the exercise's current one — the baby may have grown since.
            let rowLoad = exercise.fixedLoadLb(forRowWeight: weightLb ?? target.weightLb, holdSeconds: newHold)
            target.reps = newReps
            target.weightLb = rowLoad ?? weightLb
            target.holdSeconds = newHold
            target.caloriesEst = setCaloriesEstimate(
                exercise: exercise,
                reps: newReps, holdSeconds: newHold,
                bodyWeightLb: bodyWeightLb,
                loadLb: rowLoad
            )
        }
    }

    /// The log-time calorie math, re-derived for an edited set.
    ///
    /// Public so the edit sheet can preview the exact figure the save will store
    /// instead of keeping a second copy of the math — one definition, no drift
    /// between what the user is shown and what is written. Delegates to
    /// `CalorieEstimator.caloriesForSet`, which every logging surface also uses,
    /// so an edit lands on the number the original log would have produced.
    ///
    /// `loadLb` is the load the row was done at, for a fixed-load exercise whose
    /// current load may have changed since (see `updateSet`); nil = the exercise's.
    public static func setCaloriesEstimate(
        exercise: ExerciseDTO, reps: Int, holdSeconds: Int?, bodyWeightLb: Double,
        loadLb: Double? = nil
    ) -> Double {
        CalorieEstimator.caloriesForSet(
            exercise: exercise, reps: reps, holdSeconds: holdSeconds,
            bodyWeightLb: bodyWeightLb, loadLb: loadLb
        )
    }

    // MARK: - Water

    @discardableResult
    public static func addWater(_ ctx: ModelContext, _ w: WaterEntryDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(WaterEntryModel(snapshot: w))
        }
    }

    @discardableResult
    public static func deleteWater(_ ctx: ModelContext, id: UUID) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<WaterEntryModel>(predicate: #Predicate { $0.id == id })
            if let target = try ctx.fetch(desc).first {
                ctx.delete(target)
            }
        }
    }

    // MARK: - Body + markers

    public static func listBody(_ ctx: ModelContext, userId: UUID) -> [BodyMetricDTO] {
        let desc = FetchDescriptor<BodyMetricModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    @discardableResult
    public static func addBody(_ ctx: ModelContext, _ b: BodyMetricDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(BodyMetricModel(snapshot: b))
        }
    }

    /// Merge fields into the single body-metric row for (userId, day), creating it
    /// if absent. Only fills fields that are currently nil, so it never clobbers a
    /// value the user (or an earlier sync) already recorded. Used by Health sync to
    /// keep one row per day instead of inserting a row per metric.
    @discardableResult
    public static func upsertBodyMetric(
        _ ctx: ModelContext, userId: UUID, day: String,
        weightLb: Double? = nil, bodyFatPct: Double? = nil, waistIn: Double? = nil
    ) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<BodyMetricModel>(
                predicate: #Predicate { $0.userId == userId && $0.date == day }
            )
            if let model = try ctx.fetch(desc).first {
                if let v = weightLb,   model.weightLb == nil   { model.weightLb = v }
                if let v = bodyFatPct, model.bodyFatPct == nil { model.bodyFatPct = v }
                if let v = waistIn,    model.waistIn == nil     { model.waistIn = v }
            } else {
                ctx.insert(BodyMetricModel(snapshot: BodyMetricDTO(
                    userId: userId, date: day,
                    weightLb: weightLb, bodyFatPct: bodyFatPct, waistIn: waistIn
                )))
            }
        }
    }

    public static func listMarkers(_ ctx: ModelContext, userId: UUID) -> [HealthMarkerDTO] {
        let desc = FetchDescriptor<HealthMarkerModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    @discardableResult
    public static func addMarker(_ ctx: ModelContext, _ m: HealthMarkerDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(HealthMarkerModel(snapshot: m))
        }
    }

    // MARK: - Pilates sessions

    @discardableResult
    public static func logPilatesSession(_ ctx: ModelContext, _ s: PilatesSessionDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(PilatesSessionModel(snapshot: s))
        }
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

    /// Correct a logged Pilates session (duration, focus areas, notes). Unlike a
    /// set or an activity session there is no stored calorie figure to refresh:
    /// `PilatesSessionDTO` keeps only the duration and every surface derives the
    /// burn from it through `CalorieEstimator.caloriesForPilates`, so the
    /// estimate follows the new duration on its own.
    @discardableResult
    public static func updatePilatesSession(_ ctx: ModelContext, _ s: PilatesSessionDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            let id = s.id
            let desc = FetchDescriptor<PilatesSessionModel>(predicate: #Predicate { $0.id == id })
            guard let model = try ctx.fetch(desc).first else { throw RepositoryWriteError.missingRecord }
            model.apply(s)
        }
    }

    @discardableResult
    public static func deletePilatesSession(_ ctx: ModelContext, id: UUID) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<PilatesSessionModel>(predicate: #Predicate { $0.id == id })
            if let target = try ctx.fetch(desc).first {
                ctx.delete(target)
            }
        }
    }

    // MARK: - Cardio sessions (legacy, read-only — delete is the only write)

    @discardableResult
    public static func deleteCardioSession(_ ctx: ModelContext, id: UUID) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<CardioSessionModel>(predicate: #Predicate { $0.id == id })
            if let target = try ctx.fetch(desc).first {
                ctx.delete(target)
            }
        }
    }

    // MARK: - Live activity sessions

    @discardableResult
    public static func logActivitySession(_ ctx: ModelContext, _ s: ActivitySessionDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(ActivitySessionModel(snapshot: s))
        }
    }

    @discardableResult
    public static func deleteActivitySession(_ ctx: ModelContext, id: UUID) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<ActivitySessionModel>(predicate: #Predicate { $0.id == id })
            if let target = try ctx.fetch(desc).first {
                ctx.delete(target)
            }
        }
    }

    /// Correct a logged session's duration after the fact (e.g. the user forgot to
    /// start the timer). Recomputes the calorie estimate from the session's original
    /// MET and the profile's current weight — the same deterministic
    /// `MET × bodyWeightLb × hours` math used at log time. Leaves `met`, `date`, and
    /// `expectedMinutes` untouched.
    @discardableResult
    public static func updateActivitySession(
        _ ctx: ModelContext, id: UUID, durationMinutes: Int, bodyWeightLb: Double
    ) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<ActivitySessionModel>(predicate: #Predicate { $0.id == id })
            guard let target = try ctx.fetch(desc).first else { throw RepositoryWriteError.missingRecord }
            let mins = max(1, durationMinutes)
            target.durationMinutes = mins
            target.caloriesEst = CalorieEstimator.caloriesForActivity(
                met: target.met, minutes: Double(mins), bodyWeightLb: bodyWeightLb
            )
        }
    }

    // MARK: - Steps

    /// UPSERT by (userId, date). Used by both manual entry and HealthKit sync.
    @discardableResult
    public static func setSteps(_ ctx: ModelContext, userId: UUID, date: String, steps: Int, source: StepSource) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<StepCountModel>(
                predicate: #Predicate { $0.userId == userId && $0.date == date }
            )
            if let existing = try ctx.fetch(desc).first {
                existing.steps = steps
                existing.sourceRaw = source.rawValue
                existing.updatedAt = Date()
            } else {
                ctx.insert(StepCountModel(snapshot: StepCountDTO(
                    userId: userId, date: date, steps: steps, source: source
                )))
            }
        }
    }
}
