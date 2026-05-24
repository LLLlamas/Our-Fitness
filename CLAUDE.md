# Our-Fitness — Foundation (iOS / SwiftUI)

Native iOS app for two specific humans, two specific modes. **Build** (gain mass, fuel hoops) and **Reset** (drop weight, fix markers). One device per person, one mode per person, one philosophy: **show up, log honestly, let the numbers tell the truth over time.**

Purpose-built for these two. Don't generalize for a third.

---

## The two humans, the two modes

**Build** — gain lean mass, keep playing. Picky-eater hardgainer, basketball 4–5×/week, struggles to eat enough. Enemy is *under-fueling*. Nut-free allergen lock. Food library: the familiar short list (smoothies, spam, rice, eggs, pizza, chocolate milk, nuggets — see [nutrition-plan-research.md](nutrition-plan-research.md)).

**Reset** — drop weight, fix the markers. Real labs to move: elevated cholesterol, BP, blood sugar. Enemy is *dense empty calories + sodium creep*. **No food restrictions or allergies.** Food library: DASH + Mediterranean leaning — leafy greens, legumes, whole grains, oily fish, olive oil, nuts/seeds, low sodium, high fiber.

| | Build | Reset |
|---|---|---|
| Calories | TDEE + 400–600 | TDEE − 300–500 |
| Protein g/lb | ~1.0 | 1.0–1.2 |
| Caps | none beyond macros | sodium ≤1,500 mg, added sugar ≤25 g, sat fat <10%, fiber ≥35 g |
| Steps/day | 8,000 baseline (hoops adds more) | 10,000 (#1 lever for BP/insulin/LDL) |
| Suggestion bias | calorie-dense, liquid-friendly, frequency | fiber-dense, satiety, omega-3, low-sodium |
| Workouts | hypertrophy, 6–12 reps, double-progression | 2–3 strength + 3–4 zone-2 cardio, RPE cap 7 |

The two modes share **infrastructure**, not **content**. Resist merging the food libraries with a `mode` tag — they have different philosophies.

---

## Tech stack (locked)

- **SwiftUI** (iOS 17+) — declarative UI, native feel, free dark mode
- **SwiftData** — persistence (SQLite under the hood, `@Model` classes, schema versioning via `VersionedSchema`)
- **HealthKit** — steps, weight, resting HR, active energy ingest (and optional write-back for logged workouts)
- **Swift Charts** — built-in trend visualization, no third-party deps
- **XCTest** — domain layer fully unit-tested
- **XcodeGen** (`project.yml` → `.xcodeproj`) — `.xcodeproj` is git-ignored; regenerated in CI every run
- **Fastlane** (Fastfile lanes: `tests`, `compile`, `beta`) — handles signing via App Store Connect API key, no manual `.p12` ever
- **GitHub Actions** — two workflows: `compile.yml` (every push, 3 min feedback) and `testflight.yml` (manual / `v*` tag, ships to TestFlight)
- **No backend.** Each device is the source of truth. Future CloudKit sync is one entitlement away if we ever want it.

### Mac-less workflow (lead dev is on Windows)

There is no local Xcode. The dev loop is **push → CI tells you if it compiles → patch → push again**. Full setup and daily-loop instructions live in [README.md](README.md). Key implications for working in this codebase:

- Don't add Mac-only steps to documentation (Xcode previews, local fastlane, `xcodegen generate` from a Mac, etc.) without flagging them as "optional, Mac-only."
- The compile workflow is the source of truth for "does this build" — if it's green, ship it.
- Strict concurrency is set to **minimal** in `project.yml` during scaffolding to avoid Sendable churn blocking iteration. Bump to `complete` later when the surface is stable.
- **CI Xcode pin:** both workflows run `macos-15` / Xcode **16.3** (set via `XCODE_VERSION` env var at the top of each `.github/workflows/` file). To upgrade Xcode, bump that var and `runs-on` in both files together. `project.yml` also sets `objectVersion: "56"` — this is a hard floor that prevents XcodeGen from emitting a project format newer than what the pinned Xcode can read. If you ever see *"cannot be opened because it is in a future Xcode project file format"*, the runner Xcode and this objectVersion are out of sync.

### Why native over web wrapper
HealthKit only works in native iOS apps. Capacitor/PWA can't read step counts. We want phone-as-sensor passively, so native is the only path. Side benefits: real push notifications, Live Activities, Shortcuts intents, App Intents for Siri, Lock Screen widgets — all available later without re-platforming.

### Why SwiftData over Core Data / GRDB
SwiftData is Apple's modern wrapper, integrates natively with SwiftUI `@Query`, supports CloudKit sync via a single flag, has clean schema migration via `VersionedSchema`. Backing store is still SQLite — durability is identical. For an app this size, the dev velocity wins.

---

## Codebase map

```
OurFitness/
  App/
    OurFitnessApp.swift          ← @main entry, ModelContainer wiring
    RootView.swift               ← profile gate, tab bar, theme injection
  Domain/                        ← PURE Swift. No SwiftUI/SwiftData. Fully tested.
    Models.swift                 ← Mode, Sex, ActivityLevel, MacroTargets, DTOs
    Dates.swift                  ← dayKey, lastNDays, formatTimeAgo
    Score.swift                  ← bell, rampUp, rampDown, macroFit (shared)
    Targets.swift                ← Mifflin-St Jeor + mode adjustments
    Suggestions.swift            ← filter + score meals (per-mode scoring)
    Progression.swift            ← linear / double-prog / RPE strategies
    Trends.swift                 ← rolling avg, weekly weight delta, marker stall
    Streaks.swift                ← adherence (≥80% cal target days in a row)
    Steps.swift                  ← step rollups + hit-rate + dense series
  Data/
    ModelContainer.swift         ← SwiftData container + ModelConfiguration
    Schema.swift                 ← VersionedSchema + MigrationPlan
    Models/                      ← @Model classes (one per entity)
    Repositories/                ← Query helpers, batch operations, seeders
    Seed/
      Seeder.swift               ← idempotent on launch
      FoodsBuild.swift           ← picky-friendly, nut-free
      FoodsReset.swift           ← DASH + Mediterranean
      Exercises.swift            ← full lift catalog
      Programs.swift             ← starter programs per mode
  Services/
    HealthKitService.swift       ← steps, weight, RHR; auth + observers + writes
    Theme.swift                  ← mode → color/font tokens (light + dark)
  Features/
    Onboarding/                  ← profile creation flow
    Today/                       ← daily anchor view: bars + steps + suggestions + log
    Nutrition/                   ← library browser, planner (later), grocery (later)
    Workouts/                    ← program runner, set logger, history
    Progress/                    ← weight, steps, markers, lift PRs
  Components/                    ← ProgressBar, Banner, StatBlock, Card
  Assets.xcassets/               ← AppIcon, AccentColor, LaunchBackground
  Info.plist                     ← HealthKit usage strings (App Store requirement)
  OurFitness.entitlements        ← HealthKit capability
OurFitnessTests/                 ← XCTest suites for Domain/* only
fastlane/
  Fastfile                       ← lanes: tests, compile, beta
  Appfile                        ← bundle id + team id wiring
Gemfile                          ← Fastlane version pin
scripts/
  generate-icon.sh               ← idempotent AppIcon placeholder generator
.github/workflows/
  compile.yml                    ← every push/PR: build + test, no signing
  testflight.yml                 ← manual or v* tag: sign + ship via fastlane
project.yml                      ← XcodeGen — single source of truth for project layout
```

**Three architecture rules to keep clean:**
1. **`Domain/` never imports `SwiftData` or `SwiftUI`.** Pure structs and functions, easy to test.
2. **`Features/` never opens the SwiftData container directly.** Uses repositories or `@Query` projections.
3. **HealthKit access goes through `HealthKitService`** — never call `HKHealthStore` from a view.

---

## Where to touch for common changes

| Goal | Files |
|---|---|
| Add a new exercise | `Data/Seed/Exercises.swift` |
| Add a Build food | `Data/Seed/FoodsBuild.swift` |
| Add a Reset food | `Data/Seed/FoodsReset.swift` |
| New starter program | `Data/Seed/Programs.swift` |
| Tweak mode caps (sodium/sugar/fiber) | `Domain/Targets.swift` (`ModeRules`) |
| Change how meals are scored | `Domain/Score.swift` (shared) + `Domain/Suggestions.swift` (mode weights) |
| Change calorie math | `Domain/Targets.swift` only |
| New workout progression scheme | `Domain/Progression.swift` — add to the strategy switch |
| Adjust 14-day auto-adjust thresholds | `Domain/Targets.swift` (`suggestAdjustment`) |
| Add a tracked health marker | `Domain/Models.swift` (`HealthMarkerKind`) → `Features/Progress/ProgressView.swift` (`resetMarkers` array) |
| Change daily steps goal | `Domain/Targets.swift` (`ModeRules.stepsDaily`) |
| Wire a new HealthKit metric | `Services/HealthKitService.swift` + add `@Model` snapshot type if persisted |
| New tab in the app shell | `App/RootView.swift` `Tab` enum + new folder under `Features/` |
| Schema change | `Data/Schema.swift` — add a new `VersionedSchema` and migration stage. Never edit shipped schemas. |
| Add HealthKit permission | `OurFitness.entitlements` (capability) + `Info.plist` (`NSHealthShareUsageDescription`) + `HealthKitService.requestAuth` |
| Change press feel / variants | `Components/TactileButtonStyle.swift` (`resolved(theme:)` switch) |
| Change haptic vocabulary | `Services/Haptics.swift` |
| New toast accent / haptic pairing | `Services/ToastCenter.swift` (`ToastAccent` enum + `fireHaptic(for:)`) |
| Tweak target-hit flash on bars | `Components/ProgressBar.swift` (`onChange(of: value)` block) |

---

## Data model essentials

All entities namespaced per `Profile`. Append-only logs (sets, food entries, body metrics, markers). Daily/weekly/streak/trend figures are *derived*, never stored.

`Domain/Models.swift` holds the value-type DTOs used by domain functions and view state. `Data/Models/*.swift` holds matching `@Model` classes used for persistence. A small adapter on each `@Model` (`var snapshot: ProfileDTO { ... }`) keeps the boundary explicit and tests cheap.

Headline entities:
- `Profile` — name, mode, biometrics, activity, restrictions, `computedTargets`
- `MacroTargets` — calories/protein/carbs/fat + `stepsDaily`, plus optional Reset caps
- `Exercise`, `WorkoutSet`, `Workout`, `Program` — full gym programming
- `Food`, `FoodLogEntry` — `modeFit` gates suggestions; log entries denormalize macros
- `BodyMetric` — weight, body-fat, waist
- `HealthMarker` — BP, LDL/HDL, triglycerides, A1c, fasting glucose, resting HR (Reset-critical)
- `StepCount` — one row per user per day (UPSERT); `source: .manual | .appleHealth`

---

## Mode behaviors

**Suggestion algorithm** (same shape, different scoring): filter by `modeFit`, allergens, slot; for Reset also filter against today's remaining sodium/sugar/sat-fat headroom. Score and return top 5. Build rewards calorie density + liquid (if `lowAppetite`) + cost + protein-gap fill. Reset rewards fiber + satiety + omega-3 + low sodium + protein-per-calorie.

**14-day auto-adjust** (suggests, never mutates):
- Build stalled → +200 cal/day; gaining >0.75 lb/wk → drop a multiplier
- Reset stalled → −150 cal/day or +1 cardio; losing >1.5 lb/wk → +150 cal (protect muscle); marker not moving after 8 weeks → flag for doctor, never prescribe

---

## HealthKit integration

`Services/HealthKitService.swift` owns all HealthKit access. Two modes of use:

1. **Pull on demand** — `todaySteps(for: profile)` returns a fresh number for the Today card.
2. **Observers** — registered at app launch to wake the app for background step updates (delivered via `HKObserverQuery`), then upsert into the `StepCount` table so trends/streaks just work.

Permissions requested at onboarding:
- Read: stepCount, bodyMass, restingHeartRate, activeEnergyBurned
- Write: workouts (so logged sessions show up in Apple Health), bodyMass (so weighing in the app updates Health)

The simulator can't return real Health data — develop UI in the sim, verify HealthKit on a real iPhone.

---

## Design direction

Two visual personalities under one shell. Mode picks palette + energy. Typography shared via dynamic type with custom fonts (Bebas Neue for display numerals, Fraunces serif for accents, SF Mono for stat readouts — falls back to system fonts gracefully).

- **Build:** warm dark, orange/amber/cream (matches [nutrition-plan.html](nutrition-plan.html))
- **Reset:** warm light, sage/terracotta — calmer, "steady reset"

Shared: large headlines, generous whitespace, weekly trend > daily pass/fail, no streak-shame, persistent banners (allergens on Build, caps remaining on Reset).

System dark mode follows the user's iOS setting; mode tokens override at the screen root via `ThemeProvider`.

### Tactile UX (load-bearing — the app feels alive)

The app is built to feel like a participant, not a form. Every meaningful interaction is multisensory: visible state change + spring animation + haptic + (for wins) a brief toast.

**Components that own the feel:**

| Concern | Lives in | Notes |
|---|---|---|
| All button presses | `Components/TactileButtonStyle.swift` | Five variants (`primary`/`secondary`/`pill`/`bump`/`ghost`); subtle top-edge highlight at rest, spring scale-down on press, optional glare sweep on `primary`, light haptic tick on touch-down |
| Tappable cards (whole card is the action) | `Components/PressableCard.swift` | Same press feel, no glare, accent stroke on press |
| Number readouts (stats) | `Components/AnimatedNumber.swift` | `.contentTransition(.numericText())` + spring tween; never snaps |
| Progress bars | `Components/ProgressBar.swift` | Smooth spring fill; **success haptic + bright flash** when value crosses target |
| Confirmations | `Services/ToastCenter.swift` + `Components/ToastView.swift` | One-toast-at-a-time, animates from top, auto-dismiss ~1.8s; fires matching haptic |
| All haptics | `Services/Haptics.swift` | Five named patterns (`tap`/`bump`/`success`/`warn`/`selection`) — keep the vocabulary small |

**Rules:**

1. **Every `Button` uses `.tactile(...)`.** Never `buttonStyle(.plain)` or default styling.
2. **Every meaningful mutation fires a toast.** Logged a meal → `toasts.logged(...)`. Beat a PR → `toasts.pr(...)`. Goal hit → `toasts.goalHit(...)`.
3. **Don't add a 6th button variant.** Reuse one. Visual noise is the enemy of "wants to keep clicking."
4. **Don't double-haptic.** `.tactile()` already fires `.sensoryFeedback(.impact)` on press. Don't also call `Haptics.tap()` in the action closure. Use `Haptics.bump()` / `.success()` / `.warn()` for *outcome* feedback, not press feedback.
5. **Whole-card-as-button beats inline buttons inside a card.** Use `PressableCard` and drop the redundant "LOG IT" button.

---

## Non-goals (v1)

No third user. No medical advice. No social/sharing/leaderboards. No barcode scan / restaurants / Instacart. No notifications until the daily loop is solid. No Apple Watch app (yet — likely v2 once daily loop is loved).

---

## Build order

1. Onboarding + profile creation + HealthKit permission request
2. Today view (bars, steps from HealthKit, log a meal, log a set)
3. Suggestion engine surfaced in Today
4. Workouts: program picker → block runner → set logger with progression target
5. Progress: weight + steps + markers + lift PRs
6. Nutrition library browser
7. Weekly planner + grocery list
8. Export/import (JSON + SwiftData .store cold backup)
9. 14-day auto-adjust signals as suggestion cards
10. Apple Watch companion (post-v1)

**Ship #1–4 before anything below. The daily loop is the product.**

---

## Foundation references

- [RepCheck.md](RepCheck.md) — friction-free logging UX; the bar for one-tap actions
- [nutrition-plan-research.md](nutrition-plan-research.md) — validated Build nutrition spec; food library, math, anchor schedule
- [nutrition-plan.html](nutrition-plan.html) — Build visual reference (look/feel, not codebase)
- [README.md](README.md) — local setup, XcodeGen, TestFlight CI
