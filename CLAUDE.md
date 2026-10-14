# Our-Fitness — Foundation (iOS / SwiftUI)

Native iOS app targeting App Store release. Two modes: **Build** (gain mass) and **Circuit** (drop weight, fix cardiovascular markers).

> User-facing copy + the Swift symbol are both **Circuit** (`Mode.circuit`); the SwiftData raw value stays `"reset"` for back-compat — bump a schema version before changing it. `_stashed/` = excluded from build target.
> One profile per install (`Components/ProfileAvatar.swift`). Phase 2/3 roadmap: [docs/app-expansion.md](docs/app-expansion.md).

---

## Modes

| | Build | Circuit |
|---|---|---|
| Calories | TDEE + 400–600 | TDEE − 300–500 |
| Protein g/lb | ~1.0 | 1.0–1.2 |
| Steps/day | 8,000 | 10,000 |
| Workouts | rep/set, isometric holds, user exercises | parenting movements, Pilates, steps |

Circuit auto-seeds: Lifted Baby (30 lb), Lifted Stroller (25 lb), Carried Baby (30 lb). Isometric exercises: `isIsometric: true` on `ExerciseDTO`; hold saves `WorkoutSetModel{reps:1, holdSeconds:N}`; calorie: `CalorieEstimator.caloriesForIsometric`. `MacroTargets.{sodium,addedSugar,saturatedFat,fiber}` populate for Circuit and are surfaced via `Components/HeartHealthCard.swift` (fiber floor + sodium/addedSugar/satFat caps) in `NutritionView`; remaining headroom is computed by `Domain/MacroBudget.swift` → `RemainingMacros`. Build leaves all four nil.

---

## Codebase map

