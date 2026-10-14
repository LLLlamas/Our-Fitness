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
  Domain/       ← PURE Swift. No SwiftUI/SwiftData. Fully unit-tested.
  Data/         ← SwiftData @Model classes + Repositories/
  Services/     ← HealthKit, Theme, Haptics, ToastCenter
  Features/     ← Onboarding, Today, Nutrition, Workouts (shared Train tab; Circuit-mode cards under Circuit/ folder), Progress, Settings
  Components/   ← ProgressBar, ProgressRing, Card, AnimatedNumber, TactileButtonStyle…
_stashed/       ← Outside build target; pending rework
OurFitnessTests/ ← Hostless XCTest for Domain/* only
project.yml     ← XcodeGen source of truth; .xcodeproj gitignored
```

---

## Hard architectural rules

1. `Domain/` never imports `SwiftData` or `SwiftUI`.
2. `Features/` uses repositories or `@Query` — never opens the container directly.
3. **Per-profile `@Query` must predicate-scope** (`#Predicate { $0.userId == uid }`) — never `.filter` client-side. See `TodayView`, `NutritionView`, `ProgressTabView`, `WorkoutsView`.
4. HealthKit only through `Services/HealthKitService.swift`.
5. `.swift` filenames unique in target. All `@Model` classes in `Data/PersistenceModels.swift`.
6. `OurFitnessTests` is hostless: blank `TEST_HOST`/`BUNDLE_LOADER`, no `@testable import OurFitness`.

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
| Live sessions (timer) | `Features/Workouts/LiveSessionCard.swift` + `Domain/LiveSessionState.swift` + `Services/LiveSessionService.swift`. `ActivityTile` / `IntensitySection` in that file are shared by `ActivityPicker` (start live) and `LogPastSessionSheet` (log after the fact) — single definitions, don't re-copy |
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
| Meal log UI + day history + past-day logging | `Features/Nutrition/NutritionView.swift` — day strip (last 7 days, dot = has logs) + calendar `DayPickerSheet` for any earlier day; trend sheet day detail → "Open this day in the log" |
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
| Move card (2×3 cols) | `Features/Today/MoveCard.swift` — row 1: Apple Total · Our Total Estimate · Training Only; row 2: Distance · Flights · Heart Rate. Single `metricColumn` helper (uniform 22pt value font, no differential shrink). `activityRow(kcal:)` takes `Int`. Burn figures come from `DailyBurn.breakdown` (never re-derive MET math or the step-overlap exclusions here — `countedCardio` / `countedActivities` read `DailyBurn`'s sets); unit conversions via `Units.kgPerLb` / `Units.kmPerMile`; the 7 column info sheets sit on `Components/InfoSheet.swift` |
| Steps card (both modes, Today only) | `Features/Today/StepsCard.swift` — one mode-aware card: Build = hero count + `ProgressBar`; Circuit = `ProgressRing` + projection + pace-vs-yesterday + 7-day strip + week-to-date active cal / exercise min. One goal-picker sheet (shared `Components/GoalPickerSheet.swift`; days/week wheel is Circuit-only) + one info sheet (shared `Components/InfoSheet.swift`). Goal keys live in `StepsGoalPrefs` in the same file. Never add a second steps card |
| Water tracker (presets + day-streak) | `Domain/Water.swift` (presets Sip 4 / S 8 / M 16 / L 32 oz; `total(_:on:)`, `streak(_:goalFlOz:end:)`) + `Features/Today/WaterCard.swift` (streak chip = shared `Components/StreakChip.swift`) |
| Log water (shared path — use for ANY new water surface) | `Features/Today/WaterLogging.swift` → `WaterLog.add(_:for:on:context:lastFlOz:unitSystem:toasts:)` — one write + remembers the repeat-last amount + one copy of the toast; also owns the `waterGoalFlOz.\(profileId)` / `waterLastFlOz.\(profileId)` AppStorage keys. No explicit haptic (ToastCenter.show fires one) |
| Water quick-log (app-wide FAB) | `Features/Today/WaterQuickLogButton.swift` — tap = repeat last, press-and-hold = dim screen + radial preset picker; logs via `WaterLog.add`. Overlaid in `App/RootView.swift` |
| Step milestones / goals | `Domain/Movement.swift` (`defaultStepMilestones`). Per-profile override: `AppStorage "stepsGoal.\(profileId.uuidString)"` |
| Today burn estimate | `Domain/DailyBurn.swift` → `metEstimate` (day total) / `breakdown(...)` → `Breakdown` (per-source split: steps, sets, cardio, pilates, activities; `trainingKcal` excludes steps; `total` == `metEstimate`). Net of resting — see Calorie math. The step-overlap exclusions live here as `stepOverlappingCardio` / `stepOverlappingActivityIds`. Tests: `OurFitnessTests/DailyBurnTests.swift` |
| Encouragement / milestones | `Domain/EncouragementEngine.swift` + `Domain/EncouragementMessage.swift` + `Components/ProjectionBar.swift` |
| Meal/water nudges | `Domain/EncouragementEngine.swift` → `mealLoggingNudge` / `waterNudge`; wired in `Features/Today/TodayView.swift` |
| **Progress** | |
| Add health marker kind | `Domain/Models.swift` (`HealthMarkerKind`) + `Domain/HealthRanges.swift` (exhaustive switches) + `Features/Progress/ProgressView.swift` |
| Show/hide trackers | `Features/Progress/EditTrackersSheet.swift` — `AppStorage "progressStats.\(profileId)"`. Default set = `StatKind.isRelevant(for:)`, which is ONLY the trackers the app can fill in itself (weight / steps / training volume; + resting HR + BP in Circuit); everything needing calipers, a tape, a cuff, or a lab starts hidden. `ProgressTabView.enabledSet(body:markers:)` then re-adds any tracker that already `hasLoggedData`, so shrinking the default never hides a card someone was filling in. A stored CSV always wins. |
| Stat detail sheet (chart + entries + log) | `Components/StatDetailSheet.swift` — ONE sheet for every tracker. Metric-specific bits come in as slots (`headline`, `chartOverride`, `logOverride`, `footer`) plus `validate` / `showsEntries` / `minChartPoints` / `detents`; `StatDetailRow` is the shared label/value row. Weight (wheel picker), Body fat, BMI, and Blood pressure in `ProgressView.swift` are all thin hosts over it — never write another bespoke detail sheet |
| Training volume | `Domain/TrainingHistory.swift` → `setsInWeek(_:weeksAgo:now:)` / `weeklySetCounts(_:weeks:now:)` (Monday ISO weeks), surfaced via `StatKind.trainingVolume` in `Features/Progress/ProgressView.swift`. Tests: `TrainingHistoryTests` |
| Weeks ("this week") | `Domain/Dates.startOfISOWeek(_:weeksAgo:)` — Monday-anchored, the app-wide definition. Never `Calendar.current` week components (Sunday-based in the US). `Domain/Movement.swift`, `Features/Workouts/RepCounter.swift`, and `Circuit/CardioLogCard.swift` still build their own Monday calendars — migrate them to this helper when touched. Tests: `DatesTests` |
| Calorie intake vs activity burn | `Domain/EnergyBalance.swift` → `byDay(...)` / `averages(_:)` (intake = `DailyTotals`; burn = `DailyBurn.metEstimate` — active-only, step-overlapping sessions excluded). Card `energyBalanceCard` (both modes) in `Features/Progress/ProgressView.swift` → detail `Features/Progress/EnergyBalanceDetailSheet.swift` (Charts: intake bars vs burn line + target rule). Tests: `OurFitnessTests/EnergyBalanceTests.swift` |
| Training history (cross-day) | `Domain/TrainingHistory.swift` → `sessions(sets:exercises:)` strength grouping + `TrainingHistorySheet` in `Features/Progress/ProgressView.swift` for strength, live, cardio, and Pilates sessions. Tests: `OurFitnessTests/TrainingHistoryTests.swift` |
| Tracker display order | alphabetical by `StatKind.title` at the two render sites (`visibleStats(in:)` + `EditTrackersSheet` ForEach); never reorder the enum (persisted CSV) |
| Latest value of a health marker | `Trends.markerSeries(_:kind:).last?.value` — via the single `latestMarkerValue` helper in `ProgressView.swift`. Don't re-filter/sort markers inline |
| BMI / body-fat thresholds | `Domain/BodyComposition.swift` → `bmiCategory` / `bodyFatCategory` own every boundary. The Progress sheets read labels from them (`bmiIsHealthy`, the probe-value range tables); never restate 18.5 / 25 or a body-fat band in a view |
| **Settings / Profile** | |
| Edit vitals | `Repos.updateVitals` + `Features/Settings/SettingsView.swift` → `EditVitalsSheet` |
| Switch mode | `Repos.updateMode` + `Features/Settings/SettingsView.swift` → `ModeSwitchSheet` |
| App tab layout | `App/RootView.swift` — both modes: Today / Meals / Train / Progress. `WorkoutsView` is mode-aware (Build = lift list + rep counter; Circuit = Pilates + movement quick-log). Today mirrors Build in both (macros/move/water/steps + food log; Circuit adds cardio) |
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
| Schema migration | `Data/Schema.swift` — current SchemaV6. Additive (new optional field / entity) = automatic. Structural = `.custom` stage. |

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

Append-only logs. Derived figures never stored. DTOs in `Domain/Models.swift`; `@Model` classes in `Data/PersistenceModels.swift` with `snapshot` adapters; CRUD in `Data/Repositories/Repositories.swift`.

Key entities: `ProfileDTO`, `ExerciseDTO` (`isIsometric`), `WorkoutSetDTO` (`holdSeconds?`), `FoodLogEntryDTO` (`ingredients?`), `BodyMetricDTO`, `HealthMarkerDTO`, `StepCountDTO`, `PilatesSessionDTO`, `WaterEntryDTO`, `ActivitySessionDTO`, `SavedMealTemplateDTO`.

**`CardioSessionDTO` is legacy, read-only.** Nothing writes it any more (the card that did was unreachable and is gone); cardio is logged as an `ActivitySessionDTO` via `LogPastSessionSheet`. The read paths stay so installs that logged cardio in an older build still see and can delete those rows: `MoveCard` (burn + breakdown), `ProgressView` (Training history row + delete, energy balance), `DailyBurn.metEstimate`, `EnergyBalance.byDay`. Both paths exclude walks *and runs* so steps aren't double-counted. Note rows logged before the net-MET fix still carry their old gross `caloriesEst`. `Repos.logCardio` / `Repos.listCardio` were callerless and have been deleted — only `Repos.deleteCardioSession` remains. To write a cardio row again you'd construct `CardioSessionModel(snapshot:)` directly, but prefer `ActivitySessionDTO`.

**HealthKit crash traps (caused SIGABRT in build 37):**
- `requestAuthorization` raises uncatchable `NSException` — call ONLY from explicit user Connect flow. Never from `.task`/`.onAppear`.
- Add only quantity types to `readTypes`/`writeTypes` — correlation types (e.g. blood pressure) crash auth.

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

- **Local-first:** build/test locally in Xcode or `bundle exec fastlane ios tests` (after `xcodegen generate`); `compile.yml` on push + `testflight.yml` remain as the backup gate/release safety net. TestFlight can also be released locally via fastlane — see [docs/setup.md](docs/setup.md).
- **Tests hostless:** `OurFitnessTests` compiles `Domain/` directly. No `@testable import`. `scripts/validate-ci-invariants.sh` enforces.
- **Never bare `Date()` in streak/weekly tests** — pin `now` to fixed mid-week (e.g. `2026-05-27T12:00:00Z`), thread through fixture + function.
- **Signing:** match repo `LLLlamas/Our-Fitness-Certs`, readonly CI. Manual App Store profile `OurFitness AppStore` → base64 → `APPSTORE_PROFILE_BASE64`. Widget (`com.ourfitness.app.widgets`) needs its own profile.
- **XcodeGen:** never `info:` or `entitlements:` blocks on target — use `INFOPLIST_FILE`/`CODE_SIGN_ENTITLEMENTS` build settings only.
- **Entitlement missing?** Ladder: latest build → App ID capability → profile has it → `.xcarchive` → IPA.
- **Xcode 26:** version-sorted glob (not hardcoded). Build dest: `platform=iOS Simulator,name=iPhone 17`. All 4 orientations in `Info.plist`.
- Secrets: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_API_*`, `KEYCHAIN_PASSWORD`, `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION`, `APPSTORE_PROFILE_BASE64`, `APPSTORE_WIDGET_PROFILE_BASE64`

---

## References

- [README.md](README.md) — getting started, local build + test
- [docs/ci-history.md](docs/ci-history.md) — incident narratives behind CI rules
- [docs/setup.md](docs/setup.md) — one-time setup, secrets, daily loop
- [docs/RepCheck.md](docs/RepCheck.md) — friction-free logging UX bar
- [docs/nutrition-plan-research.md](docs/nutrition-plan-research.md) — Build nutrition spec
- [docs/app-expansion.md](docs/app-expansion.md) — Phase 2/3 roadmap (iCloud sync, store polish)
- [docs/live-activity-setup.md](docs/live-activity-setup.md) — widget signing checklist
- [docs/health-data-audit.md](docs/health-data-audit.md) — **read before changing any health/fitness number.** What was wrong and fixed, what is verified correct, and the open sourcing questions that must not be "fixed" without checking the actual guideline

> `docs/encouragement-system-plan.md`, `health-tracking-ui-plan.md`, and `activity-and-ai-expansion-research.md` are dated design specs / research — forward-looking or only partly shipped. This file and the code are authoritative when they disagree.
