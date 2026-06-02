# Our-Fitness — Foundation (iOS / SwiftUI)

Native iOS app, now targeting an App Store release (was a small TestFlight circle). Two modes: **Build** (gain mass, fuel hoops) and **Circuit** (drop weight, fix cardiovascular markers). Show up, log honestly, let the numbers tell the truth.

> **Rename note (2026-05):** *Reset* → *Circuit*. Swift symbol `Mode.circuit`; SwiftData raw value pinned to `"reset"` for back-compat. Food library, scoring, and cap surfaces stashed under `_stashed/` pending rework.
>
> **App Store expansion (2026-05):** Collapsed to **one profile per install** (the device is one person) — the old shared-device `ProfileSwitcher` / "Whose device is this?" picker is gone, replaced by `Components/ProfileAvatar.swift` (identity badge → Settings). First launch still routes to `ProfileCreationView`. **Mode is now changeable at will** in Settings (was immutable post-creation). The store layer keeps its per-profile scoping (every log carries `userId`/`profileId`), so multi-profile is dormant, not deleted. Full roadmap incl. iCloud/CloudKit sync (Phase 2) and store polish (Phase 3) in [app-expansion.md](app-expansion.md).

---

## Modes

| | Build | Circuit |
|---|---|---|
| Calories | TDEE + 400–600 | TDEE − 300–500 |
| Protein g/lb | ~1.0 | 1.0–1.2 |
| Steps/day | 8,000 | 10,000 (primary lever for BP/insulin/LDL) |
| Workouts | rep/set counter, isometric holds, user's own exercises | baby exercise quick-log, pilates, steps |

**Circuit** is parenting-movement-flavored. Auto-seeds **Lifted Baby** (30 lb / reps), **Lifted Stroller** (25 lb / reps), **Carried Baby** (30 lb / duration). `Domain/CalorieEstimator.swift` converts reps, seconds, or minutes against a known `loadLb` into kcal (MET × kg × hours). Don't hardcode kcal/rep — compute from MET.

**Isometric exercises** (plank, dead hang, wall sit) use `isIsometric: true` on `ExerciseDTO`. The rep counter becomes a countdown timer; each completed hold saves a `WorkoutSetModel` with `reps = 1` and `holdSeconds = N`. Calorie estimate: `CalorieEstimator.caloriesForIsometric(seconds:met:bodyWeightLb:)`.

`MacroTargets.{sodiumMgMax,addedSugarGMax,saturatedFatGMax,fiberGMin}` populate for Circuit but no UI renders them — dormant for future revival.

---

## Codebase map

```
OurFitness/
  App/          ← @main, ModelContainer wiring, root shell
  Domain/       ← PURE Swift. No SwiftUI/SwiftData. Fully unit-tested.
  Data/         ← SwiftData @Model classes + Repositories/
    Seed/       ← Seeder.seedAll is a no-op; profiles are user-created
  Services/     ← HealthKit, Theme, Haptics, ToastCenter
  Features/     ← Onboarding, Today, Nutrition, Workouts (Build + Circuit/), Progress, Settings
  Components/   ← ProgressBar, ProgressRing, Card, Banner, AnimatedNumber, TactileButtonStyle…
_stashed/       ← Outside build target; pending rework
OurFitnessTests/ ← Hostless XCTest for Domain/* only
fastlane/       ← tests, compile, sync_signing, beta
scripts/        ← validate-ci-invariants.sh, generate-icon.sh
.github/workflows/ ← compile.yml (every push), testflight.yml (manual / v* tag)
project.yml     ← XcodeGen — source of truth; .xcodeproj gitignored
```

### Stashed (excluded from build target)
`_stashed/` — seed food libraries, Suggestions.swift, Score.swift, CapBar.swift, ScoreTests.swift.

---

## Hard architectural rules

1. `Domain/` never imports `SwiftData` or `SwiftUI`. Pure structs/functions only.
2. `Features/` never opens the SwiftData container directly — use repositories or `@Query`.
3. **Per-profile `@Query` must be scoped in the predicate, not filtered client-side.** Give the view an `init(profile:)` that builds `Query(filter: #Predicate { $0.userId == uid })` (or `profileId`) — see `TodayView`, `NutritionView`, `ProgressTabView`, `WorkoutsView`. Never `@Query` everything and `.filter` in a computed property; it leaks across profiles and defeats the store-level isolation that iCloud sync (Phase 2) depends on.
4. HealthKit access only through `Services/HealthKitService.swift`.
5. `.swift` filenames within the target must be unique. `@Model` classes live in `Data/PersistenceModels.swift` — don't name any new file `Models.swift`.
6. `OurFitnessTests` is hostless: blank `TEST_HOST`/`BUNDLE_LOADER`, no `@testable import OurFitness`.

---

## Where to touch for common changes