```
OurFitness/
  App/          ← @main, ModelContainer, root shell
  Domain/       ← PURE Swift. No SwiftUI/SwiftData. Hostless unit-test target.
  Data/         ← SwiftData @Model classes + Repositories/
  Services/     ← HealthKit, Theme, Haptics, ToastCenter, ReminderNotifications, WatchSync
  Features/     ← Onboarding, Today, Nutrition, Workouts (shared Train tab; Circuit-only Train cards under Circuit/ folder), Reminders, Progress, Settings
                  Rule: a card lives in the folder of the TAB THAT RENDERS IT, not the mode it belongs to.
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

| Goal | File(s) |
|---|---|
| **Workouts** | |
| Add exercise | `Data/Repositories/Repositories.swift` → `Repos.createExercise` |
| Add-exercise sheet (both modes) | `Features/Workouts/WorkoutsView.swift` → `AddExerciseSheet` — ONE sheet, fields vary by `mode:` (Build = tracks-weight + isometric; Circuit = reps/duration + load). Hands back an `AddExerciseSheet.Draft`; the call site owns the rep range + `Repos.createExercise`. Used by `WorkoutsView` and `BabyExercisesCard` — never add a second add-exercise sheet |
| Exercise ⓘ info sheet (both modes) | `Features/Workouts/ExerciseInfoSheet.swift` → `ExerciseInfoSheet(exercise:profile:todayCount:todayKcal:)` — ONE sheet for Build (lift list, rep counter, isometric timer) and Circuit (movement quick-log). Content priority: `Movement.postExerciseHint` → `ExerciseInfo.meta` → on-device AI (only when neither library knows the movement). Single `loadAIIfNeeded` |
| Isometric timer UI | `Features/Workouts/RepCounter.swift` → `IsometricTimerView` |
| Isometric calorie math | `Domain/CalorieEstimator.swift` → `caloriesForIsometric` |
| Rep counter | `Features/Workouts/RepCounter.swift` → `RepCounterView` |
| Delete set / exercise | `Repos.deleteSet` / `Repos.deleteExercise` + `SetHistorySheet` in `Features/Workouts/WorkoutsView.swift` |
| Log pilates | `Repos.logPilatesSession` + `Domain/Models.swift` (`PilatesSessionDTO`). ONE manual form: `LogPastSessionSheet` in `Features/Workouts/LiveSessionCard.swift` (focus-area chips + notes appear when the chosen activity is Pilates). `Features/Workouts/Circuit/PilatesCard.swift` (Train tab, Circuit) is ring/streak/history only and opens that sheet via `lockedActivityId: ActivityCatalog.pilatesId`; a live session with the Pilates activity writes the same DTO from `LiveSessionRunner.end()`. Never add a second Pilates form |
| Log cardio (run / bike / swim / row / hike) | `LogPastSessionSheet` in `Features/Workouts/LiveSessionCard.swift` — "Log session" on `LiveSessionCard` (Train tab, both modes). Saves an `ActivitySessionDTO` with the activity's Ainsworth MET from `Domain/ActivityCatalog.swift`. There is no separate cardio logger: `CardioSessionDTO` is legacy read-only (see Data model) — never add one back |
| Circuit movements (quick-log) | `Features/Workouts/Circuit/BabyExercisesCard.swift` — Train tab (`WorkoutsView` Circuit branch); renders the auto-seeded parenting exercises as tap-to-+1 |
| Live sessions (timer) | `Features/Workouts/LiveSessionCard.swift` + `Domain/LiveSessionState.swift` + `Services/LiveSessionService.swift`. `ActivityTile` / `IntensitySection` in that file are shared by `ActivityPicker` (start live) and `LogPastSessionSheet` (log after the fact) — single definitions, don't re-copy. Phone/watch completion is centralized in `Services/LiveSessionCompletionService.swift` + `Data/Repositories/Repos+SessionCompletion.swift` |
| Live Activity (Lock Screen) | `OurFitnessWidgets/LiveSessionLiveActivity.swift` + `Services/LiveSessionActivityController.swift` — [docs/live-activity-setup.md](docs/live-activity-setup.md) |
| Exercise MET / muscles | `Domain/ExerciseInfo.swift` → `namedMeta` (first-match order matters; specific before general) |
| Canonical exercise catalog | `Domain/ExerciseInfo.swift` → `catalog` (public, alphabetical, sourced from `namedMeta`) / `catalogEntry(named:)` |
| AI exercise insights | `Services/ExerciseInsightService.swift` (iOS 26+, graceful fallback; scaffolding from `OnDeviceModel`) — consumed only by `Features/Workouts/ExerciseInfoSheet.swift` |
| AI "what to work on?" suggestions | `Services/WorkoutSuggestionService.swift` + fallback `Domain/ExerciseGoalMatcher.swift` (goal→muscles→exercises, research reasons) — both take `mode:` for a Build (loadable lifts) / Circuit (higher-burn, joint-friendly) tilt → `WorkoutGoalSheet` in `WorkoutsView`. Tests: `ExerciseGoalMatcherTests` |
| **Shared on-device-AI scaffolding** | `Services/OnDeviceModel.swift` — `isAvailable`, `generate(instructions:_:)` (session + do/catch, returns nil on any failure → caller falls back to its Domain matcher), `modeLine(_:build:circuit:)`, `Cache<Value>` (JSON in UserDefaults). All five AI services use it; prompts + `@Generable` shapes stay in each service |
| Recent sessions rule | Today/Train surfaces show today + yesterday only (sets sheet is today-only); older strength, live, cardio, and Pilates sessions live in Progress → Training history |
| Live-session activities | `Domain/ActivityCatalog.swift` — stable ids `otherId` / `pilatesId` / `walkingId` (use the constant, never the literal). Walking/running/hiking are excluded from the day's burn — the exclusion set lives in `DailyBurn`, not here |
| **Nutrition** | |
| Food parser (NL → macros) | `Domain/FoodParser.swift` → `matchFood` uses `CommonFoods.bestMatch` (first-token index, size-independent) then USDA `Domain/SQLiteFoodDatabase.swift`. Keystroke = curated only; submit = full USDA DB. Tests: `FoodParserTests` |
| Add / update curated food | `Domain/CommonFoods.swift` (~1,200 foods; 16 category arrays + `expanded`) — aliases drive matching, curated shadows USDA. Append new foods to `expanded` (tie-break = `all` order; check Atwater + no alias collisions) |
| Add food (search + describe + browse, one sheet) | `Features/Nutrition/AddFoodSheet.swift` — single field: empty = recipes/recently logged/favorites pills + full library (`LazyVStack`, order favorites → `FoodAffinity.frequencyByFoodId` 30-day → rest via `defaultOrdered`); typed = "Log ‘…’" describe card (pushes `DescribeMealForm`: AI/full-DB parse + manual macros) + `FoodSearch.combined` matches. Picks confirm in `MealIngredientDetailSheet`. Used by Meals + Today; never add a second food-search/log sheet |
| AI meal parser | `Services/MealParseService.swift` (iOS 26+; text-only model; numbers from DB; scaffolding from `OnDeviceModel`) |
| Camera food label scanner | `Features/Nutrition/CameraFoodLogSheet.swift` (iOS 17+ VisionKit, iOS 26+ AI) |
| AI food alternatives | `Services/FoodAlternativeService.swift` (iOS 26+; prefetch after every log; scaffolding + `foodAlternatives.v2.*` cache from `OnDeviceModel`) |
| AI "what are you in the mood for?" | `Services/MealIdeaService.swift` (iOS 26+; prompt puts the craving first, mode/history as tie-breaks; scaffolding from `OnDeviceModel`) + fallback `Domain/MealCravingMatcher.swift` — flavours have strong/weak signals scored by density, antagonist suppression (salty↔sweet/fruity, warm↔cold) and gated+capped affinity, so a stated flavour never returns its opposite; plus a Build (protein/calorie) / Circuit (fibre/lean) macro tilt → `MoodMealSheet` in `NutritionView`. Tests: `MealCravingMatcherTests` |
| Meal log UI + day history + past-day logging | `Features/Nutrition/NutritionView.swift` — day strip (last 7 days, dot = has logs) for quick switching + a history button opening `Features/Nutrition/MealHistorySheet.swift`. **`MealHistoryList` is THE day-history list** (one row per logged day: date · totals · the meals eaten); the trend sheet's "Recent days" renders the same component, so never write a second one. All three entry points route through `NutritionView.selectDay(_:)` so animation + haptic match. No calendar picker — a grid makes users hunt through empty dates; the list shows the days they actually logged |
| Ingredient-level editing / logging | `Features/Nutrition/MealIngredientDetailSheet.swift` — takes `targetDate:` for past-day logging |
| Meal suggestions (no standalone UI) | `Domain/SuggestedMeals.swift` → meal pool + `ranked(...)`, consumed only as `MealCravingMatcher`'s fallback; ideas UI is `MoodMealSheet` only (Suggestions sheet/"for you" row removed as redundant) |
| Personalised recs / most-logged foods | `Domain/FoodAffinity.swift` → `mostLoggedIds(_:days:limit:end:)` / `frequencyByFoodId(_:days:end:)` (30-day window over foodIds incl. ingredients); feeds `AddFoodSheet` ordering + `MealCravingMatcher` |
| Meal-logging streak (consecutive days) | `Domain/Streaks.swift` → `loggingStreak(...)`; copy `EncouragementEngine.mealStreakMessage(days:mode:)` (3/7/14/30/60/100); toast `ToastCenter.mealStreak(...)`; chip in `NutritionView` |
| Circuit heart-health micros (fiber floor + sodium/sugar/satfat caps) | `Components/HeartHealthCard.swift` (Circuit-only; no-op if targets have no caps) — rendered in `NutritionView` after the totals card. **Only fiber gets a ProgressBar**: sodium/added sugar/sat fat exist in no curated or USDA food row (camera label scan is the only source), so those three render off `MacroBudget.capCoverage` — `.none` = em-dash vs the cap ("not tracked"), `.partial` = `N+` floor figure, `.full` = real inverted bar. Never draw a cap bar straight off `DailyTotals`: a summed 0 would colour itself safely-under-cap for someone who ate 3,000 mg. Pass `entries:` (the day's `[FoodLogEntryDTO]`) to get `.partial`/`.full`; omitted, coverage falls back to what the totals alone can prove |
| Remaining macros / headroom under caps | `Domain/MacroBudget.swift` → `remaining(totals:targets:)` returns `RemainingMacros` (caps = room left, negative when over; fiber = signed distance to floor; all four nil in Build). Prefer `remaining(totals:targets:entries:)` — it also nils the three caps when nothing logged measured them, so nil = "no number to show" (no cap configured **or** unmeasured); use `capCoverage` to tell those apart |
| Can a logged food supply sodium / added sugar / sat fat? | Only `Features/Nutrition/CameraFoodLogSheet.swift` (label scan → `PerServing` with all three). `CommonFoods` (5 nutrients), the USDA SQLite table (5 columns), `MealIngredient.from`, and every manual-macro form leave them 0. `MacroBudget.capCoverage` reads provenance off the values: a positive figure can only be label-sourced, and one positive vouches for the other two on that entry |
| Personal meal templates | `Domain/Models.swift` (`SavedMealTemplateDTO`) + `Data/PersistenceModels.swift` (`SavedMealTemplateModel`) |
| Weekly nutrition trend | `Domain/NutritionHistory.swift` + `Features/Nutrition/NutritionTrendSheet.swift` |
| Calorie / macro target math | `Domain/Targets.swift` only (intake side: BMR → TDEE → targets). Activity *burn* math is `Domain/CalorieEstimator.swift` — see Calorie math |
| Target rationale copy | `Domain/TargetRationale.swift` (spell out acronyms; "cal" not "kcal"); Circuit micro copy `fiberWhy`/`sodiumWhy`/`addedSugarWhy`/`saturatedFatWhy(for:)` (used by `HeartHealthCard` info sheet) |
| **Today / Steps** | |
| Move card (2×3 cols) | `Features/Today/MoveCard.swift` — row 1: Apple Total · Our Total Estimate · Training Only; row 2: Distance · Flights · Heart Rate. **No steps row** — steps live only in `StepsCard` (it had a duplicate count, goal, goal-picker and info sheet, plus a stale gross-MET formula string). Single `metricColumn` helper (uniform 22pt value font, no differential shrink). `activityRow(kcal:)` takes `Int`. Burn figures come from `DailyBurn.breakdown` (never re-derive MET math or the step-overlap exclusions here — `countedCardio` / `countedActivities` read `DailyBurn`'s sets); unit conversions via `Units.kgPerLb` / `Units.kmPerMile`; the 7 column info sheets sit on `Components/InfoSheet.swift`. Move only renders when `profile.healthGranted` — ungranted, `TodayView` shows `connectHealthCard` at the top instead |
| Steps card (both modes, Today only) | `Features/Today/StepsCard.swift` — one mode-aware card: Build = hero count + `ProgressBar`; Circuit = `ProgressRing` + projection + pace-vs-yesterday + 7-day strip + week-to-date active cal / exercise min. One goal-picker sheet (shared `Components/GoalPickerSheet.swift`; days/week wheel is Circuit-only) + one info sheet (shared `Components/InfoSheet.swift`). Goal keys live in `StepsGoalPrefs` in the same file. Never add a second steps card |
| Water tracker (presets + day-streak) | `Domain/Water.swift` (presets Sip 4 / S 8 / M 16 / L 32 oz; `total(_:on:)`, `streak(_:goalFlOz:end:)`) + `Features/Today/WaterCard.swift` (streak chip = shared `Components/StreakChip.swift`) |
| Log water (shared path — use for ANY new water surface) | `Features/Today/WaterLogging.swift` → `WaterLog.add(_:for:on:context:lastFlOz:unitSystem:toasts:)` — one write + remembers the repeat-last amount + one copy of the toast; also owns the `waterGoalFlOz.\(profileId)` / `waterLastFlOz.\(profileId)` AppStorage keys. No explicit haptic (ToastCenter.show fires one) |
| Water quick-log (app-wide FAB) | `Features/Today/WaterQuickLogButton.swift` — tap = repeat last, press-and-hold = dim screen + radial preset picker; logs via `WaterLog.add`. Overlaid in `App/RootView.swift` |
| Step milestones / goals | `Domain/Movement.swift` (`defaultStepMilestones`). Per-profile override: `AppStorage "stepsGoal.\(profileId.uuidString)"` |
| Today burn estimate | `Domain/DailyBurn.swift` → `metEstimate` (day total) / `breakdown(...)` → `Breakdown` (per-source split: steps, sets, cardio, pilates, activities; `trainingKcal` excludes steps; `total` == `metEstimate`). Net of resting — see Calorie math. The step-overlap exclusions live here as `stepOverlappingCardio` / `stepOverlappingActivityIds`. Tests: `OurFitnessTests/DailyBurnTests.swift` |
| Encouragement / milestones | `Domain/EncouragementEngine.swift` + `Domain/EncouragementMessage.swift` + `Components/ProjectionBar.swift` |
| Meal/water nudges | `Domain/EncouragementEngine.swift` → `mealLoggingNudge` / `waterNudge`; wired in `Features/Today/TodayView.swift` |
| **Reminders** | |
| Plant watering catalog (~26 species: interval/amount/light adjustment/care notes) | `Domain/PlantCatalog.swift` — sourced from university extension services, botanical gardens, ASPCA toxicity data |
| Medication timing math (set times + inferred pattern) | `Domain/MedicationPattern.swift` → `recentDailyFirstLogs`/`typicalMinuteOfDay`/`hasDisplayablePattern`/`hasLogToday`/`nextFireDate` (inferred path only — set times never reach it) — pure, injectable now/calendar. Median of the earliest dose per day over 7 days, today excluded. Two thresholds, deliberately different: 1 day of history is enough to SCHEDULE a nudge, 2 (`minDaysForDisplay`) before the UI claims a routine. Build fire instants through calendar day+wall-clock components, never by adding minutes — that was an hour wrong on the spring-forward day. Tests: `MedicationPatternTests` |
| **Set** dose times vs the **observed** one | `ReminderDTO.scheduledMinutesOfDay` — a LIST of minutes from local midnight, user-entered, several per medication (morning + night). Non-empty means the inferred `MedicationPattern.typicalMinuteOfDay` is not used at all. Always store through `MedicationPattern.normalizedTimes` (clamp + dedupe + sort) — but never sort mid-edit, which moves a row out from under the user's finger, hence `DoseTimesEditor` normalising only at the save boundary. Minute-of-day ↔ Date conversions and all clock copy go through `clampMinuteOfDay`/`minuteOfDay(of:)`/`date(minuteOfDay:on:)`/`clockLabel`/`clockList` — a `DateComponents` on a fixed reference day, never a Date built from today (DST) |
| **Set times are daily alarms — the two paths are scheduled differently** | Set times → one `UNCalendarNotificationTrigger(hour, minute, repeats: true)` per time, id `reminder.<uuid>#<minute>`. No fire instant, no grace (the user picked the minute), no re-arm. No set times → the unchanged inferred one-shot via `MedicationPattern.nextFireDate` (median + 30 min grace), re-armed by `reschedule`/`reconcile`. **Never convert set times back to one-shots:** a one-shot is re-armed only when the app RUNS, so a nudge ignored without opening the app was the last one that medication ever produced. Because a repeating alarm can't skip a day, it fires whether or not a dose was logged — suppression lives in the UI (`MedicationDueBanner`), not the trigger |
| Dose logged vs its set times | `MedicationPattern.nearestTime` picks which set time a dose reads against (wraps around midnight: an 11pm dose logged at 00:20 is 80 min late, not 22 hr early; a log at 8:14 PM reads against the 8 PM dose, not the morning one) → `minutesFromNearest` (signed) → copy via `timingLabel` ("12 min after 8:00 AM" / "On time" inside `onTimeToleranceMinutes`). Returns nil with no set times, which means render nothing |
| In-app "dose not logged" alert | `Features/Reminders/MedicationDueBanner.swift`, rendered in `App/RootView.swift` between the header and the `TabView` (under, not over — app-wide on every tab). Reads STATE, not notifications, so it's right even when permission was refused; a 60s timer brings it in when a time passes mid-session. Shows only medications with SET times, and compares **counts** (`MedicationPattern.timesReached` vs today's logs) — matching a log to a specific dose isn't knowable and guessing produces the "you missed one" claim §16 forbids |
| Medication history (all medications, by day + time) | `Domain/MedicationHistory.swift` → `entries(events:medications:)` joins events to medications (and IS the filter — a plant watering has no entry in the lookup, so it drops out) → `byDay` (newest day first, doses earliest-first WITHIN a day) / `dayTitle` / `totals`. UI `Features/Reminders/MedicationHistorySheet.swift`, reached from the MEDICATION section header; `ReminderDetailSheet`'s per-medication history renders through the same functions so the two can't disagree. **Uncapped on purpose** — a record that silently stops at N rows reads as "that's all there was". Tests: `MedicationHistoryTests` |
| Medication UI (cards, add form, log sheet, history) | `Features/Reminders/RemindersView.swift` (MEDICATION section, always first, above Due; header carries History + Add) + `AddReminderSheet.swift` (`medicationFormSection`) + `LogMedicationSheet.swift` (prefilled dosage + time picker) + `ReminderDetailSheet.swift` (medication branch: set-for row, pattern line, history by day, disclaimer) + `MedicationHistorySheet.swift`. Medication is excluded from the Due/upcoming lists — those are interval-driven, and an "overdue" badge would be a missed-dose claim |
| Medication has **no photo** | Deliberate: a plant is identified by looking at it, a medication by name + dosage. No photo step in `medicationFormSection`, no `photoHeader` in the detail sheet's medication branch, and the card uses `medicationIcon` rather than `thumbnail` — an empty camera circle only invites a tap that does nothing. `photoData` on medication rows written before this stays on disk, unread |
| Recommended dosage vs dosage taken | `ReminderDTO.dosage` (the configured recommendation) vs `ReminderEventDTO.dosageTaken` (what was actually taken, per event). Logging NEVER writes back to `dosage`. A one-tap log with no amount (lock screen, watch, quick button) resolves to the recommendation in `ReminderNotificationService.logDone` |
| Medication notification copy | `Services/ReminderNotificationService.swift` → `medicationRequests`/`medicationContent` (two bodies: set-time — "X is set for 8:00 AM. Tap to log this dose." — and inferred). **Safety rule: it may only ever say a dose has not been LOGGED** — never "take X now", never "missed", never an amount. A set time names the hour the user themselves entered; it still does not say a dose is due. The app can't tell taken-but-unlogged from skipped from clinician-changed. Opt-in per medication (`ReminderDTO.patternReminderEnabled`, default off); `buildRequest` returns nil when off, and both callers treat nil as "cancel what's pending" |
| Reminder due-date math | `Domain/ReminderSchedule.swift` → `nextDueDay`/`daysUntilDue`/`isDue`/`overdueDays`/`fireDate`/`snoozeDate` — pure, injectable now/calendar |
| Repeat interval (generic, 1–365) | `Domain/ReminderSchedule.swift` → `minIntervalDays`/`maxIntervalDays`/`clampInterval`/`intervalPresets`/`intervalLabel`. **These are the bounds for everything except plant watering** — `PlantCatalog`'s narrower 2–60 governs only the seeded-watering math. Every clamp and every "every N days" string goes through here; hand-rolled interpolation reintroduces the "Every 1 days" plural bug |
| Interval picker UI (preset pills + stepper) | `Features/Reminders/IntervalPicker.swift` — used by the custom-reminder forms in both reminder sheets; plant watering keeps its own `PlantCatalog`-bounded stepper |
| Reminder CRUD / groups | `Data/Repositories/Repositories.swift` → `Repos.addReminder`/`updateReminder`/`deleteReminder`/`logReminderDone`/`snoozeReminder` + `addReminderGroup`/`deleteReminderGroup`/`ensurePlantsGroup`/`ensureMedicationGroup`. Two built-in groups ("Medication", "Plants") auto-created for new profiles in `Repos.createProfile`; `Seeder.swift` backstops existing profiles. Only `.custom` groups are deletable — an `ensure…` call would just recreate a built-in |
| Reminder / group / event models | `Domain/Models.swift` (`ReminderGroupDTO`, `ReminderDTO`, `ReminderEventDTO` — append-only completion log) |
| Notification scheduling + lock-screen actions | `Services/ReminderNotificationService.swift` — `UNNotificationCategory` action buttons ("Watered"/"Done"/"Log taken" + "Snooze 1 day", three categories) work from the lock screen and mirror to a paired Apple Watch with zero watch app needed; `AppNotificationDelegate` handles the actions incl. waking the app from a killed state. Reminder notifications are the ONLY ones shown while the app is FOREGROUNDED — `willPresent` returns `[.banner, .list, .sound]` for `reminder.*` identifiers and `[]` for everything else (the live-session ping stays silent); don't collapse that branch. Auth is `[.alert, .sound]` — no `.badge`, so no icon count by design. One reminder can now own SEVERAL pending requests, so `cancel` and `reschedule` sweep by reminder id (parsed out of the identifier) rather than by exact identifier. Auth requested only from explicit user actions (Add-reminder save / in-tab banner) — never `.onAppear`/`.task` |
| Watch companion sync | `Services/WatchSyncService.swift` + `Shared/WatchSyncPayload.swift` — `WatchConnectivity`: `updateApplicationContext` (phone→watch push), `transferUserInfo` (watch→phone actions), `transferFile` (photo thumbnails). Watch is a thin client with no local SwiftData; phone is source of truth |
| Adding anything to the watch's data | `Shared/WatchSyncPayload.swift` → `WatchSnapshotEnvelope`. **ONE envelope under ONE context key — never add a second key.** `updateApplicationContext` replaces the whole dictionary, so a second key silently clobbers the first. Phone builds it in one pass in `WatchSyncService.pushSnapshot`; give any new field a default in the hand-written `init(from:)` (a memberwise default is ignored by synthesised `Codable` for a missing key, which would break older payloads wholesale). Tests: `OurFitnessTests/WatchSyncPayloadTests.swift` |
| Wrist → phone mutations | `WatchAction` in `Shared/WatchSyncPayload.swift`, applied by `WatchSyncService.apply`. The watch sends an **id**; the phone re-resolves real macros/calories — never trust numbers off the wire, a stale snapshot must not be able to write wrong data |
| Reminder / thumbnail photo downscale | `Services/ImageDownscale.swift` — shared by reminder photo capture and watch thumbnails |
| Reminders tab UI | `Features/Reminders/RemindersView.swift` + `AddReminderSheet.swift` + `ReminderDetailSheet.swift` + `LogMedicationSheet.swift` + `MedicationHistorySheet.swift` + `MedicationDueBanner.swift` + `DoseTimesEditor.swift` + `IntervalPicker.swift` + `AmountFlOzRow.swift`, `Components/ImagePickerView.swift`. `AddReminderSheet` deliberately has **no default group** (`resolvedGroupId` is nil until tapped) so Add doesn't drop the user into plant species search — don't reinstate a Plants fallback |
| Is this reminder a plant? | `ReminderDTO.isPlant` (`Domain/Models.swift`) — plant-only fields are nil in a custom group. Note `ReminderSnapshot.isPlant` in `Shared/` answers the same question from `groupKind`, because the wire format can't see Domain types |
| The watch knows nothing about dose times | `ReminderSnapshot` (`Shared/`) carries neither `scheduledMinutesOfDay` nor `dosage`, so the wrist shows name + last-logged + "Log taken" and nothing about timing. Adding either means a new field on the envelope WITH a default in the hand-written `init(from:)` |
| Is this reminder a medication? | Ask the GROUP, not the DTO: `ReminderGroupKind.medication`. There is deliberately no `ReminderDTO.isMedication` — `ReminderDetailSheet` takes `groupKind:` as an init parameter resolved once per presentation. On the wrist, `WatchReminderKind` (in `OurFitnessWatch/ReminderListView.swift`) maps the raw `groupKind` string once for both watch views |
| Reminder group order | `ReminderGroupKind.sortRank` (`Domain/Models.swift`) — medication 0, plants 1, custom 2. Fixed, never alphabetical for built-ins; both `RemindersView.orderedGroups` and `AddReminderSheet.orderedGroups` sort by it, and the watch mirrors it in `WatchReminderKind.sortRank` |
| Reminders on/off + reminder hour | `Features/Settings/SettingsView.swift` → `remindersSection` — `AppStorage "reminders.enabled"` (global, default on), `AppStorage "reminderHour.<profile-uuid>"` (per-profile, default 9am) |
| Watch app (thin client, no local SwiftData) | `OurFitnessWatch/` — root `OurFitnessWatchApp.swift` is a 4-tab `TabView`: `WatchTodayView` (glance + water quick-log) · `WatchTrainView` (`WatchLiveSessionView` + `WatchQuickLogView`) · `WatchMealsView` · `ReminderListView`/`ReminderDetailView`. State in `WatchSyncStore.swift` — [docs/watch-app-setup.md](docs/watch-app-setup.md) |
| Watch target extra sources | `project.yml` → `OurFitnessWatch.sources`: `Domain/PlantCatalog.swift`, `ReminderSchedule.swift`, `LiveSessionState.swift`, `ActivityCatalog.swift`, `CalorieEstimator.swift`, `Shared/WatchSyncPayload.swift` (mirrors `OurFitnessTests` compiling `Domain/` directly). **Each must stay Foundation-only with no other Domain type** or it drags the rest of Domain onto the wrist — that's why `CalorieEstimator`'s exercise-aware overload lives in `Domain/ExerciseCalories.swift` |
| On-wrist workout / heart rate | `OurFitnessWatch/WatchWorkoutSession.swift` — `HKWorkoutSession` + `HKLiveWorkoutBuilder`, started from the live-session Start tap only (uncatchable-NSException rule). Additive telemetry: the phone still stores the deterministic MET estimate. Needs `OurFitnessWatch.entitlements` + `WKBackgroundModes: workout-processing` + a HealthKit-enabled watch profile |
| **Progress** | |
| Add health marker kind | `Domain/Models.swift` (`HealthMarkerKind`) + `Domain/HealthRanges.swift` (exhaustive switches) + `Features/Progress/ProgressView.swift` |
| Show/hide trackers | `Features/Progress/EditTrackersSheet.swift` — `AppStorage "progressStats.\(profileId)"`. Default set = `StatKind.isRelevant(for:)`, which is ONLY the trackers the app can fill in itself (weight / steps / training volume; + resting HR + BP in Circuit); everything needing calipers, a tape, a cuff, or a lab starts hidden. `ProgressTabView.enabledSet(body:markers:)` then re-adds any tracker that already `hasLoggedData`, so shrinking the default never hides a card someone was filling in. A stored CSV always wins. |
| Stat detail sheet (chart + entries + log) | `Components/StatDetailSheet.swift` — ONE sheet for every tracker. Metric-specific bits come in as slots (`headline`, `chartOverride`, `logOverride`, `footer`) plus `validate` / `showsEntries` / `minChartPoints` / `detents`; `StatDetailRow` is the shared label/value row. Weight (wheel picker), Body fat, BMI, and Blood pressure in `ProgressView.swift` are all thin hosts over it — never write another bespoke detail sheet |
| Training volume | `Domain/TrainingHistory.swift` → `setsInWeek(_:weeksAgo:now:)` / `weeklySetCounts(_:weeks:now:)` (Monday ISO weeks), surfaced via `StatKind.trainingVolume` in `Features/Progress/ProgressView.swift`. Tests: `TrainingHistoryTests` |
| Weeks ("this week") | `Domain/Dates.startOfISOWeek(_:weeksAgo:)` — Monday-anchored, the app-wide definition. Never `Calendar.current` week components (Sunday-based in the US). `Domain/Movement.swift` and `Features/Workouts/RepCounter.swift` still build their own Monday calendars — migrate them to this helper when touched. Tests: `DatesTests` |
| Calorie intake vs activity burn | `Domain/EnergyBalance.swift` → `byDay(...)` / `averages(_:)` (intake = `DailyTotals`; burn = `DailyBurn.metEstimate` — active-only, step-overlapping sessions excluded). Card `energyBalanceCard` (both modes) in `Features/Progress/ProgressView.swift` → detail `Features/Progress/EnergyBalanceDetailSheet.swift` (Charts: intake bars vs burn line + target rule). Tests: `OurFitnessTests/EnergyBalanceTests.swift` |
| Training history (cross-day) | `Domain/TrainingHistory.swift` → `sessions(sets:exercises:)` strength grouping + `TrainingHistorySheet` in `Features/Progress/ProgressView.swift` for strength, live, cardio, and Pilates sessions. Tests: `OurFitnessTests/TrainingHistoryTests.swift` |
| Tracker display order | alphabetical by `StatKind.title` at the two render sites (`visibleStats(in:)` + `EditTrackersSheet` ForEach); never reorder the enum (persisted CSV) |
| Latest value of a health marker | `Trends.markerSeries(_:kind:).last?.value` — via the single `latestMarkerValue` helper in `ProgressView.swift`. Don't re-filter/sort markers inline |
| BMI / body-fat thresholds | `Domain/BodyComposition.swift` → `bmiCategory` / `bodyFatCategory` own every boundary. The Progress sheets read labels from them (`bmiIsHealthy`, the probe-value range tables); never restate 18.5 / 25 or a body-fat band in a view |
| **Settings / Profile** | |
| Edit vitals | `Repos.updateVitals` + `Features/Settings/SettingsView.swift` → `EditVitalsSheet` |
| Switch mode | `Repos.updateMode` + `Features/Settings/SettingsView.swift` → `ModeSwitchSheet` |
| App tab layout | `App/RootView.swift` — both modes: Today / Meals / Train / Reminders / Progress. `WorkoutsView` is mode-aware (Build = lift list + rep counter; Circuit = Pilates + movement quick-log). Today is a **read-only status board**: macros · move · water · steps, and a log list with no tap target. One surface per job — logging food happens on Meals, nowhere else |
| Profile avatar | `Components/ProfileAvatar.swift` |
| Units (metric ↔ imperial) | `Domain/Units.swift` — canonical storage IMPERIAL; convert only at UI boundary |
| Sync current weight | `Repos.syncCurrentWeight` — called after progress log, HK sync, TodayView task |
| **HealthKit** | |
| New HK metric | `Services/HealthKitService.swift` + `Data/PersistenceModels.swift` |
| Sync Health into logs | `HealthKitService.syncFromHealth` (deduped upsert; re-points `profile.weightLb`) |
| Fasting glucose from Health | `HealthKitService.latestFastingGlucoseMgDL` — only samples HealthKit marks pre-meal (`HKMetadataKeyBloodGlucoseMealTime` == `.preprandial`) become `.fastingGlucose`; post-meal and metadata-less samples are **dropped**, because a normal post-meal 150 filed as fasting trips `HealthRanges` ≥126 → high (ADA diabetes cut-point). Storing them needs a new non-fasting glucose `HealthMarkerKind` |
| Weekly Health totals | `HealthKitService.weekToDateBounds` → must use `Dates.startOfISOWeek` (Monday). Never `Calendar.current` week intervals — Sunday-first in the US locale, which desyncs the StepsCard week cells from every other weekly figure |
| Absent-data policy for HK sums | `sumOrNil` / `dailySums` return nil / omit the key so the UI can hide the stat; `dailySum` (single day) is the one place absent collapses to 0. Never fabricate a 0 for a day that simply never synced |
| **UI / Components** | |
| Button variants (5 total) | `Components/TactileButtonStyle.swift` — never add a 6th |
| Circular progress | `Components/ProgressRing.swift` — never inline `Circle().trim` |
| ⓘ info-sheet chrome | `Components/InfoSheet.swift` → `InfoSheetScaffold(title:subtitle:titleSize:dragIndicator:)` + `InfoSection`, `InfoBody`, `InfoFootnote`, `InfoRow(label:detail:emphasis:)`, `InfoCalcRow(label:detail:labelWraps:)`, `InfoMetricRow`, `InfoHeroStat`, `Bullet(_:marker:)`. Carries chrome only — all copy/numbers/citations stay at the call site. Never re-roll a private `infoSection`/`calcRow`/`bullet` helper |
| Goal-picker wheel sheet | `Components/GoalPickerSheet.swift` → `GoalPickerSheet(title:subtitle:wheels:wheelVerticalPadding:resetLabel:detents:onReset:onSave:)`; `[Wheel]` so Circuit steps can show a second days/week wheel. Fires the Save success haptic itself |
| Progress-fill replay (sweep from 0 on appear) | `Components/VisibilityReveal.swift` → `.revealOnAppear($reveal)` — resets to 0 on scroll-out, springs to full on re-entry. Used by `ProgressBar` + `MacroQuadGrid` (`pct * reveal`) |
| Haptics | `Services/Haptics.swift` |
| Toast | `Services/ToastCenter.swift` + `Components/ToastView.swift` — `show(_:for:)` for a `Toast`, `show(_:accent:for:)` for an `EncouragementMessage` (every encouragement wrapper is a one-liner over it). `show` fires the outcome haptic itself: never call `Haptics.*` right before it |
| Scroll haptics | `Services/Haptics.swift` → `.scrollHapticTicks()` on top-level tab `ScrollView`s |
| Freshness timestamp | `Domain/Freshness.swift` → `label(for:now:staleAfter:)` |
| Plain-English muscle names | `Domain/ExerciseInfo.swift` → `plainName(forMuscle:)` / `muscleGlossary` |
| **Schema / Data** | |
| Schema migration | `Data/Schema.swift` — current SchemaV7. Additive (new optional field / entity) = automatic. Structural = `.custom` stage. |

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

