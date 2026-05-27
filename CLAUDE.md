# Our-Fitness — Foundation (iOS / SwiftUI)

Native iOS app for a small TestFlight circle, two modes. **Build** (gain mass, fuel hoops) and **Circuit** (drop weight, fix markers via cardio/pilates/steps). **Show up, log honestly, let the numbers tell the truth.**

> **Refactor note (2026-05):** the mode formerly named *Reset* is now *Circuit*.
> The Swift symbol is `Mode.circuit`; the SwiftData raw value is pinned to
> `"reset"` for back-compat (do not rename without a schema bump). Multi-profile
> creation replaced the two fixed seeded profiles. The food library, scoring,
> and Reset cap surfaces were stashed under `_stashed/` pending a rework — see
> "Stashed surfaces" below.

---

## The modes

**Build** — gain lean mass, keep playing. Hypertrophy bias, per-profile custom exercises, rep counter, set logger.

**Circuit** — cardiovascular markers (LDL/HDL/BP/A1c). Steps, cardio sessions, pilates, light rep counting. No strength program block.

Circuit is themed around real-life parenting movement, not gym work. New Circuit profiles auto-seed three exercises (`Repos.seedCircuitExercises`): **Lifted Baby** (30 lb / reps), **Lifted Stroller** (25 lb / reps), **Carried Baby** (30 lb / duration). The premise: a parent's day already contains workouts — log them. `Domain/CalorieEstimator.swift` converts reps or minutes against a known `loadLb` into kcal (MET × kg × hours), and every `WorkoutSet`/`CardioSession` persists `caloriesEst`. When adding Circuit content, bias toward real-life loaded movement with a known weight — don't gym-ify it, and don't hardcode kcal/rep.

