# Our-Fitness — Foundation (iOS / SwiftUI)

Native iOS app targeting App Store release. One app for everyone; the profile's **fitness goal** — `FitnessGoal.gain` ("Build muscle") or `.lose` ("Lose weight") — only changes target numbers and soft tilts.

> Persisted raw values are pinned to the retired mode names: `.gain` = `"build"`, `.lose` = `"reset"`, stored in the legacy column `ProfileModel.modeRaw` (Swift property `ProfileDTO.fitnessGoal`); the watch wire field is still `mode`, and `ExerciseDTO.availableForMode` keeps its name. Bump a schema version before changing any of them. `_stashed/` = excluded from build target.
> One profile per install (`Components/ProfileAvatar.swift`). Phase 2/3 roadmap: [docs/app-expansion.md](docs/app-expansion.md).

---

## Goals

`Domain/Targets.swift` → `Targets.rules` (`GoalRules`) is the only per-goal number set:

| | `.gain` (Build muscle) | `.lose` (Lose weight) |
|---|---|---|
| Calories | TDEE + 500 | TDEE − 400 (floor 1,200 either way) |
| Protein g/lb | 1.0 | 1.1 |
| Fat % of calories | 27% | 28% |
| Default steps/day | 8,000 | 10,000 |

Every surface is identical for both goals. Beyond `GoalRules`, the goal only moves nudge thresholds (`EncouragementEngine.mealLoggingNudge` focus, `StallDetector` workout gap 5 vs 7 days, weight stall `.lose`-only) and soft ranking/copy tilts (`OnDeviceModel.goalLine(_:gain:lose:)` in the AI services, `ExerciseGoalMatcher`, `MealCravingMatcher`, `SuggestedMeals.goalTilt`). Heart-health micros apply to everyone: `Targets.HeartHealth` (fiber ≥ 35 g, sodium ≤ 1,500 mg, added sugar ≤ 25 g, sat fat ≤ 10% of calories) populate `MacroTargets.{fiberGMin,sodiumMgMax,addedSugarGMax,saturatedFatGMax}`, surfaced by `Components/HeartHealthCard.swift` in `NutritionView`; headroom via `Domain/MacroBudget.swift` → `RemainingMacros`. `Seeder` → `Repos.backfillHeartHealthTargets` recomputes stored targets that predate this (nil micros).

Every new profile gets three starter movements (`Repos.createProfile` → `seedStarterMovements`): Lifted Baby (30 lb), Lifted Stroller (25 lb), Carried Baby (30 lb, duration). Changing goal (`Repos.updateGoal`) never seeds; existing profiles aren't backfilled. Isometric exercises: `isIsometric: true` on `ExerciseDTO`; hold saves `WorkoutSetModel{reps:1, holdSeconds:N}`; calorie: `CalorieEstimator.caloriesForIsometric`.

---

## Codebase map

```
OurFitness/
  App/          ← @main, ModelContainer, root shell
  Domain/       ← PURE Swift. No SwiftUI/SwiftData. Hostless unit-test target.
  Data/         ← SwiftData @Model classes + Repositories/
  Services/     ← HealthKit, Theme (one light palette, `Theme.standard`), Haptics, ToastCenter, MealReminderService + AppNotificationDelegate (notifications), WatchSync
  Features/     ← Onboarding, Today, Nutrition, Workouts (Train tab — flat folder, no per-goal subfolders), Progress, Settings
                  Rule: a card lives in the folder of the TAB THAT RENDERS IT.
  Components/   ← ProgressBar, ProgressRing, Card, Banner, AnimatedNumber, TactileButtonStyle…
Shared/         ← Shared contracts: Foundation-only WatchSyncPayload; ActivityKit LiveSessionAttributes for app/widget
_stashed/       ← Outside build target; pending rework
OurFitnessTests/ ← Hostless XCTest for Domain/* and shared watch payload
OurFitnessPersistenceTests/ ← Separate hostless SwiftData/repository/session regression tests
OurFitnessWatch/ ← watchOS companion app — thin client; WatchConnectivity sync, no local SwiftData
project.yml     ← XcodeGen source of truth; .xcodeproj gitignored
```

---

## Hard architectural rules