Append-only logs. Derived figures never stored. DTOs in `Domain/Models.swift`; `@Model` classes in `Data/PersistenceModels.swift` with `snapshot` adapters; CRUD in `Data/Repositories/Repositories.swift`. Writes return success (Bool or optional DTO); callers must check before showing success or dismissing. `RepositoryWrite` saves explicitly, rolls back failures and re-fetches affected models to restore retained UI values, and posts success/failure notifications. Profile creation and Circuit seeding share a commit boundary.

Key entities: `ProfileDTO`, `ExerciseDTO` (`isIsometric`), `WorkoutSetDTO` (`holdSeconds?`), `FoodLogEntryDTO` (`ingredients?`), `BodyMetricDTO`, `HealthMarkerDTO`, `StepCountDTO`, `PilatesSessionDTO`, `WaterEntryDTO`, `ActivitySessionDTO`, `SavedMealTemplateDTO`, `ReminderGroupDTO`, `ReminderDTO`, `ReminderEventDTO`.

**`CardioSessionDTO` is legacy, read-only.** Nothing writes it any more (the card that did was unreachable and is gone); cardio is logged as an `ActivitySessionDTO` via `LogPastSessionSheet`. The read paths stay so installs that logged cardio in an older build still see and can delete those rows: `MoveCard` (burn + breakdown), `ProgressView` (Training history row + delete, energy balance), `DailyBurn.metEstimate`, `EnergyBalance.byDay`. Both paths exclude walks *and runs* so steps aren't double-counted. Note rows logged before the net-MET fix still carry their old gross `caloriesEst`. `Repos.logCardio` / `Repos.listCardio` were callerless and have been deleted — only `Repos.deleteCardioSession` remains. To write a cardio row again you'd construct `CardioSessionModel(snapshot:)` directly, but prefer `ActivitySessionDTO`.

