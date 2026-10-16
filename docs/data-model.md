# Data model

> Moved from CLAUDE.md. Update in the same commit as any change to `Domain/Models.swift`, `Data/PersistenceModels.swift`, `Data/Schema.swift` or `Data/Repositories/`. Rows for schema migration live in [map/settings-health.md](map/settings-health.md).

## Persisted raw values (pinned to the retired mode names)

> Persisted raw values are pinned to the retired mode names: `.gain` = `"build"`, `.lose` = `"reset"`, stored in the legacy column `ProfileModel.modeRaw` (Swift property `ProfileDTO.fitnessGoal`); the watch wire field is still `mode`, and `ExerciseDTO.availableForMode` keeps its name. Bump a schema version before changing any of them. `_stashed/` = excluded from build target.

Append-only logs. Derived figures never stored. DTOs in `Domain/Models.swift`; `@Model` classes in `Data/PersistenceModels.swift` with `snapshot` adapters; CRUD in `Data/Repositories/Repositories.swift`. Writes return success (Bool or optional DTO); callers must check before showing success or dismissing. `RepositoryWrite` saves explicitly, rolls back failures and re-fetches affected models to restore retained UI values, and posts success/failure notifications. Profile creation, starter-movement seeding and the two built-in reminder groups share one commit boundary (`Repos.createProfile`).

`WorkoutSetDTO.weightLb` is the weight a row was done at: typed for per-set-weight lifts, and for fixed-load exercises (Lifted Baby…) the exercise's `loadLb` at log time (nil rows predate the stamping; `RepHistory` reads them as the exercise's load, and `Repos.backfillFixedLoadWeightsOnce` stamped them once). `Repos.updateExercise` edits a fixed load and stamps old nil-weight rows with the OLD load first, in the same transaction. Progress is derived on read from these rows by `Domain/RepHistory.swift`; nothing about it is stored, and no schema version changed. Non-schema local state this adds: UserDefaults `weeklyRepsNote.<profile uuid>` (weekly-reps toast gate) and `backfill.fixedLoadWeights.v1`.

Key entities: `ProfileDTO`, `ExerciseDTO` (`isIsometric`), `WorkoutSetDTO` (`holdSeconds?`), `FoodLogEntryDTO` (`ingredients?`), `BodyMetricDTO`, `HealthMarkerDTO`, `StepCountDTO`, `PilatesSessionDTO`, `WaterEntryDTO`, `ActivitySessionDTO`, `SavedMealTemplateDTO`, `ReminderGroupDTO`, `ReminderDTO`, `ReminderEventDTO`.

**`CardioSessionDTO` is legacy, read-only.** Nothing writes it any more (the card that did was unreachable and is gone); cardio is logged as an `ActivitySessionDTO` via `LogPastSessionSheet`. The read paths stay so installs that logged cardio in an older build still see and can delete those rows: `MoveCard` (burn + breakdown), `ProgressView` (Training history row + delete, energy balance), `DailyBurn.metEstimate`, `EnergyBalance.byDay`. Both paths exclude walks *and runs* so steps aren't double-counted. Note rows logged before the net-MET fix still carry their old gross `caloriesEst`. `Repos.logCardio` / `Repos.listCardio` were callerless and have been deleted — only `Repos.deleteCardioSession` remains. To write a cardio row again you'd construct `CardioSessionModel(snapshot:)` directly, but prefer `ActivitySessionDTO`.

**HealthKit crash traps (caused SIGABRT in build 37):**
- Authorization configuration errors have raised uncatchable `NSException` — call ONLY from an explicit phone Connect flow or watch Start-workout action. Never from `.task`/`.onAppear`.
- Phone `readTypes`/`writeTypes` contain quantity types; preserve the correlation-type crash guard (e.g. blood pressure). The watch also requests `HKObjectType.workoutType()` in its write set for `HKWorkoutSession` recording.

LDL/HDL/cholesterol/A1c not from Apple Health (lab-only) — manual entry. Blood glucose *is* readable from Health, but only pre-meal-marked samples may be written as `.fastingGlucose` (see the HealthKit rows above).
