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

---

## Where to touch

| Goal | File(s) |
|---|---|
| **Workouts** | |
| Add exercise | `Data/Repositories/Repositories.swift` → `Repos.createExercise` |
| Isometric timer UI | `Features/Workouts/RepCounter.swift` → `IsometricTimerView` |
| Isometric calorie math | `Domain/CalorieEstimator.swift` → `caloriesForIsometric` |
| Rep counter | `Features/Workouts/RepCounter.swift` → `RepCounterView` |
| Delete set / exercise | `Repos.deleteSet` / `Repos.deleteExercise` + `SetHistorySheet` in `Features/Workouts/WorkoutsView.swift` |
| Log pilates | `Repos.logPilatesSession` + `Domain/Models.swift` (`PilatesSessionDTO`); UI `Features/Workouts/Circuit/PilatesCard.swift` (Train tab, Circuit) |
| Log cardio | `Repos.logCardio` + `Domain/Models.swift` (`CardioSessionDTO`) |
| Circuit movements (quick-log) | `Features/Workouts/Circuit/BabyExercisesCard.swift` — Train tab (`WorkoutsView` Circuit branch); renders the auto-seeded parenting exercises as tap-to-+1 |
| Live sessions (timer) | `Features/Workouts/LiveSessionCard.swift` + `Domain/LiveSessionState.swift` + `Services/LiveSessionService.swift`; phone/watch completion is centralized in `Services/LiveSessionCompletionService.swift` + `Data/Repositories/Repos+SessionCompletion.swift` |
| Live Activity (Lock Screen) | `OurFitnessWidgets/LiveSessionLiveActivity.swift` + `Services/LiveSessionActivityController.swift` — [docs/live-activity-setup.md](docs/live-activity-setup.md) |
| Exercise MET / muscles | `Domain/ExerciseInfo.swift` → `namedMeta` (first-match order matters; specific before general) |
| Canonical exercise catalog | `Domain/ExerciseInfo.swift` → `catalog` (public, alphabetical, sourced from `namedMeta`) / `catalogEntry(named:)` |
| AI exercise insights | `Services/ExerciseInsightService.swift` (iOS 26+, graceful fallback) |
| AI "what to work on?" suggestions | `Services/WorkoutSuggestionService.swift` + fallback `Domain/ExerciseGoalMatcher.swift` (goal→muscles→exercises, research reasons) — both take `mode:` for a Build (loadable lifts) / Circuit (higher-burn, joint-friendly) tilt → `WorkoutGoalSheet` in `WorkoutsView`. Tests: `ExerciseGoalMatcherTests` |
| Recent sessions rule | Today/Train surfaces show today + yesterday only (sets sheet is today-only); older strength, live, cardio, and Pilates sessions live in Progress → Training history |
| Live-session activities | `Domain/ActivityCatalog.swift` |
| **Nutrition** | |
| Food parser (NL → macros) | `Domain/FoodParser.swift` → `matchFood` uses `CommonFoods.bestMatch` (first-token index, size-independent) then USDA `Domain/SQLiteFoodDatabase.swift`. Keystroke = curated only; submit = full USDA DB. Tests: `FoodParserTests` |
| Add / update curated food | `Domain/CommonFoods.swift` (~1,200 foods; 16 category arrays + `expanded`) — aliases drive matching, curated shadows USDA. Append new foods to `expanded` (tie-break = `all` order; check Atwater + no alias collisions) |
| Food library browse (lazy + sort) | `NutritionView` → `FoodLibrarySheet` — `LazyVStack`; empty-query order = favorites → `FoodAffinity.frequencyByFoodId` (30-day) → rest (`defaultOrdered()`) |
| AI meal parser | `Services/MealParseService.swift` (iOS 26+; text-only model; numbers from DB) |
| Camera food label scanner | `Features/Nutrition/CameraFoodLogSheet.swift` (iOS 17+ VisionKit, iOS 26+ AI) |
| AI food alternatives | `Services/FoodAlternativeService.swift` (iOS 26+; prefetch after every log) |
| AI "what are you in the mood for?" | `Services/MealIdeaService.swift` (iOS 26+; prompt puts the craving first, mode/history as tie-breaks) + fallback `Domain/MealCravingMatcher.swift` — flavours have strong/weak signals scored by density, antagonist suppression (salty↔sweet/fruity, warm↔cold) and gated+capped affinity, so a stated flavour never returns its opposite; plus a Build (protein/calorie) / Circuit (fibre/lean) macro tilt → `MoodMealSheet` in `NutritionView`. Tests: `MealCravingMatcherTests` |
| Meal log UI + day selector + past-day logging | `Features/Nutrition/NutritionView.swift` |
| Ingredient-level editing / logging | `Features/Nutrition/MealIngredientDetailSheet.swift` — takes `targetDate:` for past-day logging |
| Meal suggestions | `Domain/SuggestedMeals.swift` → `ranked(...)` (optional `recentLogs:`/`favoriteFoodIds:` give an affinity boost; `isPersonalised(...)` flags boosted meals) |
| Personalised recs / most-logged foods | `Domain/FoodAffinity.swift` → `mostLoggedIds(_:days:limit:end:)` / `frequencyByFoodId(_:days:end:)` (30-day window over foodIds incl. ingredients); fed into `SuggestedMeals.ranked` from `NutritionView` |
| Meal-logging streak (consecutive days) | `Domain/Streaks.swift` → `loggingStreak(...)`; copy `EncouragementEngine.mealStreakMessage(days:mode:)` (3/7/14/30/60/100); toast `ToastCenter.mealStreak(...)`; chip in `NutritionView` |
| Circuit heart-health micros (fiber floor + sodium/sugar/satfat caps) | `Components/HeartHealthCard.swift` (Circuit-only; no-op if targets have no caps) — rendered in `NutritionView` after the totals card |
| Remaining macros / headroom under caps | `Domain/MacroBudget.swift` → `remaining(totals:targets:)` returns `RemainingMacros` (caps = room left, negative when over; fiber = signed distance to floor; all four nil in Build) |
| Personal meal templates | `Domain/Models.swift` (`SavedMealTemplateDTO`) + `Data/PersistenceModels.swift` (`SavedMealTemplateModel`) |
| Weekly nutrition trend | `Domain/NutritionHistory.swift` + `Features/Nutrition/NutritionTrendSheet.swift` |
| Calorie math | `Domain/Targets.swift` only |
| Target rationale copy | `Domain/TargetRationale.swift` (spell out acronyms; "cal" not "kcal"); Circuit micro copy `fiberWhy`/`sodiumWhy`/`addedSugarWhy`/`saturatedFatWhy(for:)` (used by `HeartHealthCard` info sheet) |
| **Today / Steps** | |
| Move card (steps row + 2×3 cols) | `Features/Today/MoveCard.swift` — `stepsRow` on top (full width: value + goal + inline bar); row 1: Apple Total · Our Total Estimate · Training Only; row 2: Distance · Flights · Heart Rate. Steps leads because the rows below are largely derived from it. Single `metricColumn` helper (uniform 22pt value font, no differential shrink). `activityRow(kcal:)` takes `Int` |
| Steps (Build) | `Features/Today/MoveCard.swift` → `stepsRow`. There is deliberately **no separate steps card** on Today any more — the Move card is the only place steps live, so its row carries both controls the old `StepsCard` owned: the count/goal chip opens `stepsGoalPickerSheet` (writes `AppStorage "stepsGoal.<uuid>"`), the rest of the row opens `StepsInfoSheet`. Move only renders when `profile.healthGranted`; ungranted Build shows `connectHealthCard` at the top of `TodayView` instead |
| Steps + cardio (Circuit, on Today) | `Features/Today/StepsCardioCard.swift` — rendered by `TodayView`, not under `Workouts/Circuit/`. Circuit keeps its own steps card because it also carries cardio logging and the weekly view; it has its own goal picker (daily + days/week) writing the same `AppStorage` key |
| Water tracker (presets + day-streak) | `Domain/Water.swift` (presets Sip 4 / S 8 / M 16 / L 32 oz; `streak(_:goalFlOz:end:)`) + `Features/Today/WaterCard.swift` (`AppStorage "waterGoalFlOz.\(profileId)"`; streak chip) |
| Water quick-log (app-wide FAB) | `Features/Today/WaterQuickLogButton.swift` — tap = repeat last (`AppStorage "waterLastFlOz.\(profileId)"`), press-and-hold = dim screen + radial preset picker; logs via `Repos.addWater`. Overlaid in `App/RootView.swift` |
| Step milestones / goals | `Domain/Movement.swift` (`defaultStepMilestones`). Per-profile override: `AppStorage "stepsGoal.\(profileId.uuidString)"` |
| Today burn estimate | `Domain/DailyBurn.swift` → `metEstimate` |
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
| Show/hide trackers | `Features/Progress/EditTrackersSheet.swift` — `AppStorage "progressStats.\(profileId)"` |
| Training volume | `Features/Progress/ProgressView.swift` → `StatKind.trainingVolume` |
| Calorie intake vs activity burn | `Domain/EnergyBalance.swift` → `byDay(...)` / `averages(_:)` (intake = `DailyTotals`; burn = `DailyBurn.metEstimate`, walks excluded). Card `energyBalanceCard` (both modes) in `Features/Progress/ProgressView.swift` → detail `Features/Progress/EnergyBalanceDetailSheet.swift` (Charts: intake bars vs burn line + target rule). Tests: `OurFitnessTests/EnergyBalanceTests.swift` |
| Training history (cross-day) | `Domain/TrainingHistory.swift` → strength grouping + `TrainingHistorySheet` in `Features/Progress/ProgressView.swift` for strength, live, cardio, and Pilates sessions. Tests: `OurFitnessTests/TrainingHistoryTests.swift` |
| Tracker display order | alphabetical by `StatKind.title` at the two render sites (`visibleStats` + `EditTrackersSheet` ForEach); never reorder the enum (persisted CSV) |
| **Settings / Profile** | |
| Edit vitals | `Repos.updateVitals` + `Features/Settings/SettingsView.swift` → `EditVitalsSheet` |
| Switch mode | `Repos.updateMode` + `Features/Settings/SettingsView.swift` → `ModeSwitchSheet` |
| App tab layout | `App/RootView.swift` — both modes: Today / Meals / Train / Reminders / Progress. `WorkoutsView` is mode-aware (Build = lift list + rep counter; Circuit = Pilates + movement quick-log). Today mirrors Build in both (macros/move/water/steps + food log; Circuit adds cardio) |
| Profile avatar | `Components/ProfileAvatar.swift` |
| Units (metric ↔ imperial) | `Domain/Units.swift` — canonical storage IMPERIAL; convert only at UI boundary |
| Sync current weight | `Repos.syncCurrentWeight` — called after progress log, HK sync, TodayView task |
| **HealthKit** | |
| New HK metric | `Services/HealthKitService.swift` + `Data/PersistenceModels.swift` |
| Sync Health into logs | `HealthKitService.syncFromHealth` (deduped upsert; re-points `profile.weightLb`) |
| **UI / Components** | |
| Button variants (5 total) | `Components/TactileButtonStyle.swift` — never add a 6th |
| Circular progress | `Components/ProgressRing.swift` — never inline `Circle().trim` |
| Progress-fill replay (sweep from 0 on appear) | `Components/VisibilityReveal.swift` → `.revealOnAppear($reveal)` — resets to 0 on scroll-out, springs to full on re-entry. Used by `ProgressBar` + `MacroQuadGrid` (`pct * reveal`) |
| Haptics | `Services/Haptics.swift` |
| Toast | `Services/ToastCenter.swift` + `Components/ToastView.swift` |
| Scroll haptics | `Services/Haptics.swift` → `.scrollHapticTicks()` on top-level tab `ScrollView`s |
| Freshness timestamp | `Domain/Freshness.swift` → `label(for:now:staleAfter:)` |
| Plain-English muscle names | `Domain/ExerciseInfo.swift` → `plainName(forMuscle:)` / `muscleGlossary` |
| **Schema / Data** | |
| Schema migration | `Data/Schema.swift` — current SchemaV7. Additive (new optional field / entity) = automatic. Structural = `.custom` stage. |