**HealthKit crash traps (caused SIGABRT in build 37):**
- Authorization configuration errors have raised uncatchable `NSException` — call ONLY from an explicit phone Connect flow or watch Start-workout action. Never from `.task`/`.onAppear`.
- Phone `readTypes`/`writeTypes` contain quantity types; preserve the correlation-type crash guard (e.g. blood pressure). The watch also requests `HKObjectType.workoutType()` in its write set for `HKWorkoutSession` recording.

LDL/HDL/cholesterol/A1c not from Apple Health (lab-only) — manual entry. Blood glucose *is* readable from Health, but only pre-meal-marked samples may be written as `.fastingGlucose` (see the HealthKit rows above).

---

## Design rules

- **Build:** warm dark, orange/amber/cream · **Circuit:** warm light, sage/terracotta
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
- `themed(_:)` in `Services/Theme.swift` sets theme key + `colorScheme` — never override individually
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
resolution and full medication history remain available. Move refreshes its
Health readings on pull-to-refresh and foregrounding. Watch water keeps the
original action timestamp. `SessionInputValidation` resolves known activity
values on the phone and permits bounded custom intensity only for Other.

The separate hostless `OurFitnessPersistenceTests` target compiles Domain,
persistence models/repositories and selected session services directly. It checks
failed-save recovery, completion idempotency, stale runners, seeded profiles and
query equivalence with multi-year fixtures. System notification cleanup is
injected out of hostless tests; physical phone/watch integration still needs
manual verification. No historical schema or persisted raw value was changed.