1. `Domain/` never imports `SwiftData` or `SwiftUI`.
2. `Features/` uses repositories or `@Query` — never opens the container directly.
3. **Per-profile `@Query` must predicate-scope** (`#Predicate { $0.userId == uid }`) — never `.filter` client-side. See `TodayView`, `NutritionView`, `ProgressTabView`, `WorkoutsView`.
4. Phone HealthKit only through `Services/HealthKitService.swift`; watch workout sessions only through `OurFitnessWatch/WatchWorkoutSession.swift`. Authorization requires an explicit phone Connect or watch Start-workout action.
5. `.swift` filenames unique in target. All `@Model` classes in `Data/PersistenceModels.swift`.
6. `OurFitnessTests` is hostless: blank `TEST_HOST`/`BUNDLE_LOADER`, no `@testable import OurFitness`.
7. `Shared/WatchSyncPayload.swift` stays Foundation-only and compiles into phone, watch, and tests. `Shared/LiveSessionAttributes.swift` uses ActivityKit and compiles into phone and widget only. Neither contract imports SwiftUI/SwiftData/UIKit. The watch also compiles selected `Domain/` files directly, so keep their dependencies within that explicit source set.
   - Concretely: `CalorieEstimator.swift` is in the watch's source list and `Units.swift` is **not**, which is why `CalorieEstimator` keeps a file-local `kgPerLb` instead of using `Units.kgPerLb`. "Deduplicating" that constant breaks the watch build. Check `project.yml` → `OurFitnessWatch.sources` before pointing one watch-compiled file at another `Domain/` file.
8. **One surface per job.** Steps render in `StepsCard` only; food is logged in `AddFoodSheet` (Meals) only; day history is `MealHistoryList` only; cardio is logged in `LogPastSessionSheet` only. Before adding a card, sheet or row, find the existing one and extend it. Duplicate surfaces drift apart — the pair that triggered this rule showed the same step count against two different goal stores and two different burn formulas.
9. **Every `Repos` write returns success** (`Bool`, or an optional DTO) via `RepositoryWrite.perform`. Callers MUST `guard … else { return }` before dismissing a sheet, firing a toast, or celebrating. A write that silently failed while the UI said "Logged" is the bug this prevents.

---

## Where to touch

Rows are pointers only. Behaviour notes and invariants for a row: `grep -n -A6 "^### <row title>" docs/where-to-touch-notes.md` before editing that area.