---

## Calorie math

Formula: `kcal = MET × bodyWeightKg × hours` (Ainsworth 2011).

| Activity | MET |
|---|---|
| Steps (3.5 mph) | 4.3 |
| Pilates | 3.0 |
| Resistance | 4.0–8.0 (see `Domain/ExerciseInfo.swift`) |
| Isometric hold | 3.8 default |
| Cardio with load | 4.5 |
| Live sessions | 2.8–11.8 (see `Domain/ActivityCatalog.swift`) |

Never hardcode kcal/rep — always MET × weight × time.

---

## Tech stack (locked)

SwiftUI (iOS 17+) · SwiftData · HealthKit · Swift Charts · XCTest · XcodeGen (`project.yml`) · Fastlane · GitHub Actions · No backend.

---

## Data model

Append-only logs. Derived figures never stored. DTOs in `Domain/Models.swift`; `@Model` classes in `Data/PersistenceModels.swift` with `snapshot` adapters; CRUD in `Data/Repositories/Repositories.swift`. Writes return success (Bool or optional DTO); callers must check before showing success or dismissing. `RepositoryWrite` saves explicitly, rolls back failures and re-fetches affected models to restore retained UI values, and posts success/failure notifications. Profile creation and Circuit seeding share a commit boundary.

Key entities: `ProfileDTO`, `ExerciseDTO` (`isIsometric`), `WorkoutSetDTO` (`holdSeconds?`), `FoodLogEntryDTO` (`ingredients?`), `BodyMetricDTO`, `HealthMarkerDTO`, `StepCountDTO`, `PilatesSessionDTO`, `CardioSessionDTO`, `WaterEntryDTO`, `ActivitySessionDTO`, `SavedMealTemplateDTO`, `ReminderGroupDTO`, `ReminderDTO`, `ReminderEventDTO`.