## References

- [README.md](README.md) — getting started, local build + test
- [docs/ci-history.md](docs/ci-history.md) — incident narratives behind CI rules
- [docs/setup.md](docs/setup.md) — one-time setup, secrets, daily loop
- [docs/RepCheck.md](docs/RepCheck.md) — friction-free logging UX bar
- [docs/nutrition-plan-research.md](docs/nutrition-plan-research.md) — Build nutrition spec
- [docs/app-expansion.md](docs/app-expansion.md) — Phase 2/3 roadmap (iCloud sync, store polish)
- [docs/live-activity-setup.md](docs/live-activity-setup.md) — widget signing checklist
- [docs/watch-app-setup.md](docs/watch-app-setup.md) — watch companion app signing checklist
- [docs/medication-reminders-plan.md](docs/medication-reminders-plan.md) — medication logging spec (the feature as shipped; safety wording rules in §12/§16 are binding)
- [docs/health-data-audit.md](docs/health-data-audit.md) — **read before changing any health/fitness number.** What was wrong and fixed, what is verified correct, and the open sourcing questions that must not be "fixed" without checking the actual guideline

> `docs/encouragement-system-plan.md`, `health-tracking-ui-plan.md`, and `activity-and-ai-expansion-research.md` are dated design specs / research — forward-looking or only partly shipped. This file and the code are authoritative when they disagree.