| | Build | Circuit |
|---|---|---|
| Calories | TDEE + 400–600 | TDEE − 300–500 |
| Protein g/lb | ~1.0 | 1.0–1.2 |
| Steps/day | 8,000 baseline | 10,000 (#1 lever for BP/insulin/LDL) |
| Workouts | rep counter + set log on user's own exercises | inline baby exercise quick-log (no sets/targets), pilates; steps is primary tracker |

`MacroTargets.{sodiumMgMax,addedSugarGMax,saturatedFatGMax,fiberGMin}` and
`Targets.compute` still populate cap values for `.circuit` profiles, but no UI
renders them. The math sits dormant for a future revival.

---

## Codebase map

```
OurFitness/
  App/                ← @main, ModelContainer wiring, root shell
  Domain/             ← PURE Swift. No SwiftUI/SwiftData. Fully tested.
  Data/               ← SwiftData @Model classes + repositories + (now-empty) seeders
    Seed/             ← Seeder.seedAll is a no-op; profiles are user-created
  Services/           ← HealthKit, Theme, Haptics, ToastCenter (singletons)
  Features/           ← Onboarding (ProfileCreationView), Today, Nutrition (meal log),
                        Workouts (Build flow + Circuit/ subfolder), Progress, Settings
  Components/         ← Reusable view atoms (ProgressBar, Card, Banner, AnimatedNumber…)
_stashed/             ← Code excluded from the build target — see "Stashed surfaces"
OurFitnessTests/      ← Hostless XCTest for Domain/* only. No app module import.
fastlane/             ← Fastfile lanes: tests, compile, sync_signing, beta
scripts/              ← validate-ci-invariants.sh, generate-icon.sh
.github/workflows/    ← compile.yml (every push), testflight.yml (manual / v* tag)
project.yml           ← XcodeGen — source of truth; .xcodeproj is gitignored
```

### Stashed surfaces (intentionally outside the build)

These files live under `_stashed/` and are not referenced by `project.yml`'s
target source path (which is `OurFitness/`). They stay in the repo for future
revival but do not compile.

- `Data/Seed/SeedFoodsBuild.swift`, `Data/Seed/SeedFoodsReset.swift`,
  `Data/Seed/SeedExercises.swift`, `Data/Seed/SeedPrograms.swift`,
  `Data/Seed/SeedProfiles.swift` — seed libraries
- `Domain/Suggestions.swift`, `Domain/Score.swift`,
  `Domain/ScoredFood.swift`, `Domain/CapExplanations.swift` — meal scoring + Circuit cap explainers
- `Components/CapBar.swift`, `Components/CapExplanationView.swift`
- `OurFitnessTests/ScoreTests.swift`

**Hard architectural rules:**

1. `Domain/` never imports `SwiftData` or `SwiftUI`. Pure structs/functions.
2. `Features/` never opens the SwiftData container directly — use repositories or `@Query`.
3. HealthKit access only through `Services/HealthKitService.swift`. Never call `HKHealthStore` from a view.
4. `.swift` filenames within the target must be unique (Swift compiler requirement). Persistence `@Model` classes live in `Data/PersistenceModels.swift` — don't name any new file `Models.swift`.
5. `OurFitnessTests` is hostless: compiles `OurFitness/Domain` directly, blank `TEST_HOST`/`BUNDLE_LOADER`, no `@testable import OurFitness`.

---

## Where to touch for common changes

| Goal | Files |
|---|---|
| Add a per-profile exercise (runtime) | `Repos.createExercise(_:profileId:name:defaultRepsBottom:defaultRepsTop:tracksWeight:)` |
| Log a Pilates session | `Repos.logPilatesSession` + `PilatesSessionDTO` / `PilatesSessionModel` |
| Log a cardio session | `Repos.logCardio` + `CardioSessionDTO` / `CardioSessionModel` (backend only — no UI in Circuit) |
| Pilates weekly goal / streak | `Domain/Movement.swift` (`pilatesWeeklyStreak`) |
| Step-count milestone thresholds | `Domain/Movement.swift` (`defaultStepMilestones`) |
| Circuit "why this matters" copy + citations | `Domain/Movement.swift` (`circuitFocusBlurb`) + `CircuitWorkoutsView.FocusInfoButton` |
| Meal log natural language → nutrition | `Domain/FoodParser.swift` + `Domain/CommonFoods.swift` |
| Add / update a common food entry | `Domain/CommonFoods.swift` (`CommonFoods.all`) |
| Curated meal suggestions (Meals tab pill) | `Domain/SuggestedMeals.swift` — **TODO: personalise to user's cuisine patterns** |
| Apple Intelligence / Siri shortcuts | `App/OurFitnessIntents.swift` + `OurFitnessShortcuts` |
| Tweak mode caps (sodium/sugar/fiber) | `Domain/Targets.swift` (`ModeRules`) — math only, no UI |
| Change calorie math | `Domain/Targets.swift` only |
| New workout progression | `Domain/Progression.swift` strategy switch |
| 14-day auto-adjust thresholds | `Domain/Targets.swift` (`suggestAdjustment`) |
| Add a tracked health marker | `Domain/Models.swift` (`HealthMarkerKind`) + `Features/Progress/ProgressView.swift` |
| Daily steps goal | `Domain/Targets.swift` (`ModeRules.stepsDaily`) |
| New HealthKit metric | `Services/HealthKitService.swift` + `@Model` snapshot in `Data/PersistenceModels.swift` if persisted |
| New tab | `App/RootView.swift` `Tab` enum + new folder under `Features/` |
| Schema change | `Data/Schema.swift` — add new `VersionedSchema` + migration stage. Never edit shipped schemas. Current is `SchemaV2`. |
| Add HealthKit permission | `OurFitness.entitlements` + `Info.plist` (`NSHealthShareUsageDescription`) + `HealthKitService.requestAuth` |
| Press feel / button variant | `Components/TactileButtonStyle.swift` (`resolved(theme:)` switch) |
| Haptic vocabulary | `Services/Haptics.swift` |
| Toast accent / haptic pairing | `Services/ToastCenter.swift` (`ToastAccent` + `fireHaptic(for:)`) |
| Bar target-hit flash | `Components/ProgressBar.swift` (`onChange(of: value)`) |

---

## Tech stack (locked)

- **SwiftUI** (iOS 17+) — declarative UI, native dark mode
- **SwiftData** — persistence (`@Model` + `VersionedSchema`); SQLite under the hood
- **HealthKit** — steps, weight, RHR, active energy (+ workout write-back)
- **Swift Charts** — trends, no third-party deps
- **XCTest** — domain layer fully unit-tested
- **XcodeGen** — `project.yml` → `.xcodeproj` (gitignored, regenerated in CI)
- **Fastlane** — lanes: `tests`, `compile`, `sync_signing`, `beta`. Signs via App Store Connect API key + `match`.
- **GitHub Actions** — `compile.yml` (every push, ~3 min), `testflight.yml` (manual / `v*` tag)
- **No backend.** Each device is source of truth. Future CloudKit sync is one entitlement away.

---

## Data model essentials

All entities namespaced per `Profile`. Append-only logs (sets, food entries, body metrics, markers). Daily/weekly/streak/trend figures are **derived, never stored**.

`Domain/Models.swift` holds value-type DTOs. `Data/PersistenceModels.swift` holds matching `@Model` classes. Each `@Model` exposes a `snapshot` adapter so domain functions stay pure.

Headline entities:
- `Profile` — name, mode, biometrics, activity, restrictions, `computedTargets`
- `MacroTargets` — calories/protein/carbs/fat + `stepsDaily` + optional Reset caps
- `Exercise`, `WorkoutSet`, `Workout`, `Program` — gym programming
- `Food`, `FoodLogEntry` — `modeFit` gates suggestions; entries denormalize macros
- `BodyMetric` — weight, body-fat, waist
- `HealthMarker` — BP, LDL/HDL, triglycerides, A1c, fasting glucose, resting HR (Reset-critical)
- `StepCount` — one row per user per day (UPSERT); `source: .appleHealth` is the only live writer (HealthKit observer + backfill). `.manual` is a retained enum case with no current writer (manual step entry was removed); kept for schema stability and a possible future Watch/airplane-mode path.

---

## Mode behaviors

**Suggestion algorithm** (same shape, per-mode scoring): filter by `modeFit`, allergens, slot; for Reset also filter against today's remaining sodium/sugar/sat-fat headroom. Score, return top 5.
- Build rewards: calorie density, liquid (if `lowAppetite`), cost, protein-gap fill
- Reset rewards: fiber, satiety, omega-3, low sodium, protein-per-calorie

**14-day auto-adjust** (suggests, never mutates):
- Build stalled → +200 cal/day; gaining >0.75 lb/wk → drop a multiplier
- Reset stalled → −150 cal/day or +1 cardio; losing >1.5 lb/wk → +150 cal (protect muscle); marker stuck after 8 weeks → flag for doctor, never prescribe

---

## HealthKit integration

`Services/HealthKitService.swift` owns all HealthKit access. Two modes:
1. **Pull on demand** — `todaySteps(for: profile)` for the Today card
2. **Observers** — `HKObserverQuery` at launch wakes the app for background step updates → UPSERT into `StepCount`

Permissions:
- Read: `stepCount`, `bodyMass`, `restingHeartRate`, `activeEnergyBurned`, `appleExerciseTime`
- Write: `workouts` (logged sessions surface in Apple Health), `bodyMass`

Simulator returns no Health data — UI in sim, HealthKit on a real iPhone.

---

## Design direction

Two visual personalities under one shell. Mode picks palette + energy. Typography shared via Dynamic Type with custom fonts (Bebas Neue display numerals, Fraunces serif accents, SF Mono stat readouts — system fallbacks).

- **Build:** warm dark, orange/amber/cream
- **Reset:** warm light, sage/terracotta

Shared: large headlines, generous whitespace, weekly trend > daily pass/fail, no streak-shame, persistent banners (allergens on Build, caps remaining on Reset). System dark mode follows iOS; mode tokens override via `ThemeProvider`.

### Tactile UX (load-bearing — the app feels alive)

Every interaction is multisensory: visible state change + spring animation + haptic + (for wins) brief toast.

| Concern | Lives in | Notes |
|---|---|---|
| All button presses | `Components/TactileButtonStyle.swift` | 5 variants (`primary`/`secondary`/`pill`/`bump`/`ghost`); spring scale-down, light haptic tick |
| Tappable cards | `Components/PressableCard.swift` | Same press feel, accent stroke on press |
| Number readouts | `Components/AnimatedNumber.swift` | `.contentTransition(.numericText())` + spring tween |
| Progress bars | `Components/ProgressBar.swift` | Spring fill; success haptic + flash on target cross |
| Confirmations | `Services/ToastCenter.swift` + `Components/ToastView.swift` | One-at-a-time, ~1.8s, matching haptic |
| All haptics | `Services/Haptics.swift` | 5 patterns: `tap`/`bump`/`success`/`warn`/`selection` |

Rules:
1. Every `Button` uses `.tactile(...)`. Never `buttonStyle(.plain)`.
2. Every meaningful mutation fires a toast (`toasts.logged(...)`, `toasts.goalHit(...)`).
3. Don't add a 6th button variant. Reuse one.
4. Don't double-haptic. `.tactile()` already fires impact on press; only call `Haptics.bump/.success/.warn` for *outcome* feedback.
5. Whole-card-as-button beats inline buttons inside a card — use `PressableCard` and drop the redundant action button.

---

## CI / TestFlight rules (do not regress)

All "Current rule" entries below trace to a specific past incident; full incident narratives live in [docs/ci-history.md](docs/ci-history.md). Touch a rule only when you understand why it exists.

### Mac-less workflow
- No local Xcode. Loop is **push → `compile.yml` tells you → patch → push**. See [README.md](README.md) for setup.
- Don't add Mac-only steps to docs without flagging them "optional, Mac-only."
- Strict concurrency is **minimal** in `project.yml` during scaffolding. Bump to `complete` once surface is stable.

### Test target topology
- `OurFitnessTests` is **hostless**: compiles `OurFitness/Domain` sources directly. No `@testable import OurFitness`. `TEST_HOST` and `BUNDLE_LOADER` blank. `scripts/validate-ci-invariants.sh` enforces.
- For future apps: put pure logic in a Swift Package, or compile pure sources directly into a hostless test target. **Do not** use the iOS app executable as a `BUNDLE_LOADER` shortcut — `.app/OurFitness` is often a stub for `OurFitness.debug.dylib` and hosting through it triggers the SwiftUI app lifecycle.

### TestFlight signing — fastlane `match`, never raw `cert`/`sigh`
- Signing assets live encrypted in a separate private repo (`LLLlamas/Our-Fitness-Certs`). CI runs `match` in **readonly mode** (`MATCH_READONLY=true`) by default — pulls existing assets, cannot consume an Apple Distribution cert slot.
- For App Store/TestFlight provisioning, omit `adhoc`/`developer_id` entirely (passing them as `false` triggers Fastlane's mutex check). `validate-ci-invariants.sh` guards top-level `cert(` / `sigh(` calls and false sigh-mode flags.
- Bootstrap or rotation only: dispatch with `refresh_signing` ✅ checked → `MATCH_READONLY=false` → `fastlane ios sync_signing` runs before XcodeGen/tests so cert-capacity failures fail fast. This rotates the Apple Distribution **cert**. It does NOT rotate the **provisioning profile** — see next bullet.
- **Provisioning profiles bearing managed capabilities (HealthKit, Background Delivery, Push, Sign-in-with-Apple) must be generated by hand.** Apple removed the App Store Connect API endpoint that fastlane match used to attach capabilities to regenerated profiles in May 2025 (ASC API v3.8.0). Match's `--template_name` is deprecated with no replacement (see [fastlane docs](https://docs.fastlane.tools/actions/match/#managed-capabilities)). Symptom of trying to use match anyway: profile gets regenerated successfully, the IPA signs and uploads cleanly, but on device `requestAuthorization` fails with `Missing com.apple.developer.<x> entitlement`.
  - **One-time setup**: at developer.apple.com → Profiles → +, generate an **App Store** profile against `com.ourfitness.app` (which must have HealthKit + HealthKit Background Delivery enabled in the App ID), naming it exactly **`OurFitness AppStore`**. Download the `.mobileprovision`.
  - On Windows: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("OurFitness_AppStore.mobileprovision")) | Set-Clipboard`. On macOS/Linux: `base64 -i OurFitness_AppStore.mobileprovision | pbcopy` (or `xclip`).
  - Save the base64 string as repo secret **`APPSTORE_PROFILE_BASE64`**. The TestFlight workflow installs it on every run via `fastlane ios install_appstore_profile` *before* the build step.
  - When a capability changes (new entitlement enabled on the App ID), repeat the manual steps and update the secret. No CI dispatch needed for the change itself; the next TestFlight run picks up the new profile automatically.
- The Fastfile passes `skip_provisioning_profiles: true` to match so match no longer touches profiles at all — only the cert. Combined with the manual install step, this fully sidesteps the broken capability-attach path.
- **Preflight** step (`Preflight — signing mode + match repo readiness`) prints the resolved mode and, in readonly, clones the match repo to confirm a `.p12` exists; fails fast with actionable message if empty.
- Required release secrets: `APPLE_TEAM_ID`, `APP_STORE_CONNECT_API_*`, `KEYCHAIN_PASSWORD`, `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION` (base64 `github-user:token`).
- If `Could not create another Distribution certificate, reached the maximum number`: revoke stale unused **Apple Distribution** certs at developer.apple.com (don't touch one signing a build under review), then run TestFlight once with `refresh_signing` checked. Leave it unchecked after that.
- TestFlight workflow uses Ruby **3.3** (Fastlane dropped 3.2 support).

### GitHub Actions boolean inputs
- Access `workflow_dispatch` boolean inputs as `inputs.<name>` and compare with `== true` — **not** `github.event.inputs.<name> == 'true'`. The latter coerces typed booleans to strings and silently always returns false.

### Xcode 26 SDK constraints
- `AppShortcutsProvider.appShortcuts` **requires `@AppShortcutsBuilder`** — returning a plain `[AppShortcut]` array literal without it is a compile error in the iOS 26 SDK. See `App/OurFitnessIntents.swift`.

### App Store Connect upload requirements
- **Xcode 26+ / iOS 26 SDK** is mandatory for upload. Both workflows run on `macos-26`.
- **Do not hard-code `Xcode_26.0.app`.** Runner images install point-release names (`Xcode_26.0.1.app`, etc.) and keep the latest beta alongside. The **Select Xcode 26** step disables `*beta*.app` by rename, globs `Xcode_26*.app`, drops dangling symlinks, picks the highest valid via `sort -V`, and exports both `DEVELOPER_DIR` **and** `PATH` (beta `usr/bin` can otherwise route `actool`/`clang`/`ld` to beta tooling even when DEVELOPER_DIR points elsewhere — symptom: ASC rejects external testing with "build is using a beta version of Xcode").
- **Simulator runtime is not preinstalled.** The **Ensure iOS simulator runtime** step runs `sudo xcodebuild -runFirstLaunch` first (mandatory — otherwise `-downloadPlatform` exits 70 with the misleading "not available for download"), then retries `xcodebuild -downloadPlatform iOS` up to 3 times. **Do not pass `-buildVersion`** — let xcodebuild pick the runtime matching the selected Xcode's iphonesimulator SDK.
- Build/test destinations: `platform=iOS Simulator,name=iPhone 17` with **no `OS=` suffix**. Fastfile `device:` is `"iPhone 17"`. Never `generic/platform=iOS Simulator`. When the runner image upgrades and drops the named device, update both to the newest iPhone model present in the available destinations list printed in the xcodebuild error.
- `Info.plist` base `UISupportedInterfaceOrientations` must include all four orientations (Portrait, PortraitUpsideDown, LandscapeLeft, LandscapeRight) for iPad multitasking validation. Keep `~ipad` variant in sync. `UILaunchScreen` dict (already present) satisfies the launch-screen requirement.
- **Do not put an `info:` block on the OurFitness target in `project.yml`.** XcodeGen regenerates the file at `info.path` on every `xcodegen generate`, overwriting our orientations / HealthKit usage strings / UILaunchScreen with a minimal default. Point Xcode at the file via the `INFOPLIST_FILE` build setting only. `GENERATE_INFOPLIST_FILE: "NO"` stays at the project base.
- **Do not put an `entitlements:` block on the OurFitness target in `project.yml`.** Identical trap: XcodeGen writes an empty plist to the path on every generate, wiping our HealthKit / Background Delivery declarations and producing an archive with only the 4 default entitlement keys (`application-identifier`, `beta-reports-active`, `team-identifier`, `get-task-allow`). The IPA signs cleanly and uploads to TestFlight, but the app fails on device with `Missing com.apple.developer.healthkit entitlement` because the binary's embedded entitlements don't include HealthKit even though the provisioning profile does. Point Xcode at the hand-written `.entitlements` file via the `CODE_SIGN_ENTITLEMENTS` build setting only. `scripts/validate-ci-invariants.sh` enforces the absence of the block.

### Diagnosing "Missing com.apple.developer.X entitlement" on device

This error appeared multiple times during the HealthKit rollout. Every time it had a different root cause, but always the same on-device symptom. Walk the ladder top-down — each rung is a strictly upstream layer of the previous one, so the first "missing" answer is the root cause.

The two diagnostic steps in `testflight.yml` (**Dump archived .app entitlements (pre-export)** and **Dump signed IPA entitlements (post-export)**) plus the install-step diagnostic in `Fastfile.install_appstore_profile` answer each rung directly.

1. **Is the app on the phone actually the latest TestFlight build?** Check the build number on the phone vs the latest workflow run number. Delete + reinstall before debugging anything else. (Wasted 1+ hour on this once.)
2. **Does the App ID have the capability enabled in developer.apple.com?** Identifiers → `com.<bundle>.app` → Capabilities. For HealthKit, both the top-level checkbox AND the `Background Delivery` sub-option need to be on.
3. **Does the manually-generated provisioning profile carry the entitlement?** Look at the `Fastfile.install_appstore_profile` diagnostic output — it lists every `com.apple.developer.*` key in the profile. If the entitlement isn't there, **delete the profile in developer.apple.com and create a new one** (Edit/Save does NOT refresh capabilities from the App ID — confirmed gotcha). Then base64 the new `.mobileprovision` and update `APPSTORE_PROFILE_BASE64`.
4. **Does the .xcarchive's signed .app carry the entitlement?** Look at the **pre-export** dump. If the profile has it but the archive doesn't, the source of stripping is in the build itself — almost always XcodeGen overwriting the entitlements file (see `entitlements:` block rule above) or a wrong `CODE_SIGN_ENTITLEMENTS` path.
5. **Does the IPA carry the entitlement?** Look at the **post-export** dump. If the archive has it but the IPA doesn't, the re-sign during fastlane gym's export step is stripping it — check `export_options.provisioningProfiles` and confirm the export profile UUID matches the archive profile UUID.

`codesign -d --entitlements -` (without `--xml`) prints in Apple's old text format — `[Key] foo`, `[Bool] true` — not XML. When writing detection regexes, match `com\.apple\.developer\.<name>(\b|<)` to cover both formats.

### Why native / Why SwiftData
- **Native:** HealthKit only works in native iOS apps. Capacitor/PWA can't read step counts. Side benefits: real push, Live Activities, Shortcuts, App Intents, widgets.
- **SwiftData:** SwiftUI-native `@Query`, CloudKit sync via one flag, clean `VersionedSchema` migration, SQLite backing — durability identical to Core Data, better dev velocity at this size.

---

## Non-goals (v1)

No third user. No medical advice. No social/sharing/leaderboards. No barcode scan / restaurants / Instacart. No notifications until the daily loop is solid. No Apple Watch (likely v2).

---

## Build order

1. Onboarding + profile + HealthKit permission
2. Today view (bars, steps, log meal, log set)
3. Suggestion engine in Today
4. Workouts: program picker → block runner → set logger with progression
5. Progress: weight + steps + markers
6. Nutrition library browser
7. Weekly planner + grocery list
8. Export/import (JSON + SwiftData `.store` backup)
9. 14-day auto-adjust as suggestion cards
10. Apple Watch companion (post-v1)

**Ship #1–4 before anything below. The daily loop is the product.**

---

## Foundation references

- [README.md](README.md) — setup, XcodeGen, TestFlight CI, secrets
- [docs/ci-history.md](docs/ci-history.md) — full incident narratives behind every "do not regress" rule
- [RepCheck.md](RepCheck.md) — friction-free logging UX bar
- [nutrition-plan-research.md](nutrition-plan-research.md) — Build nutrition spec
- [nutrition-plan.html](nutrition-plan.html) — Build visual reference
