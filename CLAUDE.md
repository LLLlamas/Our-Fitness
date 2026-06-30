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
  Components/   ← ProgressBar, ProgressRing, Card, Banner, AnimatedNumber, TactileButtonStyle…
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
| Isometric timer UI | `Features/Workouts/RepCounter.swift` → `IsometricTimerView` |
| Isometric calorie math | `Domain/CalorieEstimator.swift` → `caloriesForIsometric` |
| Rep counter | `Features/Workouts/RepCounter.swift` → `RepCounterView` |
| Delete set / exercise | `Repos.deleteSet` / `Repos.deleteExercise` + `SetHistorySheet` in `Features/Workouts/WorkoutsView.swift` |
| Log pilates | `Repos.logPilatesSession` + `Domain/Models.swift` (`PilatesSessionDTO`); UI `Features/Workouts/Circuit/PilatesCard.swift` (Train tab, Circuit) |
| Log cardio | `Repos.logCardio` + `Domain/Models.swift` (`CardioSessionDTO`) |
| Circuit movements (quick-log) | `Features/Workouts/Circuit/BabyExercisesCard.swift` — Train tab (`WorkoutsView` Circuit branch); renders the auto-seeded parenting exercises as tap-to-+1 |
| Live sessions (timer) | `Features/Workouts/LiveSessionCard.swift` + `Domain/LiveSessionState.swift` + `Services/LiveSessionService.swift` |
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
| Move card (2×3 cols) | `Features/Today/MoveCard.swift` — row 1: Apple Total · Our Total Estimate · Training Only; row 2: Distance · Flights · Heart Rate. Single `metricColumn` helper (uniform 22pt value font, no differential shrink). `activityRow(kcal:)` takes `Int` |
| Steps (Build) | `Features/Today/StepsCard.swift` |
| Steps + cardio (Circuit, on Today) | `Features/Workouts/Circuit/StepsCardioCard.swift` |
| Water tracker (presets + day-streak) | `Domain/Water.swift` (presets Sip 4 / S 8 / M 16 / L 32 oz; `streak(_:goalFlOz:end:)`) + `Features/Today/WaterCard.swift` (`AppStorage "waterGoalFlOz.\(profileId)"`; streak chip) |
| Water quick-log (app-wide FAB) | `Features/Today/WaterQuickLogButton.swift` — tap = repeat last (`AppStorage "waterLastFlOz.\(profileId)"`), press-and-hold = dim screen + radial preset picker; logs via `Repos.addWater`. Overlaid in `App/RootView.swift` |
| Step milestones / goals | `Domain/Movement.swift` (`defaultStepMilestones`). Per-profile override: `AppStorage "stepsGoal.\(profileId.uuidString)"` |
| Today burn estimate | `Domain/DailyBurn.swift` → `metEstimate` |
| Encouragement / milestones | `Domain/EncouragementEngine.swift` + `Domain/EncouragementMessage.swift` + `Components/ProjectionBar.swift` |
| Meal/water nudges | `Domain/EncouragementEngine.swift` → `mealLoggingNudge` / `waterNudge`; wired in `Features/Today/TodayView.swift` |
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
| App tab layout | `App/RootView.swift` — both modes: Today / Meals / Train / Progress. `WorkoutsView` is mode-aware (Build = lift list + rep counter; Circuit = Pilates + movement quick-log). Today mirrors Build in both (macros/move/water/steps + food log; Circuit adds cardio) |
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
| Schema migration | `Data/Schema.swift` — current SchemaV6. Additive (new optional field / entity) = automatic. Structural = `.custom` stage. |

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

Append-only logs. Derived figures never stored. DTOs in `Domain/Models.swift`; `@Model` classes in `Data/PersistenceModels.swift` with `snapshot` adapters; CRUD in `Data/Repositories/Repositories.swift`.

Key entities: `ProfileDTO`, `ExerciseDTO` (`isIsometric`), `WorkoutSetDTO` (`holdSeconds?`), `FoodLogEntryDTO` (`ingredients?`), `BodyMetricDTO`, `HealthMarkerDTO`, `StepCountDTO`, `PilatesSessionDTO`, `CardioSessionDTO`, `WaterEntryDTO`, `ActivitySessionDTO`, `SavedMealTemplateDTO`.

**HealthKit crash traps (caused SIGABRT in build 37):**
- `requestAuthorization` raises uncatchable `NSException` — call ONLY from explicit user Connect flow. Never from `.task`/`.onAppear`.
- Add only quantity types to `readTypes`/`writeTypes` — correlation types (e.g. blood pressure) crash auth.

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

- **Mac-less workflow:** push → `compile.yml` → patch → push.
- **Tests hostless:** `OurFitnessTests` compiles `Domain/` directly. No `@testable import`. `scripts/validate-ci-invariants.sh` enforces.
- **Never bare `Date()` in streak/weekly tests** — pin `now` to fixed mid-week (e.g. `2026-05-27T12:00:00Z`), thread through fixture + function.
- **Signing:** match repo `LLLlamas/Our-Fitness-Certs`, readonly CI. Manual App Store profile `OurFitness AppStore` → base64 → `APPSTORE_PROFILE_BASE64`. Widget (`com.ourfitness.app.widgets`) needs its own profile.
- **XcodeGen:** never `info:` or `entitlements:` blocks on target — use `INFOPLIST_FILE`/`CODE_SIGN_ENTITLEMENTS` build settings only.
- **Entitlement missing?** Ladder: latest build → App ID capability → profile has it → `.xcarchive` → IPA.
- **Xcode 26:** version-sorted glob (not hardcoded). Build dest: `platform=iOS Simulator,name=iPhone 17`. All 4 orientations in `Info.plist`.
- Secrets: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_API_*`, `KEYCHAIN_PASSWORD`, `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION`, `APPSTORE_PROFILE_BASE64`, `APPSTORE_WIDGET_PROFILE_BASE64`

---

## References

- [README.md](README.md) — setup, XcodeGen, CI, secrets
- [docs/ci-history.md](docs/ci-history.md) — incident narratives behind CI rules
- [docs/setup.md](docs/setup.md) — one-time setup, secrets, daily loop
- [docs/RepCheck.md](docs/RepCheck.md) — friction-free logging UX bar
- [docs/nutrition-plan-research.md](docs/nutrition-plan-research.md) — Build nutrition spec
- [docs/app-expansion.md](docs/app-expansion.md) — Phase 2/3 roadmap (iCloud sync, store polish)
- [docs/live-activity-setup.md](docs/live-activity-setup.md) — widget signing checklist

> Other `docs/*-plan.md` / `*-implementation.md` are historical design snapshots — some predate shipped behaviour (e.g. they say Circuit has no strength / no Train tab). This file and the code are authoritative when they disagree.