**HealthKit crash traps (caused SIGABRT in build 37):**
- Authorization configuration errors have raised uncatchable `NSException` — call ONLY from an explicit phone Connect flow or watch Start-workout action. Never from `.task`/`.onAppear`.
- Phone `readTypes`/`writeTypes` contain quantity types; preserve the correlation-type crash guard (e.g. blood pressure). The watch also requests `HKObjectType.workoutType()` in its write set for `HKWorkoutSession` recording.

LDL/HDL/cholesterol/A1c not from Apple Health (lab-only) — manual entry.

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

- **Local Mac (since 2026-08-08):** Xcode 26.6 / Swift 6.3.3 / XcodeGen 2.46 on an M5 Pro. Build and test **locally** — never push to CI to find out whether Swift compiles.
  ```bash
  set -o pipefail
  xcodegen generate    # only after editing project.yml
  xcodebuild -project OurFitness.xcodeproj -scheme OurFitness \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E '(error:|BUILD)'
  ```
  `compile.yml` still runs on push as a clean-room check; a CI-only failure means environment drift, not a Swift error. `testflight.yml` remains the shipping lane — its `Run tests` step is **tag-only** (`if: startsWith(github.ref, 'refs/tags/')`), because `compile.yml` already ran the same suite on the push, but does NOT trigger on tags. Don't make it unconditional again: that's ~4 min of a ~13 min ship re-answering a question already answered. Do keep the tag condition — a `v*` release has no other gate — local archive is now possible too ([docs/setup.md](docs/setup.md) → "Simplifying signing").
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

