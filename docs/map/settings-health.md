# Map: Settings, Profile, HealthKit, Schema

Vitals, goal switching, onboarding goal pick, tab layout, units, HealthKit services and absent-data policy, schema migration.

> Rows describe current code. **Update the matching row in the same commit as the code it describes** — a stale row is worse than none. Index of all maps: [../../CLAUDE.md](../../CLAUDE.md) → "Find it fast".

## Goal rules in detail

The goal table is in [CLAUDE.md](../../CLAUDE.md). This is the rest of the goal section, moved verbatim.

Every new profile gets three starter movements (`Repos.createProfile` → `seedStarterMovements`): Lifted Baby (30 lb), Lifted Stroller (25 lb), Carried Baby (30 lb, duration). Changing goal (`Repos.updateGoal`) never seeds; existing profiles aren't backfilled. Their weights are editable (ⓘ sheet → `Repos.updateExercise`) and every logged row carries the load it was done at in `weightLb` — see "Edit a fixed load" in [workouts.md](workouts.md). `Seeder.seedAll` also runs `Repos.backfillFixedLoadWeightsOnce` (once, UserDefaults flag `backfill.fixedLoadWeights.v1`) next to `backfillHeartHealthTargets`. Isometric exercises: `isIsometric: true` on `ExerciseDTO`; hold saves `WorkoutSetModel{reps:1, holdSeconds:N}`; calorie: `CalorieEstimator.caloriesForIsometric`.

---

| Goal | File(s) |
|---|---|
| **Settings / Profile** | |
| Edit vitals | `Repos.updateVitals` + `Features/Settings/SettingsView.swift` → `EditVitalsSheet` |
| Switch goal | `Repos.updateGoal` (recomputes targets from current vitals via `Repos.recomputeTargets`; never seeds; logs untouched) + `Features/Settings/SettingsView.swift` → `GoalSwitchSheet` (previews old → new targets from `Targets.compute`) |
| Pick goal at onboarding | `Features/Onboarding/ProfileCreationView.swift` → "What's your goal?" (`FitnessGoal.allCases`, copy from `displayName` / `blurb`) → `Repos.createProfile(fitnessGoal:)` |
| App tab layout | `App/RootView.swift` — same for every goal: Today / Meals / Train / Progress. `WorkoutsView` is the same for everyone (live sessions · `ExercisesCard` · optional Pilates / Yoga / Stretching sections · suggestions). Today is a **read-only status board**: move (steps on top) · macro rings · today-vs-yesterday insights (`Domain/DayInsights.swift` → `Features/Today/DayInsightsCard.swift`; ≤3 rules-based observations with a next step, no claim off a day with no data; tests `DayInsightsTests`) · water, and a log list with no tap target. One surface per job — logging food happens on Meals, nowhere else |
| Profile avatar | `Components/ProfileAvatar.swift` |
| Units (metric ↔ imperial) | `Domain/Units.swift` — canonical storage IMPERIAL; convert only at UI boundary |
| Sync current weight | `Repos.syncCurrentWeight` — called after progress log, HK sync, TodayView task |
| **HealthKit** | |
| New HK metric | `Services/HealthKitService.swift` + `Data/PersistenceModels.swift` |
| Sync Health into logs | `HealthKitService.syncFromHealth` (deduped upsert; re-points `profile.weightLb`) |
| Fasting glucose from Health | `HealthKitService.latestFastingGlucoseMgDL` — only samples HealthKit marks pre-meal (`HKMetadataKeyBloodGlucoseMealTime` == `.preprandial`) become `.fastingGlucose`; post-meal and metadata-less samples are **dropped**, because a normal post-meal 150 filed as fasting trips `HealthRanges` ≥126 → high (ADA diabetes cut-point). Storing them needs a new non-fasting glucose `HealthMarkerKind` |
| Weekly Health totals | `HealthKitService.weekToDateBounds` → must use `Dates.startOfISOWeek` (Monday). Never `Calendar.current` week intervals — Sunday-first in the US locale, which desyncs the StepsCard week cells from every other weekly figure |
| Absent-data policy for HK sums | `sumOrNil` / `dailySums` return nil / omit the key so the UI can hide the stat; `dailySum` (single day) is the one place absent collapses to 0. Never fabricate a 0 for a day that simply never synced |
| **Schema / Data** | |
| Schema migration | `Data/Schema.swift` — current SchemaV7. Additive (new optional field / entity) = automatic. Structural = `.custom` stage. |