| Goal | File(s) |
|---|---|
| **Workouts** | |
| Add exercise | `Data/Repositories/Repositories.swift` → `Repos.createExercise` |
| Add-exercise sheet | `Features/Workouts/WorkoutsView.swift` → `AddExerciseSheet` |
| Exercise ⓘ info sheet | `Features/Workouts/ExerciseInfoSheet.swift` → `ExerciseInfoSheet(exercise:profile:todayCount:todayKcal:)` |
| Isometric timer UI | `Features/Workouts/RepCounter.swift` → `IsometricTimerView` |
| Isometric calorie math | `Domain/CalorieEstimator.swift` → `caloriesForIsometric` |
| Rep counter | `Features/Workouts/RepCounter.swift` → `RepCounterView` |
| Edit / delete / back-fill a logged set | `SetHistorySheet(profile:exercise:dayKey:)` in `Features/Workouts/WorkoutsView.swift` |
| Per-set calories (log, edit, preview, watch) | `Domain/ExerciseCalories.swift` → `CalorieEstimator.caloriesForSet(exercise:reps:holdSeconds:bodyWeightLb:)` |
| Exercise shape (which controls a row gets) | `Domain/Models.swift` → `ExerciseDTO.tracksPerSetWeight` (reps, no `loadLb`, not isometric, compound/isolation → rep counter with weight field) / `isOneTapLoggable` (not isometric, not tracksPerSetWeight → inline +1, and the watch quick-log filter). |
| Log pilates | `Repos.logPilatesSession` + `Domain/Models.swift` (`PilatesSessionDTO`). |
| Optional Train sections (Pilates / Yoga / Stretching) | `Domain/TrainSections.swift` (`TrainSection` metadata + goal keys; `TrainSections.enabled/available/encode`; `countThisWeek` / `weeklyStreak`) + `Features/Workouts/ActivitySectionCard.swift` |
| Edit a logged session's duration | `EditDurationSheet` in `Features/Workouts/LiveSessionCard.swift` |
| Log cardio (run / bike / swim / row / hike) | `LogPastSessionSheet` in `Features/Workouts/LiveSessionCard.swift` |
| Exercise list (Train tab) | `Features/Workouts/ExercisesCard.swift` |
| Live sessions (timer) | `Features/Workouts/LiveSessionCard.swift` + `Domain/LiveSessionState.swift` + `Services/LiveSessionService.swift`. |
| Live Activity (Lock Screen) | `OurFitnessWidgets/LiveSessionLiveActivity.swift` + `Services/LiveSessionActivityController.swift` |
| Exercise MET / muscles | `Domain/ExerciseInfo.swift` → `namedMeta` (first-match order matters; specific before general) |
| Canonical exercise catalog | `Domain/ExerciseInfo.swift` → `catalog` (public, alphabetical, sourced from `namedMeta`) / `catalogEntry(named:)` |
| AI exercise insights | `Services/ExerciseInsightService.swift` (iOS 26+, graceful fallback; scaffolding from `OnDeviceModel`) |
| AI "what to work on?" suggestions | `Services/WorkoutSuggestionService.swift` + fallback `Domain/ExerciseGoalMatcher.swift` (goal→muscles→exercises, research reasons) |
| **Shared on-device-AI scaffolding** | `Services/OnDeviceModel.swift` |
| Recent sessions rule | Today/Train surfaces show today + yesterday only (the sets sheet opens on today, last 7 days one tap away); every older day lives in `TrainingHistorySheet`, reachable from both Train ("Training history" row under `ExercisesCard`) and Progress |
| Live-session activities | `Domain/ActivityCatalog.swift` |
| **Nutrition** | |
| Food parser (NL → macros) | `Domain/FoodParser.swift` → `matchFood` uses `CommonFoods.bestMatch` (first-token index, size-independent) then USDA `Domain/SQLiteFoodDatabase.swift`. |
| Add / update curated food | `Domain/CommonFoods.swift` (~1,200 foods; 16 category arrays + `expanded`) |
| Add food (search + describe + browse, one sheet) | `Features/Nutrition/AddFoodSheet.swift` |
| Restaurant / chain menus (search + browse) | Data: `scripts/restaurant-data/<slug>.json` |
| AI meal parser | `Services/MealParseService.swift` (iOS 26+; text-only model; numbers from DB; scaffolding from `OnDeviceModel`) |
| Camera food label scanner | `Features/Nutrition/CameraFoodLogSheet.swift` (iOS 17+ VisionKit, iOS 26+ AI). Scanner unavailable / unreadable label falls back to `DescribeMealForm` |
| AI food alternatives | `Services/FoodAlternativeService.swift` (iOS 26+; prefetch after every log; scaffolding + `foodAlternatives.v2.*` cache from `OnDeviceModel`) |
| AI "what are you in the mood for?" | `Services/MealIdeaService.swift` (iOS 26+; prompt puts the craving first, goal/history as tie-breaks; scaffolding from `OnDeviceModel`) + fallback `Domain/MealCravingMatcher.swift` |
| Meal log UI + day history + past-day logging | `Features/Nutrition/NutritionView.swift` |
| Ingredient-level editing / logging | `Features/Nutrition/MealIngredientDetailSheet.swift` |
| Meal suggestions (no standalone UI) | `Domain/SuggestedMeals.swift` → `all` (ONE pool for every user) + `ranked(...)` (goal tilt via `goalTilt`); the pool is consumed only by `MealCravingMatcher`; ideas UI is `MoodMealSheet` only (Suggestions sheet/"for you" row removed as redundant) |
| Personalised recs / most-logged foods | `Domain/FoodAffinity.swift` → `mostLoggedIds(_:days:limit:end:)` / `frequencyByFoodId(_:days:end:)` (30-day window over foodIds incl. ingredients); feeds `AddFoodSheet` ordering + `MealCravingMatcher` |
| Meal-logging streak (consecutive days) | `Domain/Streaks.swift` → `loggingStreak(...)`; copy `EncouragementEngine.mealStreakMessage(days:fitnessGoal:)` (3/7/14/30/60/100); toast `ToastCenter.mealStreak(...)`; chip in `NutritionView` |
| Heart-health micros (fiber floor + sodium/sugar/satfat caps) | `Components/HeartHealthCard.swift` (every profile; values from `Targets.HeartHealth`; no-op if targets have no caps) |
| Remaining macros / headroom under caps | `Domain/MacroBudget.swift` → `remaining(totals:targets:)` returns `RemainingMacros` (caps = room left, negative when over; fiber = signed distance to floor; all four nil only for targets stored before the micros became universal |
| Can a logged food supply sodium / added sugar / sat fat? | Only `Features/Nutrition/CameraFoodLogSheet.swift` (label scan → `PerServing` with all three). |
| Personal meal templates | `Domain/Models.swift` (`SavedMealTemplateDTO`) + `Data/PersistenceModels.swift` (`SavedMealTemplateModel`) |
| Weekly nutrition trend | `Domain/NutritionHistory.swift` + `Features/Nutrition/NutritionTrendSheet.swift` |
| Calorie / macro target math | `Domain/Targets.swift` only (intake side: BMR → TDEE → targets). Activity *burn* math is `Domain/CalorieEstimator.swift` |
| Target rationale copy | `Domain/TargetRationale.swift` (spell out acronyms; "cal" not "kcal"); heart-health micro copy `fiberWhy`/`sodiumWhy`/`addedSugarWhy`/`saturatedFatWhy(for:)` (used by `HeartHealthCard` info sheet) |
| **Today / Steps** | |
| Move card (steps + 2×3 cols) | `Features/Today/MoveCard.swift` |
| Steps card (Today only) | `Features/Today/StepsCard.swift` |
| Water tracker (presets + day-streak) | `Domain/Water.swift` (presets Sip 4 / S 8 / M 16 / L 32 oz; `total(_:on:)`, `streak(_:goalFlOz:end:)`) + `Features/Today/WaterCard.swift` (streak chip = shared `Components/StreakChip.swift`; the card header is the only "WATER" label |
| Log water (shared path — use for ANY new water surface) | `Features/Today/WaterLogging.swift` → `WaterLog.add(_:for:on:context:lastFlOz:unitSystem:toasts:)` |
| Water quick-log (app-wide FAB) | `Features/Today/WaterQuickLogButton.swift` |
| Step milestones / goals | `Domain/Movement.swift` (`defaultStepMilestones`). Per-profile override: `AppStorage "stepsGoal.\(profileId.uuidString)"` |
| Today burn estimate | `Domain/DailyBurn.swift` → `metEstimate` (day total) / `breakdown(...)` → `Breakdown` (per-source split: steps, sets, cardio, pilates, activities; `trainingKcal` excludes steps; `total` == `metEstimate`). Net of resting |
| Encouragement / milestones | `Domain/EncouragementEngine.swift` + `Domain/EncouragementMessage.swift` + `Components/ProjectionBar.swift` |
| Meal/water nudges | `Domain/EncouragementEngine.swift` → `mealLoggingNudge` / `waterNudge`; wired in `Features/Today/TodayView.swift` through `ToastCenter.mealNudge` / `waterReminder`, which compute the message once and return whether they showed (the hour guard advances only on `true`) |
| Meal-logging push reminders (learned timing) | `Domain/MealLogPattern.swift` + `Services/MealReminderService.swift`; notification delegate + one-time retired-reminder cleanup in `Services/AppNotificationDelegate.swift` |
| Watch companion sync | `Services/WatchSyncService.swift` + `Shared/WatchSyncPayload.swift` |
| Adding anything to the watch's data | `Shared/WatchSyncPayload.swift` → `WatchSnapshotEnvelope`. **ONE envelope under ONE context key |
| Wrist → phone mutations | `WatchAction` in `Shared/WatchSyncPayload.swift`, applied by `WatchSyncService.apply`. The watch sends an **id**; the phone re-resolves real macros/calories |
| Watch app (thin client, no local SwiftData) | `OurFitnessWatch/` |
| What may appear in the watch quick-log | `Services/WatchSyncService.swift` → `quickLogExercises` filters to exercises ONE TAP CAN RECORD CORRECTLY. `.logQuickSet` writes `weightLb: nil` and `reps:`, so compound/isolation lifts (per-set weight) and isometric exercises (a hold is `{reps:1, holdSeconds:N}`) are excluded |
| An empty watch screen must not claim empty phone data | Before the first sync the watch knows nothing, so every empty state branches on `store.hasSynced`: synced → "No movements yet / Add … on your phone", not synced → "Not synced yet / Open Our Fitness on your iPhone". `WatchTodayView`, `WatchQuickLogView`, `WatchMealsView` all do this |
| …nor present an OLD day's data as today's | `WatchTodayView.staleNotice` |
| Watch target extra sources | `project.yml` → `OurFitnessWatch.sources`: `Domain/LiveSessionState.swift`, `ActivityCatalog.swift`, `CalorieEstimator.swift`, `Shared/WatchSyncPayload.swift` (mirrors `OurFitnessTests` compiling `Domain/` directly). |
| On-wrist workout / heart rate | `OurFitnessWatch/WatchWorkoutSession.swift` |
| **Progress** | |
| Add health marker kind | `Domain/Models.swift` (`HealthMarkerKind`) + `Domain/HealthRanges.swift` (exhaustive switches) + `Features/Progress/ProgressView.swift` |
| Show/hide trackers | `Features/Progress/EditTrackersSheet.swift` |
| Stat detail sheet (chart + entries + log) | `Components/StatDetailSheet.swift` |
| Training volume | `Domain/TrainingHistory.swift` → `setsInWeek(_:weeksAgo:now:)` / `weeklySetCounts(_:weeks:now:)` (Monday ISO weeks), surfaced via `StatKind.trainingVolume` in `Features/Progress/ProgressView.swift`. |
| Strength progress (per-lift headline: est. max lb / most reps in a day / most minutes / longest hold sec — `Lift.metric`) | `Domain/StrengthProgress.swift` → `lifts(sets:exercises:now:)`; rendered by `strengthCard` in `Features/Progress/ProgressView.swift` |
| Weekly sets per muscle + "what to add" tips (target 10 sets/wk, no upper limit — sources in code comment) | `Domain/MuscleVolume.swift`; core, forearms, traps, lower back and hip flexors map to no group |
| Home equipment (max dumbbell lb, pull-up bar; no schema) | `Domain/HomeEquipment.swift`, AppStorage `equipment.<profileId>`; edited in `WorkoutGoalSheet`; filters `ExerciseGoalMatcher` / `WorkoutSuggestionService` |
| Tape measurements (frame size: waist, shoulders, chest, arm, thigh) | `StatKind` in `Features/Progress/ProgressView.swift` |
| Weeks ("this week") | `Domain/Dates.startOfISOWeek(_:weeksAgo:)` |
| Calorie intake vs activity burn | `Domain/EnergyBalance.swift` → `byDay(...)` / `averages(_:)` (intake = `DailyTotals`; burn = `DailyBurn.metEstimate` |
| Training history (cross-day) | `Domain/TrainingHistory.swift` → `sessions(sets:exercises:)` strength grouping + `Features/Workouts/TrainingHistorySheet.swift` for strength, live, cardio, and Pilates sessions |
| Tracker display order | alphabetical by `StatKind.title` at the two render sites (`visibleStats(in:)` + `EditTrackersSheet` ForEach); never reorder the enum (persisted CSV) |
| Latest value of a health marker | `Trends.markerSeries(_:kind:).last?.value` |
| BMI / body-fat thresholds | `Domain/BodyComposition.swift` → `bmiCategory` / `bodyFatCategory` own every boundary. |
| **Settings / Profile** | |
| Edit vitals | `Repos.updateVitals` + `Features/Settings/SettingsView.swift` → `EditVitalsSheet` |
| Switch goal | `Repos.updateGoal` (recomputes targets from current vitals via `Repos.recomputeTargets`; never seeds; logs untouched) + `Features/Settings/SettingsView.swift` → `GoalSwitchSheet` (previews old → new targets from `Targets.compute`) |
| Pick goal at onboarding | `Features/Onboarding/ProfileCreationView.swift` → "What's your goal?" (`FitnessGoal.allCases`, copy from `displayName` / `blurb`) → `Repos.createProfile(fitnessGoal:)` |
| App tab layout | `App/RootView.swift` |
| Profile avatar | `Components/ProfileAvatar.swift` |
| Units (metric ↔ imperial) | `Domain/Units.swift` |
| Sync current weight | `Repos.syncCurrentWeight` |
| **HealthKit** | |
| New HK metric | `Services/HealthKitService.swift` + `Data/PersistenceModels.swift` |
| Sync Health into logs | `HealthKitService.syncFromHealth` (deduped upsert; re-points `profile.weightLb`) |
| Fasting glucose from Health | `HealthKitService.latestFastingGlucoseMgDL` |
| Weekly Health totals | `HealthKitService.weekToDateBounds` → must use `Dates.startOfISOWeek` (Monday). Never `Calendar.current` week intervals |
| Absent-data policy for HK sums | `sumOrNil` / `dailySums` return nil / omit the key so the UI can hide the stat; `dailySum` (single day) is the one place absent collapses to 0. Never fabricate a 0 for a day that simply never synced |
| **UI / Components** | |
| Button variants (5 total) | `Components/TactileButtonStyle.swift` |
| Circular progress | `Components/ProgressRing.swift` |
| ⓘ info-sheet chrome | `Components/InfoSheet.swift` → `InfoSheetScaffold(title:subtitle:titleSize:dragIndicator:detents:)` (`detents` defaults to `[.medium, .large]`; pass `[.large]` for a sheet long enough that medium reads as truncated |
| Goal-picker wheel sheet | `Components/GoalPickerSheet.swift` → `GoalPickerSheet(title:subtitle:wheels:wheelVerticalPadding:resetLabel:detents:onReset:onSave:)`; `[Wheel]` so steps can show a second days/week wheel. |
| Progress-fill replay (sweep from 0 on appear) | `Components/VisibilityReveal.swift` → `.revealOnAppear($reveal)` |
| Haptics | `Services/Haptics.swift` |
| Toast | `Services/ToastCenter.swift` + `Components/ToastView.swift` |
| Scroll haptics | `Services/Haptics.swift` → `.scrollHapticTicks()` on top-level tab `ScrollView`s |
| Freshness timestamp | `Domain/Freshness.swift` → `label(for:now:staleAfter:)` |
| Plain-English muscle names | `Domain/ExerciseInfo.swift` → `plainName(forMuscle:)` / `muscleGlossary` |
| **Schema / Data** | |
| Schema migration | `Data/Schema.swift` |

---

## Calorie math

Formula: **`kcal = (MET − 1) × bodyWeightKg × hours`** — written once, in `Domain/CalorieEstimator.swift`.

Ainsworth 2011 METs are **gross**: 1.0 MET *is* resting metabolism, so `MET × kg × hours` includes the calories you'd have burned sitting still for the same stretch. Every figure the app labels "active" / "burn" sits beside Apple Health's active energy, which is net of resting — so the estimator subtracts that one resting MET. Sub-resting METs clamp to zero. The gross product is `private` and nothing needs it: `Domain/Targets.swift` derives TDEE independently (Mifflin-St Jeor BMR × activity multiplier) and consumes nothing from `CalorieEstimator`. If a surface ever genuinely wants gross, add a gross entry point — don't drop the −1.

| Activity | MET (gross, as published) | Net multiplier used |
|---|---|---|
| Steps (3.5 mph) | 4.3 | 3.3 |
| Pilates | 3.0 | 2.0 |
| Resistance | 4.0–8.0 (see `Domain/ExerciseInfo.swift`) | 3.0–7.0 |
| Isometric hold | 3.8 default | 2.8 |
| Loaded carry, by duration (`caloriesForDuration`, `loadLb != nil`) | 4.5 | 3.5 |
| Logged cardio (run/bike/swim/…) | per-activity, `Domain/ActivityCatalog.swift` | MET − 1 |
| Live sessions | 2.8–11.8 (see `Domain/ActivityCatalog.swift`) | 1.8–10.8 |

Never hardcode kcal/rep — always (MET − 1) × weight × time.

**Never double-count steps.** Sessions whose movement the day's step count already contains are dropped from the day total by `Domain/DailyBurn.swift`: `stepOverlappingCardio` (`.walk`, `.run`) and `stepOverlappingActivityIds` (walking, running, hiking). `Activity.tracksDistance` is **not** that signal — cycling tracks distance but registers no steps, so excluding it would lose the ride entirely. Any surface that lists the contributing sessions must filter on those two sets (see `MoveCard.countedCardio` / `countedActivities`) so the rows add up to the total.

---

## Tech stack (locked)

SwiftUI (iOS 17+) · SwiftData · HealthKit · Swift Charts · XCTest · XcodeGen (`project.yml`) · Fastlane · GitHub Actions · No backend.

---

## Data model

Append-only logs. Derived figures never stored. DTOs in `Domain/Models.swift`; `@Model` classes in `Data/PersistenceModels.swift` with `snapshot` adapters; CRUD in `Data/Repositories/Repositories.swift`. Writes return success (Bool or optional DTO); callers must check before showing success or dismissing. `RepositoryWrite` saves explicitly, rolls back failures and re-fetches affected models to restore retained UI values, and posts success/failure notifications. Profile creation, starter-movement seeding is part of the one commit boundary (`Repos.createProfile`).

Key entities: `ProfileDTO`, `ExerciseDTO` (`isIsometric`), `WorkoutSetDTO` (`holdSeconds?`), `FoodLogEntryDTO` (`ingredients?`), `BodyMetricDTO`, `HealthMarkerDTO`, `StepCountDTO`, `PilatesSessionDTO`, `WaterEntryDTO`, `ActivitySessionDTO`, `SavedMealTemplateDTO`. (`ReminderGroupDTO` / `ReminderDTO` / `ReminderEventDTO` and their `@Model`s are retired — kept only so existing installs keep their rows; see [docs/removed-reminders.md](docs/removed-reminders.md).)

**`CardioSessionDTO` is legacy, read-only.** Nothing writes it any more (the card that did was unreachable and is gone); cardio is logged as an `ActivitySessionDTO` via `LogPastSessionSheet`. The read paths stay so installs that logged cardio in an older build still see and can delete those rows: `MoveCard` (burn + breakdown), `ProgressView` (Training history row + delete, energy balance), `DailyBurn.metEstimate`, `EnergyBalance.byDay`. Both paths exclude walks *and runs* so steps aren't double-counted. Note rows logged before the net-MET fix still carry their old gross `caloriesEst`. `Repos.logCardio` / `Repos.listCardio` were callerless and have been deleted — only `Repos.deleteCardioSession` remains. To write a cardio row again you'd construct `CardioSessionModel(snapshot:)` directly, but prefer `ActivitySessionDTO`.

**HealthKit crash traps (caused SIGABRT in build 37):**
- Authorization configuration errors have raised uncatchable `NSException` — call ONLY from an explicit phone Connect flow or watch Start-workout action. Never from `.task`/`.onAppear`.
- Phone `readTypes`/`writeTypes` contain quantity types; preserve the correlation-type crash guard (e.g. blood pressure). The watch also requests `HKObjectType.workoutType()` in its write set for `HKWorkoutSession` recording.

LDL/HDL/cholesterol/A1c not from Apple Health (lab-only) — manual entry. Blood glucose *is* readable from Health, but only pre-meal-marked samples may be written as `.fastingGlucose` (see the HealthKit rows above).

---

## Design rules

- **One palette for everyone:** warm light, sage/terracotta — `Theme.standard` in `Services/Theme.swift`, the `\.theme` environment default (no per-view theme application). `Info.plist` `UIUserInterfaceStyle = Light`; `AccentColor` / `LaunchBackground` in the asset catalog and the widget's Live Activity palette (`OurFitnessWidgets/LiveSessionLiveActivity.swift`) mirror it — keep them equal when retuning
- **"cal" not "kcal"** in all UI strings
- Every interaction: state change + spring animation + haptic + (wins) toast

| Surface | Shape |
|---|---|
| `Card`, `PressableCard`, `MacroQuadGrid` cells | `RoundedRectangle(cornerRadius: 16, style: .continuous)` |
| Inline card borders | `RoundedRectangle(cornerRadius: 12, style: .continuous)` |
| Primary / secondary buttons | `cornerRadius: 10` |
| Pill buttons | `cornerRadius: 20` |
| `ProgressBar` | `Capsule()` track, fill `cornerRadius: 3` |

- Sheet backgrounds: `.presentationBackground(theme.bg)` not `.background(theme.bg.ignoresSafeArea())`
- ⓘ buttons: `.sheet` with `.presentationDetents([.medium])`, never `.popover`
- Numeric keyboards: `ToolbarItemGroup(placement: .keyboard)` with Done button

---

## CI / TestFlight

Full incident narratives: [docs/ci-history.md](docs/ci-history.md). Setup: [docs/setup.md](docs/setup.md).

- **Local Mac (since 2026-08-08):** Xcode 26.6 / Swift 6.3.3 / XcodeGen 2.46 on an M5 Pro. Build and test **locally** — never push to CI to find out whether Swift compiles. The test suite runs locally too: `bundle exec fastlane ios tests` (after `xcodegen generate`).
  ```bash
  set -o pipefail
  xcodegen generate    # only after editing project.yml
  xcodebuild -project OurFitness.xcodeproj -scheme OurFitness \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E '(error:|BUILD)'
  ```
  UI smoke test (launches the app, onboards, opens every tab; not in the `OurFitness` scheme): `xcodebuild -project OurFitness.xcodeproj -scheme OurFitnessUITests -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test` — erase the simulator first (`xcrun simctl erase "iPhone 17"`) so it starts from onboarding.
  `compile.yml` still runs on push as a clean-room check; a CI-only failure means environment drift, not a Swift error. `testflight.yml` remains the shipping lane — its `Run tests` step is **tag-only** (`if: startsWith(github.ref, 'refs/tags/')`), because `compile.yml` already ran the same suite on the push, but does NOT trigger on tags. Don't make it unconditional again: that's ~4 min of a ~13 min ship re-answering a question already answered. Do keep the tag condition — a `v*` release has no other gate — local archive is now possible too — TestFlight can be released from the Mac via fastlane ([docs/setup.md](docs/setup.md) → "Simplifying signing").
- **Tests hostless:** `OurFitnessTests` compiles `Domain/` directly. No `@testable import`. `scripts/validate-ci-invariants.sh` enforces.
- **Never bare `Date()` in streak/weekly tests** — pin `now` to fixed mid-week (e.g. `2026-05-27T12:00:00Z`), thread through fixture + function.
- **Signing:** match repo `LLLlamas/Our-Fitness-Certs`, readonly CI. Manual App Store profile `OurFitness AppStore` → base64 → `APPSTORE_PROFILE_BASE64`. Widget (`com.ourfitness.app.widgets`) needs its own profile. Watch companion app (`com.ourfitness.app.watchkitapp`) has its own profile `OurFitnessWatch AppStore` → `APPSTORE_WATCH_PROFILE_BASE64` (regenerated 2026-09-05 with HealthKit, against the May-2027 distribution cert — the one `match` syncs, identified in [docs/watch-app-setup.md](docs/watch-app-setup.md); the 2026-08-08 profile predated the on-wrist workout session, and the watch App ID itself had HealthKit unchecked, which is what failed the 2026-08-12 archive); see [docs/watch-app-setup.md](docs/watch-app-setup.md).
- **XcodeGen:** never `info:` or `entitlements:` blocks on target — use `INFOPLIST_FILE`/`CODE_SIGN_ENTITLEMENTS` build settings only.
- **Entitlement missing?** Ladder: latest build → App ID capability → profile has it → `.xcarchive` → IPA.
- **Xcode 26:** version-sorted glob (not hardcoded). Build dest: `platform=iOS Simulator,name=iPhone 17`. All 4 orientations in `Info.plist`.
- Secrets: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_API_*`, `KEYCHAIN_PASSWORD`, `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION`, `APPSTORE_PROFILE_BASE64`, `APPSTORE_WIDGET_PROFILE_BASE64`, `APPSTORE_WATCH_PROFILE_BASE64`

---

## Milestone documentation

Update affected Markdown in every milestone commit alongside its code. Record current behavior, changed architecture/routing, validation actually performed, and remaining limitations. Keep dated incident narratives and research intact, with explicit historical/planned status where guidance has been superseded. Do not claim tests or external signing state were verified without evidence.

## Audit remediation and handoff

[docs/audit-handoff.md](docs/audit-handoff.md) is a **historical record** of the
2026-09-14 session, superseded on 14 Oct 2026 — read it for why the reminders and
watch work landed the way it did, not for current state. The open backlog it fed
into is [docs/next-audit-scope.md](docs/next-audit-scope.md) (privacy controls,
erase-local-data, measured performance), which is still accurate.

When a session hands off, record unverified edits explicitly and update affected
docs in the same milestone commit.

Successful repository saves, live-session changes, and defaults changes schedule
one coalesced phone-to-watch snapshot. The snapshot fetches 30 days of food logs
and today's water/steps through `Repos+SnapshotReads.swift`; historical shortcut
resolution remains available. Move refreshes its
Health readings on pull-to-refresh and foregrounding. Watch water keeps the
original action timestamp. `SessionInputValidation` resolves known activity
values on the phone and permits bounded custom intensity only for Other.

The separate hostless `OurFitnessPersistenceTests` target compiles Domain,
persistence models/repositories and selected session services directly. It checks
failed-save recovery, completion idempotency, stale runners, seeded profiles and
query equivalence with multi-year fixtures. System notification cleanup is
injected out of hostless tests; physical phone/watch integration still needs
manual verification. No historical schema or persisted raw value was changed.

## Validation records

Dated per-feature validation records: `docs/validation-records.md`.

## References

- [README.md](README.md) — getting started, local build + test
- [docs/ci-history.md](docs/ci-history.md) — incident narratives behind CI rules
- [docs/setup.md](docs/setup.md) — one-time setup, secrets, daily loop
- [docs/RepCheck.md](docs/RepCheck.md) — friction-free logging UX bar
- [docs/nutrition-plan-research.md](docs/nutrition-plan-research.md) — gain-goal nutrition spec (written when that goal was the Build mode)
- [docs/app-expansion.md](docs/app-expansion.md) — Phase 2/3 roadmap (iCloud sync, store polish)
- [docs/live-activity-setup.md](docs/live-activity-setup.md) — widget signing checklist
- [docs/watch-app-setup.md](docs/watch-app-setup.md) — watch companion app signing checklist
- [docs/removed-reminders.md](docs/removed-reminders.md) — the Reminders feature (plants, reminders, medication) was REMOVED; what went, how to recover it (git at/after `d284700`), the leftover DB tables and when they must be deleted
- [docs/medication-reminders-plan.md](docs/medication-reminders-plan.md) — RETIRED medication logging spec (kept for a future return; safety wording rules in §12/§16 were binding)
- [docs/health-data-audit.md](docs/health-data-audit.md) — **read before changing any health/fitness number.** What was wrong and fixed, what is verified correct, and the open sourcing questions that must not be "fixed" without checking the actual guideline

> `docs/encouragement-system-plan.md`, `health-tracking-ui-plan.md`, and `activity-and-ai-expansion-research.md` are dated design specs / research — forward-looking or only partly shipped. This file and the code are authoritative when they disagree.