Read [docs/audit-handoff.md](docs/audit-handoff.md) before continuing this audit.
Update it at meaningful checkpoints and before usage exhaustion; record unverified
edits explicitly. Update affected docs in the same milestone commit.

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

- [README.md](README.md) — setup, XcodeGen, CI, secrets
- [docs/ci-history.md](docs/ci-history.md) — incident narratives behind CI rules
- [docs/setup.md](docs/setup.md) — one-time setup, secrets, daily loop
- [docs/RepCheck.md](docs/RepCheck.md) — friction-free logging UX bar
- [docs/nutrition-plan-research.md](docs/nutrition-plan-research.md) — Build nutrition spec
- [docs/app-expansion.md](docs/app-expansion.md) — Phase 2/3 roadmap (iCloud sync, store polish)
- [docs/live-activity-setup.md](docs/live-activity-setup.md) — widget signing checklist
- [docs/watch-app-setup.md](docs/watch-app-setup.md) — watch companion app signing checklist
- [docs/medication-reminders-plan.md](docs/medication-reminders-plan.md) — medication logging spec (the feature as shipped; safety wording rules in §12/§16 are binding)

> `docs/encouragement-system-plan.md`, `health-tracking-ui-plan.md`, and `activity-and-ai-expansion-research.md` are dated design specs / research — forward-looking or only partly shipped. This file and the code are authoritative when they disagree.
