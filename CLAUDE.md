# Our-Fitness — Foundation (iOS / SwiftUI)

Native iOS app for a small TestFlight circle. Two modes: **Build** (gain mass, fuel hoops) and **Circuit** (drop weight, fix cardiovascular markers). Show up, log honestly, let the numbers tell the truth.

> **Rename note (2026-05):** *Reset* → *Circuit*. Swift symbol `Mode.circuit`; SwiftData raw value pinned to `"reset"` for back-compat. Multi-profile creation replaced fixed seeded profiles. Food library, scoring, and cap surfaces stashed under `_stashed/` pending rework.

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
3. HealthKit access only through `Services/HealthKitService.swift`.
4. `.swift` filenames within the target must be unique. `@Model` classes live in `Data/PersistenceModels.swift` — don't name any new file `Models.swift`.
5. `OurFitnessTests` is hostless: blank `TEST_HOST`/`BUNDLE_LOADER`, no `@testable import OurFitness`.

---

## Where to touch for common changes

| Goal | Files |
|---|---|
| Add a per-profile exercise | `Repos.createExercise` — pass `isIsometric: true` for plank/hold exercises |
| Isometric hold timer UI | `Features/Workouts/RepCounter.swift` → `IsometricTimerView` |
| Isometric calorie math | `Domain/CalorieEstimator.caloriesForIsometric(seconds:met:bodyWeightLb:)` |
| Rep counter (non-isometric) | `Features/Workouts/RepCounter.swift` → `RepCounterView` |
| Log a Pilates session | `Repos.logPilatesSession` + `PilatesSessionDTO` / `PilatesSessionModel` |
| Log a cardio session | `Repos.logCardio` + `CardioSessionDTO` / `CardioSessionModel` |
| Pilates weekly goal / streak | `Domain/Movement.swift` (`pilatesWeeklyStreak`) |
| Step-count milestone thresholds | `Domain/Movement.swift` (`defaultStepMilestones`) |
| Circuit "why this matters" copy | `Domain/Movement.swift` (`circuitFocusBlurb`) |
| Post-exercise recovery hint | `Domain/Movement.swift` (`postExerciseHint`, `postPilatesHint`, `namedParentingHint`) |
| Circular progress arc | `Components/ProgressRing.swift` — reuse, never inline `Circle().trim` |
| Per-profile steps goal override | `AppStorage` key `"stepsGoal.\(profileId.uuidString)"` |
| Meal log natural language → nutrition | `Domain/FoodParser.swift` + `Domain/CommonFoods.swift` |
| Add / update a common food | `Domain/CommonFoods.swift` (`CommonFoods.all`) |
| Curated meal suggestions | `Domain/SuggestedMeals.swift` |
| Meal detail modal (info + portion adjust) | `Features/Nutrition/NutritionView.swift` → `MealDetailSheet` |
| Change calorie math | `Domain/Targets.swift` only |
| New workout progression | `Domain/Progression.swift` strategy switch |
| Add a tracked health marker | `Domain/Models.swift` (`HealthMarkerKind`) + `Features/Progress/ProgressView.swift` |
| New HealthKit metric | `Services/HealthKitService.swift` + snapshot in `Data/PersistenceModels.swift` |
| New tab | `App/RootView.swift` `Tab` enum + new folder under `Features/` |
| Schema change | `Data/Schema.swift` — new `VersionedSchema` + custom migration stage. Never edit shipped schemas. Current: `SchemaV3`. |
| Add HealthKit permission | `OurFitness.entitlements` + `Info.plist` + `HealthKitService.requestAuth` |
| Button variant | `Components/TactileButtonStyle.swift` — reuse existing 5 variants |
| Haptic vocabulary | `Services/Haptics.swift` |
| Toast accent / haptic pairing | `Services/ToastCenter.swift` |

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

Key entities: `Profile`, `ExerciseDTO` (has `isIsometric: Bool`), `WorkoutSetDTO` (has `holdSeconds: Int?` for isometric), `FoodLogEntryDTO`, `BodyMetricDTO`, `HealthMarkerDTO`, `StepCountDTO`, `PilatesSessionDTO`, `CardioSessionDTO`.

`StepCount.source`: `.appleHealth` is the only live writer. `.manual` retained for schema stability.

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

---

## CI / TestFlight rules (do not regress)

Full incident narratives in [docs/ci-history.md](docs/ci-history.md).

### Mac-less workflow
Push → `compile.yml` tells you → patch → push. Don't add Mac-only steps without "optional, Mac-only" flag.

### Test target topology
`OurFitnessTests` is **hostless**: compiles `OurFitness/Domain` sources directly. No `@testable import OurFitness`. `scripts/validate-ci-invariants.sh` enforces.

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
Current: `SchemaV3`. History: V1–V3 lightweight migrations failed with uncatchable Obj-C exceptions; app now opens a fresh store URL (`OurFitness.store`). No migration plan runs today.

**Adding new optional fields** (with `= default` or `?`) to existing `@Model` classes is safe — SwiftData applies lightweight column additions automatically. `isIsometric: Bool = false` on `ExerciseModel` and `holdSeconds: Int?` on `WorkoutSetModel` were added this way in 2026-05.

**For structural changes**: define `SchemaV4`, write a `.custom` migration stage (not lightweight — those proved fragile), bump `AppSchema.current`.

---

## References

- [README.md](README.md) — setup, XcodeGen, TestFlight CI, secrets
- [docs/ci-history.md](docs/ci-history.md) — incident narratives behind every CI rule
- [RepCheck.md](RepCheck.md) — friction-free logging UX bar
- [nutrition-plan-research.md](nutrition-plan-research.md) — Build nutrition spec
