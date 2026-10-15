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
            if fitnessGoal == .lose { try seedCircuitExercises(ctx, profileId: dto.id) }
            ctx.insert(ReminderGroupModel(snapshot: ReminderGroupDTO(
                userId: dto.id, name: "Plants", sfSymbol: "leaf.fill", kind: .plants)))
            ctx.insert(ReminderGroupModel(snapshot: ReminderGroupDTO(
                userId: dto.id, name: "Medication", sfSymbol: "pills.fill", kind: .medication)))
        }
        return saved ? dto : nil
    }

    /// Seeds the three parenting-flavored exercises Circuit mode is built
    /// around. Idempotent: skips any exercise already present for the profile
    /// with a matching name.
    private static func seedCircuitExercises(_ ctx: ModelContext, profileId: UUID) throws {
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

            let updated = model.snapshot
            model.targetsJSON = try JSONEncoder().encode(
                Targets.compute(fitnessGoal: updated.fitnessGoal, vitals: updated.vitals)
            )
            model.updatedAt = Date()
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

    /// Switch a profile's mode at will. Recomputes macro/step targets from the
    /// profile's existing vitals (logs are mode-agnostic and untouched) and, when
    /// switching to Circuit, seeds the parenting exercises (idempotent). Returns
    /// the updated DTO, or nil if the profile no longer exists.
    @discardableResult
    public static func updateMode(_ ctx: ModelContext, profileId: UUID, to newMode: FitnessGoal) -> ProfileDTO? {
        var updatedProfile: ProfileDTO?
        let saved = RepositoryWrite.perform(ctx) {
            let target = profileId
            let desc = FetchDescriptor<ProfileModel>(predicate: #Predicate { $0.id == target })
            guard let model = try ctx.fetch(desc).first else { throw RepositoryWriteError.missingRecord }

            let current = model.snapshot
            guard current.fitnessGoal != newMode else { updatedProfile = current; return }

            model.modeRaw = newMode.rawValue
            model.targetsJSON = try JSONEncoder().encode(Targets.compute(fitnessGoal: newMode, vitals: current.vitals))
            model.updatedAt = Date()

            if newMode == .lose {
                try seedCircuitExercises(ctx, profileId: profileId)
            }
            updatedProfile = model.snapshot
        }
        return saved ? updatedProfile : nil
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
    /// no MET, so the estimate is re-derived by `recomputedSetCalories` below.
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
        bodyWeightLb: Double,
        fitnessGoal: FitnessGoal
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
            target.reps = newReps
            target.weightLb = weightLb
            target.holdSeconds = newHold
            target.caloriesEst = setCaloriesEstimate(
                exercise: exercise, fitnessGoal: fitnessGoal,
                reps: newReps, holdSeconds: newHold,
                bodyWeightLb: bodyWeightLb
            )
        }
    }

    /// The log-time calorie math, re-derived for an edited set.
    ///
    /// Public so the edit sheet can preview the exact figure the save will store
    /// instead of keeping a second copy of the branching below — one definition,
    /// no drift between what the user is shown and what is written.
    ///
    /// A set row stores no MET, so which estimator produced its `caloriesEst`
    /// has to be inferred from the same facts the three logging surfaces branch
    /// on. Keep these branches in step with them — an edit must land on the
    /// number the original log would have produced:
    ///   • `holdSeconds` set → isometric hold, exercise MET
    ///     (`RepCounter.swift` → `IsometricTimerView.completeHold`)
    ///   • Circuit → the flat, load-aware quick-log estimate; `reps` carries
    ///     minutes for a `.duration` movement and reps otherwise
    ///     (`Circuit/BabyExercisesCard.swift` → `logActivity`)
    ///   • Build → the exercise's researched MET and tempo
    ///     (`RepCounter.swift` → `RepCounterView.saveSet`)
    ///
    /// All four estimators are activity-only (MET − 1); never hand-roll the
    /// product here.
    public static func setCaloriesEstimate(
        exercise: ExerciseDTO, fitnessGoal: FitnessGoal, reps: Int, holdSeconds: Int?, bodyWeightLb: Double
    ) -> Double {
        if let seconds = holdSeconds {
            return CalorieEstimator.caloriesForIsometric(
                seconds: Double(seconds),
                met: ExerciseInfo.meta(for: exercise).met,
                bodyWeightLb: bodyWeightLb
            )
        }
        guard fitnessGoal == .lose else {
            return CalorieEstimator.caloriesForReps(
                reps: reps, exercise: exercise, bodyWeightLb: bodyWeightLb
            )
        }
        if exercise.kind == .duration {
            return CalorieEstimator.caloriesForDuration(
                minutes: Double(reps), loadLb: exercise.loadLb, bodyWeightLb: bodyWeightLb
            )
        }
        return CalorieEstimator.caloriesForReps(
            reps: reps, loadLb: exercise.loadLb, bodyWeightLb: bodyWeightLb
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

    // MARK: - Cardio sessions

    @discardableResult
    public static func logCardio(_ ctx: ModelContext, _ s: CardioSessionDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(CardioSessionModel(snapshot: s))
        }
    }

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

    // MARK: - Reminder groups

    public static func listReminderGroups(_ ctx: ModelContext, userId: UUID) -> [ReminderGroupDTO] {
        let desc = FetchDescriptor<ReminderGroupModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    @discardableResult
    public static func addReminderGroup(_ ctx: ModelContext, _ g: ReminderGroupDTO) -> ReminderGroupDTO? {
        ctx.insert(ReminderGroupModel(snapshot: g))
        guard RepositoryWrite.perform(ctx) else { return nil }
        return g
    }

    /// Deletes a custom group and cascades every reminder in it (which itself
    /// cascades that reminder's events). Only `.custom` groups are deletable —
    /// both built-ins ("Plants" and "Medication") are refused, since
    /// `ensure…Group` would just recreate them on the next launch. Returns the
    /// deleted reminder ids so the caller can also cancel their pending
    /// notifications (this layer stays notification-free — see
    /// ReminderNotificationService).
    @discardableResult
    public static func deleteReminderGroup(_ ctx: ModelContext, id: UUID) -> [UUID] {
        var deletedIds: [UUID] = []
        let saved = RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<ReminderGroupModel>(predicate: #Predicate { $0.id == id })
            guard let group = try ctx.fetch(desc).first,
                  group.kindRaw == ReminderGroupKind.custom.rawValue else { return }
            let reminders = try ctx.fetch(FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.groupId == id }))
            for reminder in reminders {
                let reminderId = reminder.id
                for event in try ctx.fetch(FetchDescriptor<ReminderEventModel>(predicate: #Predicate { $0.reminderId == reminderId })) {
                    ctx.delete(event)
                }
                deletedIds.append(reminderId)
                ctx.delete(reminder)
            }
            ctx.delete(group)
        }
        return saved ? deletedIds : []
    }

    /// Idempotently ensures a profile has the built-in Plants group. Called
    /// from `createProfile` (new profiles) and `Seeder.seedAll` (profiles that
    /// existed before this feature shipped).
    @discardableResult
    public static func ensurePlantsGroup(_ ctx: ModelContext, userId: UUID) -> ReminderGroupDTO? {
        if let existing = listReminderGroups(ctx, userId: userId).first(where: { $0.kind == .plants }) {
            return existing
        }
        return addReminderGroup(ctx, ReminderGroupDTO(userId: userId, name: "Plants", sfSymbol: "leaf.fill", kind: .plants))
    }

    /// Idempotently ensures a profile has the built-in Medication group. Same
    /// shape and call sites as `ensurePlantsGroup` — `createProfile` for new
    /// profiles, `Seeder.seedAll` for ones that predate the feature.
    @discardableResult
    public static func ensureMedicationGroup(_ ctx: ModelContext, userId: UUID) -> ReminderGroupDTO? {
        if let existing = listReminderGroups(ctx, userId: userId).first(where: { $0.kind == .medication }) {
            return existing
        }
        return addReminderGroup(ctx, ReminderGroupDTO(userId: userId, name: "Medication", sfSymbol: "pills.fill", kind: .medication))
    }

    /// Single-group fetch for callers (e.g. notification scheduling) that only
    /// need one reminder's group, not the whole per-user list.
    public static func reminderGroup(_ ctx: ModelContext, id: UUID) -> ReminderGroupDTO? {
        let desc = FetchDescriptor<ReminderGroupModel>(predicate: #Predicate { $0.id == id })
        return (try? ctx.fetch(desc).first)?.snapshot
    }

    // MARK: - Reminders

    public static func listReminders(_ ctx: ModelContext, userId: UUID) -> [ReminderDTO] {
        let desc = FetchDescriptor<ReminderModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    public static func reminder(_ ctx: ModelContext, id: UUID) -> ReminderDTO? {
        let desc = FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.id == id })
        return (try? ctx.fetch(desc).first)?.snapshot
    }

    @discardableResult
    public static func addReminder(_ ctx: ModelContext, _ r: ReminderDTO,
                                   initialEvent: ReminderEventDTO? = nil) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(ReminderModel(snapshot: r))
            if let initialEvent { ctx.insert(ReminderEventModel(snapshot: initialEvent)) }
        }
    }

    @discardableResult
    public static func updateReminder(_ ctx: ModelContext, _ r: ReminderDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            let id = r.id
            let desc = FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.id == id })
            guard let model = try ctx.fetch(desc).first else { throw RepositoryWriteError.missingRecord }
            model.apply(r)
        }
    }

    /// Cascades: deletes the reminder's logged events. Does NOT cancel its
    /// pending notification — callers go through
    /// `ReminderNotificationService.cancel(ids:)` alongside this (keeps this
    /// layer free of UserNotifications).
    @discardableResult
    public static func deleteReminder(_ ctx: ModelContext, id: UUID) -> Bool {
        RepositoryWrite.perform(ctx) {
            let eventDesc = FetchDescriptor<ReminderEventModel>(predicate: #Predicate { $0.reminderId == id })
            for e in try ctx.fetch(eventDesc) {
                ctx.delete(e)
            }
            let desc = FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.id == id })
            if let target = try ctx.fetch(desc).first {
                ctx.delete(target)
            }
        }
    }

    // MARK: - Reminder events

    /// Logs a completion and clears any active snooze (a real watering
    /// supersedes a "check back later").
    @discardableResult
    public static func logReminderDone(_ ctx: ModelContext, _ e: ReminderEventDTO) -> Bool {
        RepositoryWrite.perform(ctx) {
            ctx.insert(ReminderEventModel(snapshot: e))
            let reminderId = e.reminderId
            let desc = FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.id == reminderId })
            if let target = try ctx.fetch(desc).first {
                target.snoozedUntil = nil
            }
        }
    }

    @discardableResult
    public static func deleteReminderEvent(_ ctx: ModelContext, id: UUID) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<ReminderEventModel>(predicate: #Predicate { $0.id == id })
            if let target = try ctx.fetch(desc).first {
                ctx.delete(target)
            }
        }
    }

    public static func reminderEvents(_ ctx: ModelContext, reminderId: UUID, limit: Int = 50) -> [ReminderEventDTO] {
        var desc = FetchDescriptor<ReminderEventModel>(
            predicate: #Predicate { $0.reminderId == reminderId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        desc.fetchLimit = limit
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    public static func lastReminderEvent(_ ctx: ModelContext, reminderId: UUID) -> ReminderEventDTO? {
        reminderEvents(ctx, reminderId: reminderId, limit: 1).first
    }

    /// All of a user's reminder events in one fetch (newest first), for
    /// callers that need "latest per reminder" across many reminders at once
    /// (e.g. WatchSyncService.pushSnapshot) — fold into a dictionary instead
    /// of calling `lastReminderEvent` per reminder.
    public static func listReminderEvents(_ ctx: ModelContext, userId: UUID) -> [ReminderEventDTO] {
        let desc = FetchDescriptor<ReminderEventModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? ctx.fetch(desc).map(\.snapshot)) ?? []
    }

    @discardableResult
    public static func snoozeReminder(_ ctx: ModelContext, id: UUID, until: Date) -> Bool {
        RepositoryWrite.perform(ctx) {
            let desc = FetchDescriptor<ReminderModel>(predicate: #Predicate { $0.id == id })
            if let target = try ctx.fetch(desc).first {
                target.snoozedUntil = until
            }
        }
    }
}
