# Our-Fitness — Foundation (iOS / SwiftUI)

Native iOS app targeting App Store release, one profile per install. One app for everyone: the profile's **fitness goal** (`FitnessGoal.gain` "Build muscle" / `.lose` "Lose weight") only changes target numbers and soft tilts — never show, hide or restyle a surface by goal. Persisted raw values are pinned to the retired mode names (`.gain` = `"build"`, `.lose` = `"reset"`, column `ProfileModel.modeRaw`, watch wire field `mode`): bump a schema version before changing any of them ([docs/data-model.md](docs/data-model.md)). `_stashed/` = excluded from the build target.

**Doc index with status of every doc: [docs/README.md](docs/README.md).** Read only the `docs/map/` file for the area you are touching, not all of them.

## Goals

`Domain/Targets.swift` → `Targets.rules` (`GoalRules`) is the only per-goal number set:

| | `.gain` (Build muscle) | `.lose` (Lose weight) |
|---|---|---|
| Calories | TDEE + 500 | TDEE − 400 (floor 1,200 either way) |
| Protein g/lb | 1.0 | 1.1 |
| Fat % of calories | 27% | 28% |
| Default steps/day | 8,000 | 10,000 |

Everything else about goals (nudge thresholds, soft tilts, heart-health micros, starter movements): [docs/map/settings-health.md](docs/map/settings-health.md) → "Goal rules in detail".

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

## HealthKit crash traps (caused SIGABRT in build 37)

- Authorization configuration errors raise uncatchable `NSException` — call ONLY from an explicit phone Connect flow or watch Start-workout action. Never from `.task`/`.onAppear`.
- Phone `readTypes`/`writeTypes` contain quantity types; preserve the correlation-type crash guard (e.g. blood pressure). The watch also requests `HKObjectType.workoutType()` for `HKWorkoutSession`.

## Calorie math

**`kcal = (MET − 1) × bodyWeightKg × hours`**, written once in `Domain/CalorieEstimator.swift` (METs are gross; the −1 makes it net of resting, matching Apple Health active energy). Never hardcode kcal/rep. Never double-count steps: sessions the step count already contains are dropped by `Domain/DailyBurn.swift`. Tables and details: [docs/calorie-math.md](docs/calorie-math.md).

## Build and test (local-first)

Build and test locally on the Mac — never push to CI to find out whether Swift compiles. Tests are hostless; never a bare `Date()` in streak/weekly tests (pin `now`).

```bash
set -o pipefail
xcodegen generate    # only after editing project.yml
xcodebuild -project OurFitness.xcodeproj -scheme OurFitness \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E '(error:|BUILD)'
```

Tests: `bundle exec fastlane ios tests` (after `xcodegen generate`). UI smoke test, simulator conventions, signing, XcodeGen and TestFlight rules: [docs/ci.md](docs/ci.md). Stack: SwiftUI (iOS 17+), SwiftData, HealthKit, Swift Charts, XCTest, XcodeGen, Fastlane; no backend.

## Design rules

- One warm-light palette for everyone: `Theme.standard` (`Services/Theme.swift`, the `\.theme` environment default). Keep `AccentColor`, `LaunchBackground` and the widget palette equal when retuning.
- **"cal" not "kcal"** in all UI strings.
- Every interaction: state change + spring animation + haptic + (wins) toast.
- Sheet backgrounds `.presentationBackground(theme.bg)`; ⓘ buttons are `.sheet` with `.presentationDetents([.medium])`, never `.popover`; numeric keyboards get a `ToolbarItemGroup(placement: .keyboard)` Done button.
- Corner radii (cards 16, inline borders 12, buttons 10, pills 20, `ProgressBar` capsule) and the shared components: [docs/map/ui-components.md](docs/map/ui-components.md).

## Find it fast

Each `docs/map/` file is a table of "goal → file(s) and the rules that bind them". **Edit the matching row in the same commit as the code** (add a row for a new surface). If a row and the code disagree, the code wins and the row is a bug — fix it.

| Area | Open | Scope |
|---|---|---|
| Train tab | [docs/map/workouts.md](docs/map/workouts.md) | Exercises, rep counter and rep history, hold timer, set editing, live sessions, Pilates/Yoga/Stretching sections, cardio logging, exercise MET data, workout AI |
| Meals tab | [docs/map/nutrition.md](docs/map/nutrition.md) | Food parser and DB, Add food, restaurant menus, label scanner, meal AI, meal log UI, heart-health micros, target math |
| Today tab | [docs/map/today-steps.md](docs/map/today-steps.md) | Move card, Steps card, water, burn estimate, encouragement, nudges, meal push reminders |
| Watch | [docs/map/watch.md](docs/map/watch.md) | Watch app, sync wire format, on-wrist workouts. (Reminders/plants/medication were removed: [docs/removed-reminders.md](docs/removed-reminders.md)) |
| Progress tab | [docs/map/progress.md](docs/map/progress.md) | Trackers, stat detail sheet, weekly reps, strength card, tape measurements, weeks, energy balance, history |
| Settings, HealthKit, schema | [docs/map/settings-health.md](docs/map/settings-health.md) | Vitals, goal switch, onboarding, tab layout, units, HealthKit services, schema migration, goal rules in detail |
| Shared UI | [docs/map/ui-components.md](docs/map/ui-components.md) | Buttons, rings, info sheets, goal picker, haptics, toasts, freshness |
| Calorie math | [docs/calorie-math.md](docs/calorie-math.md) | Net-MET formula, per-activity multipliers, step-overlap rule |
| Data model | [docs/data-model.md](docs/data-model.md) | Entities, append-only logs, legacy `CardioSessionDTO`, pinned raw values |
| CI / signing / TestFlight | [docs/ci.md](docs/ci.md) | Local commands, UI smoke test, signing, XcodeGen rules; incident history in [docs/ci-history.md](docs/ci-history.md) |
| Validation history | [docs/validation-log.md](docs/validation-log.md) | What was verified and not at each milestone, audit handoff (historical) |

## Milestone documentation

Update affected Markdown in every milestone commit alongside its code (current behavior, routing changes, validation actually performed, remaining limitations). Append validation records to [docs/validation-log.md](docs/validation-log.md); never claim tests or signing state were verified without evidence. Before changing any health/fitness number read [docs/health-data-audit.md](docs/health-data-audit.md). Open backlog: [docs/next-audit-scope.md](docs/next-audit-scope.md). When a session hands off, record unverified edits explicitly.