| Goal | Files |
|---|---|
| Add a per-profile exercise | `Repos.createExercise` — pass `isIsometric: true` for plank/hold exercises |
| Isometric hold timer UI | `Features/Workouts/RepCounter.swift` → `IsometricTimerView` |
| Isometric calorie math | `Domain/CalorieEstimator.caloriesForIsometric(seconds:met:bodyWeightLb:)` |
| Rep counter (non-isometric) | `Features/Workouts/RepCounter.swift` → `RepCounterView` |
| Delete a logged set / an exercise | `Repos.deleteSet` / `Repos.deleteExercise` (cascade-deletes its sets) + `SetHistorySheet` in `Features/Workouts/WorkoutsView.swift` (clock icon on each exercise card) |
| Log a Pilates session | `Repos.logPilatesSession` + `PilatesSessionDTO` / `PilatesSessionModel` |
| Log a cardio session | `Repos.logCardio` + `CardioSessionDTO` / `CardioSessionModel` |
| Pilates weekly goal / streak | `Domain/Movement.swift` (`pilatesWeeklyStreak`) |
| Step-count milestone thresholds | `Domain/Movement.swift` (`defaultStepMilestones`) |
| Circuit "why this matters" copy | `Domain/Movement.swift` (`circuitFocusBlurb`) |
| Post-exercise recovery hint | `Domain/Movement.swift` (`postExerciseHint`, `postPilatesHint`, `namedParentingHint`) |
| Circular progress arc | `Components/ProgressRing.swift` — reuse, never inline `Circle().trim` |
| Per-profile steps goal override | `AppStorage` key `"stepsGoal.\(profileId.uuidString)"` |
| Water intake tracker (daily + weekly) | `Domain/Water.swift` (cup presets, aggregation over `WaterEntryDTO`) + `Features/Today/WaterCard.swift` (`@Query` of `WaterEntryModel`). `Repos.addWater` / `listWater` / `deleteWater`. Daily goal in `AppStorage` `"waterGoalFlOz.\(profileId)"`. ⓘ opens `WaterInfoSheet` (private in WaterCard) — personalized goal = ACSM base `0.5 oz/lb` + activity-level bonus, vs. current goal |
| Meal log natural language → nutrition | `Domain/FoodParser.swift` + `Domain/CommonFoods.swift` + `Domain/FoodDatabase.swift`. **Resolution order per chunk: curated `CommonFoods` wins (hand-tuned aliases/servings), then falls back to the bundled USDA `FoodDatabase` for breadth.** Public `FoodParser.parse(text:)` is unchanged; tests use `parse(text:database:)` to inject a DB without the bundle. |
| On-device AI meal parser (text → items, numbers stay deterministic) | `Services/MealParseService.swift` — Apple **FoundationModels** (Apple Intelligence), runtime-gated `if #available(iOS 26.0, *)` + `#if canImport(FoundationModels)` (deployment target is iOS 17, so degrade gracefully). `parse(_:) async -> [FoodParser.ExtractedItem]?` splits a casual sentence ("two eggs, a flat white and some sourdough") into distinct foods + best-guess quantities. **SAFETY (mirrors `ExerciseInsightService`): the model emits TEXT ONLY — never calories/macros. The `@Generable` shape has no nutrition fields; the prompt forbids nutrition numbers and inventing foods.** Numbers are resolved deterministically by handing the names back through `FoodParser.resolve(items:)` (DRY — same `CommonFoods`/`FoodDatabase` lookup + per-serving scaling as the string parser); an extracted name not in the DB is `unrecognized`, never fabricated. Wired into `NLMealLogSheet` (`Features/Nutrition/NutritionView.swift`): the instant string parser (`FoodParser.parse`) runs on every keystroke and stays the only path on iOS < 26 / no Apple Intelligence; on submit/end-editing `aiRefine()` tries the model and **falls back silently** to the string result on any failure. AI-parsed results show a "sparkles" Apple Intelligence attribution clarifying numbers come from the database. `FoundationModels` needs no entitlement; lives in `Services/` (Domain stays framework-free). `ExtractedItem` + `resolve(items:)` are pure in `Domain/FoodParser.swift` so they're hostless-testable (`OurFitnessTests/MealParseResolutionTests.swift`); the model call itself is iOS-26-SDK-only — verify on a Mac/device |
| Offline USDA food database (data + loader) | `Domain/FoodDatabase.swift` — pure Foundation; indexes the bundled `OurFitness/Resources/usda-foods.json` (USDA FoodData Central, public-domain/CC0) by name+aliases. **Offline-first, no runtime network.** `FoodDatabase.shared` loads from `Bundle.main` and **degrades gracefully to empty when the resource is absent** (e.g. the hostless test target ships no bundle) — never crashes. The repo ships a small hand-verified SEED; the full dataset is regenerated by `scripts/build-food-db.py` (run on a Mac/CI with network — downloads USDA Foundation Foods + SR Legacy, prunes to whole foods + the fields we use, emits the JSON). Resource is wired in `project.yml` under the OurFitness target's `resources:` AND excluded from `sources:` (don't add it to the test target — that's what keeps the loader's empty-fallback path exercised). Numbers are never invented — only real USDA values. |
| Add / update a common food | `Domain/CommonFoods.swift` (`CommonFoods.all`) — pick the right category array (grains/proteins/eggsAndDairy/vegetables/fruits/legumes/nutsAndFats/drinks/soups/preparedMeals/snacksAndSweets); aliases drive parser matching. Curated entries always shadow the USDA DB by alias, so put hand-tuned high-frequency foods here; let the generated USDA DB cover the long tail. |
| Curated meal suggestions | `Domain/SuggestedMeals.swift` |
| Meal / food detail modal (info + portion adjust) | `Features/Nutrition/NutritionView.swift` → `MealDetailSheet` (suggested meals), `FoodDetailSheet` (library foods), `LoggedEntryDetailSheet` (tap a logged row). Shared `MacroChip` |
| Weekly+ nutrition history | `Domain/NutritionHistory.swift` (per-day totals, calorie series from the persisted log) + `weeklyNutritionCard` in NutritionView + `Features/Nutrition/NutritionTrendSheet.swift` |
| Change calorie math | `Domain/Targets.swift` only |
| Personalized "why your target is what it is" copy | `Domain/TargetRationale.swift` — pure, tested. Turns a profile (+ latest markers) into plain-language rationale **anchored to the user's own numbers** (BMR → TDEE/maintenance → surplus/deficit → goal; protein g/lb; steps; per-marker meaning) tied to the Mode goal (Build = slowly add muscle; Circuit = lose fat + improve heart-health numbers). Science is deliberately softened to current evidence (citations inline). Consumed by `MacroInfoSheet` (`Components/MacroQuadGrid.swift` — now takes `profile:`), `NutritionInsightSheet`, `StepsInfoSheet`/`CircuitStepsInfoSheet`, `StatDetailSheet`'s `personalNote`, and `BPDetailSheet`. Copy rule: spell out acronyms ("blood pressure" not "BP"), say "cal" not "kcal" |
| Plain-English muscle names (layman glosses) | `Domain/ExerciseInfo.plainName(forMuscle:)` / `plainMuscleList(_:)` — appends a "(what/where it is)" gloss to anatomical names (e.g. *Rectus abdominis* → the "six-pack" muscle). Applied at display in `BuildExerciseInfoSheet` (RepCounter) + Circuit `ExerciseInfoSheet` (BabyExercisesCard). Add new terms to `muscleGlossary` |
| On-device AI insights for user-added exercises | `Services/ExerciseInsightService.swift` — Apple **FoundationModels** (Apple Intelligence), runtime-gated `if #available(iOS 26.0, *)` + `#if canImport(FoundationModels)` (deployment target is iOS 17, so it must degrade gracefully). Generates plain-English muscles + benefits ONLY for exercises with no curated entry (`ExerciseInfo.hasCuratedMeta(for:)==false` **and** `Movement.hasNamedHint(for:)==false`); known/seeded exercises keep their cited copy. **Descriptive only — never touches MET/calorie math** (logged calories stay deterministic). Prompt forbids medical claims + fabricated citations (implementation-plan.md §9: "AI never prescribes; it suggests"). Result cached in UserDefaults (`aiExerciseInsight.v1.*`). Surfaced with a "sparkles" Apple Intelligence attribution + not-medical-advice disclaimer in `BuildExerciseInfoSheet` (RepCounter) and Circuit `ExerciseInfoSheet` (BabyExercisesCard). FoundationModels needs no entitlement; it's in `Services/` (not Domain — Domain stays framework-free). API call (`LanguageModelSession`/`respond(to:generating:)`/`@Generable`) is iOS-26-SDK-only — verify on a Mac/device |
| Metric ⇄ Imperial units | `Domain/Units.swift` — pure conversion + display/parse helpers (lb↔kg, in↔cm, height ft-in vs cm, fl oz↔mL, mi↔km), fully unit-tested. **Canonical storage stays IMPERIAL** (lb/inches/fl oz/miles) — convert ONLY at the UI boundary: `format*` for display, `parse*`/`*ToLb`/`*ToInches`/`*ToMiles` to return to canonical before persisting. Chosen system lives in `@AppStorage(UnitSystem.storageKey)` ("unitSystem", app-wide, default `.imperial`). Toggle UI = "Units" section in `SettingsView`. Views that read it: `ProfileCreationView`, `EditVitalsSheet`/Settings Body row, `WaterCard`/`WaterInfoSheet`, `ProgressView` (weight/waist/body-fat lb breakdown + `StatKind.unit(system:)`/`displayValue(...system:)`/`series(...system:)`/`entries(...system:)`/`placeholder(system:)`), `RepCounter` weight-lifted, `SetHistorySheet`, `BabyExercisesCard` load, `CardioLogSheet` distance. **Energy stays "cal" in BOTH systems — no kJ.** MET-formula explainer strings in `MoveCard`/`StepsCard` stay scientific (kg) by design — the Ainsworth Compendium defines MET math in kg. `TargetRationale` weekly-rate / protein-per-pound prose is intentionally NOT converted (colloquial English, tested copy). |
| Switch a profile's mode at will | `Repos.updateMode(_:profileId:to:)` (recomputes targets, seeds Circuit exercises) + `ModeSwitchSheet` in `Features/Settings/SettingsView.swift` |
| Edit profile vitals (weight/height/age/sex/activity) | `Repos.updateVitals(_:profileId:...)` (writes the changed fields, recomputes targets) + `EditVitalsSheet` in `Features/Settings/SettingsView.swift` (Settings → Body row). All recommendations read `profile.weightLb` etc., so editing here re-derives calorie/protein/water/burn targets app-wide |
| Keep `profile.weightLb` current (the single source recommendations read) | `Repos.syncCurrentWeight(_:profileId:weightLb:)` re-points the profile at the latest known body weight + recomputes targets. Called after a Progress-tab weight log, after `HealthKitService.syncFromHealth` (passing the authoritative HK sample), and in `TodayView`'s task (self-heals older installs). `profile.weightLb` is the live current weight, NOT a frozen onboarding snapshot — never read a stale weight from elsewhere |
| Profile identity / open Settings | `Components/ProfileAvatar.swift` (one profile per install; no switcher) |
| Mode display copy / opposite mode | `Domain/Models.swift` (`Mode.blurb`, `Mode.toggled`) |
| New workout progression | `Domain/Progression.swift` strategy switch |
| Add a tracked health marker | `Domain/Models.swift` (`HealthMarkerKind`) + `Features/Progress/ProgressView.swift`. Adding a `HealthMarkerKind` case also requires updating the exhaustive switches in `Domain/HealthRanges.swift` (`status`, `context`) |
| Show/hide progress trackers | `Features/Progress/EditTrackersSheet.swift` (sliders icon on Progress). Per-mode defaults via `StatKind.isRelevant`; user overrides in `AppStorage` `"progressStats.\(profileId)"` (empty = defaults, `"none"` = all hidden, else CSV of raw values) |
| New HealthKit metric | `Services/HealthKitService.swift` + snapshot in `Data/PersistenceModels.swift` |
| Sync a Health metric into logs | `HealthKitService.syncFromHealth(profileId:ctx:)` (deduped upsert of body mass + body fat/waist → BodyMetric, resting HR/BP/glucose → markers; body mass also re-points `profile.weightLb` via `Repos.syncCurrentWeight`). Called from `TodayView`'s task/refresh when granted |
| Apple Health "Move" card (3 columns) | `Features/Today/MoveCard.swift`. Columns: Apple Energy (HK daily sum), Exercises (sets+cardio+pilates+live-sessions MET only, steps excluded to avoid double-count with Apple active energy), Heart Rate. Each column is a tappable button → its own per-column info sheet (`AppleEnergyInfoSheet`/`ExercisesInfoSheet`/`HeartRateInfoSheet`, built on shared `ColumnInfoScaffold`). `ExercisesInfoSheet` shows the full per-source MET breakdown (steps, strength, cardio, pilates, live sessions) + total + estimated fat burned + training sweat-loss. Data older than 7 days shows `"-"` / "need new data". Separate "as of" timestamp per column. Header ⓘ opens `MoveInfoSheet`. Use `HealthKitService.latestHeartRateWithDate()` / `latestActiveEnergySampleDate()` for timestamped reads |
| Today's MET burn estimate | `Domain/DailyBurn.metEstimate(steps:sets:cardio:pilates:activities:bodyWeightLb:)` — sums via `CalorieEstimator`; the `walking` live-activity is excluded (counted in steps) like cardio `.walk`; never hardcode kcal |
| Live Sessions (timed activity timer) | Entry: `LiveSessionCard` in `Features/Workouts/LiveSessionCard.swift` — placed atop `WorkoutsView` (Build) and `circuitContent` in `TodayView` (Circuit). Picker → live runner (big mm:ss vs. expected, `ProgressRing`, gentle over-time state, End / ±5 min). Timestamp-anchored: source of truth is `LiveSessionState.startDate` (`Domain/LiveSessionState.swift`, pure, tested), elapsed = now − start, so it survives backgrounding/kill; `TimelineView(.periodic)` only drives the on-screen tick. Persisted to UserDefaults + local end-notification in `Services/LiveSessionService.swift` (`LiveSessionStore` / `LiveSessionNotifier`). **Notification auth is requested ONLY from the explicit Start tap — never .onAppear/.task — and a denial never blocks the session** (mirrors the HealthKit crash-trap rule). NO background modes added. On finish, logs an `ActivitySessionDTO` via `Repos.logActivitySession`. Phase-2 TODO marker for an ActivityKit Live Activity sits at the start call site |
| Add / adjust a live-session activity (MET, icon) | `Domain/ActivityCatalog.swift` (`ActivityCatalog.all`) — Ainsworth 2011 METs, SF Symbol per entry. "Other" entry lets the user pick a custom MET via slider. `Repos.logActivitySession` / `listActivitySessions` / `deleteActivitySession`. Calorie math: `CalorieEstimator.caloriesForActivity(met:minutes:bodyWeightLb:)` |
| "As of …" timestamp label for a reading | `Domain/Freshness.label(for:now:staleAfter:)` — pure, injectable `now`, unit-tested. Returns nil for just-taken (<2 min) samples; same-day → time, older → abbreviated date. Used by `MoveCard`. The separate 7-day "need new data" gate lives in the view, not here |
| Steps health info sheet | Build: `StepsInfoSheet` in `Features/Today/StepsCard.swift` (calorie/fat formula, Tudor-Locke activity category, research bullets) — `StepsCard` takes `weightLb`/`mode`, shows `~N cal burned`. Circuit: `CircuitStepsInfoSheet` in `Features/Workouts/Circuit/StepsCardioCard.swift` (today's burn, "why 10k steps," cardio/LDL research). Both open via an ⓘ in the card header |
| Add / remove a Circuit movement | `Features/Workouts/Circuit/BabyExercisesCard.swift` — "+" in header opens `AddCircuitMovementSheet` (name/type/optional load → `Repos.createExercise`); `contextMenu` on each row → "Remove movement" → `Repos.deleteExercise` (cascade-deletes its sets) |
| Encouragement copy (milestones, projections) | `Domain/EncouragementEngine.swift` returns `EncouragementMessage` (`Domain/EncouragementMessage.swift`); pure copy + math, no SwiftUI/SwiftData. Toast bridges in `ToastCenter` (`stepMilestone`/`workoutMilestone`/`pilatesGoalHit`/`streakMilestone`/`macroGoalHit`/`macroApproaching`). Inline projection strip: `Components/ProjectionBar.swift`. Wired: step projection + mode-aware milestone in `StepsCardioCard`, rep projection + weekly-volume milestone in `RepCounter.swift` (`RepCounterView.saveSet`), protein/calorie goal+approaching toasts in `TodayView`. Copy rule: spell out acronyms ("blood pressure" not "BP", "muscle protein synthesis" not "MPS"); "cal" not "kcal" |
| Training volume progress tracker | `StatKind.trainingVolume` in `Features/Progress/ProgressView.swift` — weekly set count, both modes, file-scope helpers `setsThisWeek`/`setsLastWeek`/`trainingVolumeSeries`. Adding a new `StatKind` requires updating all exhaustive switches: `statusTint`, `save`, `displayValue`, `trendChip`, `series`, `entries`, `isRelevant`, `title`, `unit`, `placeholder`, `canLog`, `markerKind`, `detailSheet` |
| New tab | `App/RootView.swift` `Tab` enum + new folder under `Features/` |
| Schema change | `Data/Schema.swift` — new `VersionedSchema`. Never edit shipped schemas. Current: `SchemaV5` (adds `ActivitySessionModel` for Live Sessions). Additive changes (new entity / optional field) ride automatic migration with NO staged plan; structural changes need a `.custom` stage. |
| Add HealthKit permission | `OurFitness.entitlements` + `Info.plist` + `HealthKitService.requestAuth` |
| Button variant | `Components/TactileButtonStyle.swift` — reuse existing 5 variants |
| Haptic vocabulary | `Services/Haptics.swift` |
| Scroll haptic ticks | `Services/Haptics.swift` → `.scrollHapticTicks()` ViewModifier. Apply to the primary content `VStack` inside the `ScrollView` of every top-level tab view. Currently applied: `TodayView`, `WorkoutsView`, `NutritionView`, `NutritionTrendSheet`. Missing: `ProgressView`, `SettingsView`, `StepsCardioCard` (and any new tab views). |
| Toast accent / haptic pairing | `Services/ToastCenter.swift` |
| Appear-from-0 bar animation | `Components/ProgressBar.swift` (fills from 0 on `.onAppear` via `displayPct` state + spring delay 0.12 s). `Components/WeeklyBarStrip.swift` (bars scale from `0.01` to `1` with stagger on `appeared` state; re-triggers on `series` change via `onChange`). Both use explicit `withAnimation` — do not add a passive `.animation(..., value: pct)` on top. |
| Nutrition day selector (past-days log view) | `NutritionView.daySelector` — scrollable pill row (`recentDayKeys` = last 8 days reversed). `selectedDayKey` drives `totalsCard`, `logList`, and hides the log/suggestions buttons for past days. `LogRow(canDelete:)` is `false` for past days. |
| Nutrition goal insight sheet | `Features/Nutrition/NutritionView.swift` → `NutritionInsightSheet` (private). Opened via ⓘ in the meals header. Queries `HealthMarkerModel` per-profile (own `@Query` init), shows targets in plain English, 7-day avg vs target, mode-specific advice, dietary tips when LDL/BP markers are on file. |
| Nutrition trend — day drill-down | `Features/Nutrition/NutritionTrendSheet.swift` → recent rows are `PressableCard`s; tap opens `DayMealDetailSheet` with a per-meal breakdown + "view in log" action that calls `onSelectDay` closure and dismisses the sheet. |
| formatDayKey / dayKeyFormatter duplication (tech debt) | `NutritionView` and `NutritionTrendSheet` each contain an identical `dayKeyFormatter: DateFormatter` and `formatDayKey(_:)` helper. Consolidate into `Domain/Dates.swift` as `Dates.formatDayKey(_:)` — `Dates` already imports Foundation. |

---

## Calorie math — sources and validation

Formula: `kcal = MET × bodyWeightKg × hours`. Source: Ainsworth BE et al. "2011 Compendium of Physical Activities." *Med Sci Sports Exerc*, 2011.

| Activity | MET | Notes |
|---|---|---|
| Steps (walking 3.5 mph) | 4.3 | 7,392 steps/hr (2.5 ft stride). 10k steps @ 150 lb ≈ 394 kcal ✓ |
| Pilates (general) | 3.0 | Ainsworth code 06010 |
| Resistance, loaded | 4.0–8.0 | Varies by exercise; see `ExerciseInfo.meta()` for named lookup |
| Isometric hold (plank, etc.) | 3.8 default | Ainsworth 02110 (3.5) + McGill 2007 VO₂ data; 60 s @ 150 lb ≈ 2.4 kcal (Calatayud et al., *J Hum Kinet*, 2014) |
| Cardio with load | 4.5 | Duration-based; loaded parenting movement |
| Live sessions (timed activities) | 2.8–11.8 | `Domain/ActivityCatalog.swift` per-activity, Ainsworth 2011 general-effort codes (e.g. basketball game 8.0, soccer 7.0, swimming 7.0, jump rope 11.8, yoga 2.8). "Other" defaults 5.0 (user-adjustable). kcal = MET × current bodyweight × actual elapsed time |

Named exercises in `Domain/ExerciseInfo.swift` use exercise-specific METs (e.g., pull-ups 8.0, deadlift 6.0, squat 5.0). Unknown exercises fall back to category defaults. Do not hardcode per-rep kcal — always derive from MET × weight × time.

---

## Tech stack (locked)

- **SwiftUI** (iOS 17+), **SwiftData** (SQLite), **HealthKit**, **Swift Charts**, **XCTest**
- **XcodeGen** — `project.yml` → `.xcodeproj` (gitignored)
- **Fastlane** — `tests`, `compile`, `sync_signing`, `beta`
- **GitHub Actions** — `compile.yml` (every push), `testflight.yml` (manual / `v*` tag)
- **No backend.** Each device is source of truth.

---

## Data model essentials

Append-only logs. Derived figures (daily/weekly/streak/trend) are never stored.

`Domain/Models.swift` — value-type DTOs. `Data/PersistenceModels.swift` — matching `@Model` classes with `snapshot` adapters.

Key entities: `Profile`, `ExerciseDTO` (has `isIsometric: Bool`), `WorkoutSetDTO` (has `holdSeconds: Int?` for isometric), `FoodLogEntryDTO`, `BodyMetricDTO`, `HealthMarkerDTO`, `StepCountDTO`, `PilatesSessionDTO`, `CardioSessionDTO`, `WaterEntryDTO`.

`StepCount.source`: `.appleHealth` is the only live writer. `.manual` retained for schema stability.

**HealthKit coverage.** `syncFromHealth` auto-fills body mass + body fat % + waist (`BodyMetricDTO`) and resting HR + blood pressure + blood glucose (`HealthMarkerDTO`, `source: "healthkit"`), deduped per day; the synced body mass also re-points `profile.weightLb` (via `Repos.syncCurrentWeight`) so calorie/protein/water/burn targets track current weight. Steps sync via the observer/backfill path. **LDL, HDL, total cholesterol, triglycerides, and A1c are NOT available from Apple Health** (lab values exposed only via clinical records / FHIR, out of scope) — they remain manual entry. Calorie *burn* is never replaced by Health: the Train tab keeps per-exercise MET estimates, and the `MoveCard` shows Apple Health's whole-day active energy **beside** our own whole-day MET estimate (`Domain/DailyBurn.metEstimate`) so the science-based number sits next to the Watch-measured one.

**HealthKit authorization — crash traps (these caused a launch SIGABRT in build 37):**
- `requestAuthorization(toShare:read:)` can raise a **synchronous Obj-C `NSException`** that Swift `do/catch` **cannot catch** → instant `SIGABRT`. So: **only call it from the explicit, user-initiated Connect flow** (`connectAndPersist`, onboarding, Settings). **Never** call it from `.task`/`.onAppear`/pull-to-refresh — `isAuthorized` is per-process (always false at cold launch), so an auto-request there fires on every launch and any validation failure crashes the app. Reads (`steps()`, `latestQuantity`, etc.) work without re-requesting because Health authorization persists across launches; just read.
- **Only add quantity types to `readTypes`/`writeTypes`.** To read a **correlation** type (e.g. blood pressure), authorize its component quantity types and run the correlation *query* — do NOT put the correlation type itself in the auth request; it can trip request validation and raise the uncatchable exception.

---

## Design and UX rules

Two visual personalities under one shell. Mode picks palette + energy.
- **Build:** warm dark, orange/amber/cream
- **Circuit:** warm light, sage/terracotta

**Calorie copy:** UI says **"cal"** everywhere (colloquial kcal). Never `"kcal"` in user-facing strings.

### Tactile UX (load-bearing)

Every interaction: visible state change + spring animation + haptic + (for wins) brief toast.

| Concern | Lives in |
|---|---|
| All button presses | `Components/TactileButtonStyle.swift` (5 variants: primary/secondary/pill/bump/ghost) |
| Tappable cards | `Components/PressableCard.swift` |
| Number readouts | `Components/AnimatedNumber.swift` |
| Progress bars | `Components/ProgressBar.swift` |
| Confirmations | `Services/ToastCenter.swift` + `Components/ToastView.swift` |
| All haptics | `Services/Haptics.swift` |

Rules:
1. Every `Button` uses `.tactile(...)`. Never `buttonStyle(.plain)`.
2. Every meaningful mutation fires a toast.
3. Don't add a 6th button variant.
4. Don't double-haptic — `.tactile()` fires on press; only call `Haptics.bump/.success/.warn` for outcome feedback.
5. ⓘ info buttons open `.sheet` with `.presentationDetents([.medium])`. Never `.popover`.
6. All numeric/decimal keyboards need a Done toolbar button (`ToolbarItemGroup(placement: .keyboard)`).

### Corner radius + sheet backgrounds

**Everything uses rounded corners.** Flat `Rectangle()` strokes/fills are reserved only for intentional divider lines (tab-bar separator, toast left-edge accent bar).

| Surface | Shape |
|---|---|
| `Card`, `PressableCard`, `MacroQuadGrid` cells | `RoundedRectangle(cornerRadius: 16, style: .continuous)` |
| Inline card borders in feature views | `RoundedRectangle(cornerRadius: 12, style: .continuous)` |
| `TactileButtonStyle` primary/secondary | `cornerRadius: 10` |
| `TactileButtonStyle` pill | `cornerRadius: 20` |
| `TactileButtonStyle` bump | `cornerRadius: 8` |
| `Banner`, `ToastView` | `cornerRadius: 12–14` |
| `StreakChip` | `Capsule()` |
| `ProgressBar` track | `Capsule()`, fill `cornerRadius: 3` |
| Wheel picker containers | `theme.card2` background + `RoundedRectangle(cornerRadius: 12)` clip |

**Sheet backgrounds:** use `.presentationBackground(theme.bg)` — NOT `.background(theme.bg.ignoresSafeArea())`. The latter only covers the content area; `.presentationBackground` replaces the system's default sheet material and eliminates the visible border/film at sheet edges. Root screen views (`TodayView`, `ProgressView`, etc.) still use `.background(theme.bg.ignoresSafeArea())` for their main body.

**`themed(_:)` sets `colorScheme`:** `Services/Theme.swift → themed(_:)` sets both the `theme` environment key and `.environment(\.colorScheme, mode == .build ? .dark : .light)`. This ensures system UI elements (wheel pickers, keyboard, etc.) render correctly against the mode's background regardless of the device's iOS dark-mode setting. Do not override `colorScheme` individually — `themed()` handles it.

---

## CI / TestFlight rules (do not regress)

Full incident narratives in [docs/ci-history.md](docs/ci-history.md).

### Mac-less workflow
Push → `compile.yml` tells you → patch → push. Don't add Mac-only steps without "optional, Mac-only" flag.

### Test target topology
`OurFitnessTests` is **hostless**: compiles `OurFitness/Domain` sources directly. No `@testable import OurFitness`. `scripts/validate-ci-invariants.sh` enforces.

**Never use bare `Date()` in time-sensitive tests.** Streak / weekly-bucketing / "this week" logic (`Movement.pilatesWeeklyStreak`, `stepWeeklyStreak`, `sessionsThisWeek`, anything keyed on ISO week or `Dates.lastNDays`) is day-of-week sensitive: a test that passes Tue–Sat fails when CI runs on a Sun/Mon because fixtures land in an adjacent ISO week. **Pin `now` to a fixed mid-week date (e.g. Wednesday `2026-05-27T12:00:00Z`) and thread it through BOTH the fixture/data-factory helper and the function under test** (these functions take a `now:`/`end:` parameter for exactly this). See `MovementTests` for the pattern. Same rule applies to any new Domain function that buckets by date — give it an injectable `now`/`end` default rather than calling `Date()` internally.

### TestFlight signing
- Signing assets in private repo (`LLLlamas/Our-Fitness-Certs`). CI uses `match` in **readonly mode** by default.
- Managed capabilities (HealthKit, Background Delivery) require a **manually generated App Store profile** — fastlane match can't attach capabilities post May 2025 ASC API v3.8.0.
  - Generate at developer.apple.com → Profiles → + → App Store → `com.ourfitness.app`, name **`OurFitness AppStore`**.
  - Base64-encode → save as repo secret **`APPSTORE_PROFILE_BASE64`**.
- Fastfile passes `skip_provisioning_profiles: true` to match.
- Required secrets: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_API_*`, `KEYCHAIN_PASSWORD`, `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION`.
- If cert slot full: revoke stale Apple Distribution certs, dispatch with `refresh_signing` checked.

### Diagnosing "Missing com.apple.developer.X entitlement"
Walk this ladder top-down — first "missing" answer is root cause:
1. Is the phone running the latest TestFlight build? (Delete + reinstall before debugging.)
2. Does the App ID have the capability enabled at developer.apple.com?
3. Does the manually-generated profile carry the entitlement? (Check Fastfile install-step diagnostic output.)
4. Does the `.xcarchive` carry the entitlement? (Pre-export dump in CI.)
5. Does the IPA carry the entitlement? (Post-export dump in CI.)

### Xcode 26 SDK constraints
- `AppShortcutsProvider.appShortcuts` requires `@AppShortcutsBuilder`.
- **Do not hard-code `Xcode_26.0.app`** — use the version-sorted glob in the workflow.
- **Simulator runtime** needs `sudo xcodebuild -runFirstLaunch` before `-downloadPlatform iOS`.
- Build destination: `platform=iOS Simulator,name=iPhone 17` (no `OS=` suffix).
- `Info.plist` must include all 4 interface orientations for iPad validation.
- **Do not put `info:` or `entitlements:` blocks on the OurFitness target in `project.yml`** — XcodeGen overwrites the files on every generate, stripping HealthKit entitlements. Use `INFOPLIST_FILE` and `CODE_SIGN_ENTITLEMENTS` build settings only. `validate-ci-invariants.sh` enforces.

### App Store Connect upload
- Xcode 26+ / iOS 26 SDK mandatory. Both workflows run on `macos-26`.
- `workflow_dispatch` boolean inputs: compare with `inputs.<name> == true`, not `github.event.inputs.<name> == 'true'`.

### Schema migration
Current: `SchemaV5`. History: V1–V3 lightweight *staged* migrations failed with uncatchable Obj-C exceptions; app moved to a fresh store URL (`OurFitness.store`). **No staged `MigrationPlan` runs today** — the container opens `AppSchema.current` directly and relies on SwiftData's *automatic* additive migration.

**Adding new optional fields** (with `= default` or `?`) to existing `@Model` classes is safe — SwiftData applies lightweight column additions automatically. `isIsometric: Bool = false` on `ExerciseModel` and `holdSeconds: Int?` on `WorkoutSetModel` were added this way in 2026-05.

**Adding a new entity** is also additive and rides automatic migration with no plan: `WaterEntryModel` (SchemaV4, 2026-05) and `ActivitySessionModel` (SchemaV5, 2026-06, Live Sessions) were each added by listing the model in the new `SchemaV*.models` and bumping `AppSchema.current` — no staged `NSLightweightMigrationStage` (the thing that threw in builds 26/27). ⚠️ Still test an upgrade-in-place on a device carrying existing data before shipping; the fallback on failure is delete + reinstall (data loss).

**For structural changes** (renaming/splitting/retyping existing entities): define a new `SchemaV*`, write a `.custom` migration stage (not lightweight — those proved fragile), bump `AppSchema.current`.

---

## References

- [README.md](README.md) — setup, XcodeGen, TestFlight CI, secrets
- [docs/ci-history.md](docs/ci-history.md) — incident narratives behind every CI rule
- [RepCheck.md](RepCheck.md) — friction-free logging UX bar
- [nutrition-plan-research.md](nutrition-plan-research.md) — Build nutrition spec
