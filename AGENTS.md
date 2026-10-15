# Our-Fitness — agent guide

Native iOS / SwiftUI app (App Store target). One profile per install, one light-theme app (`Theme.standard`) where every surface is the same for everyone.

Each profile has a **fitness goal** (`FitnessGoal`), switchable in Settings:

- **Build muscle** (`.gain`) — calorie surplus, 1.0 g/lb protein, 8,000 default steps.
- **Lose weight** (`.lose`) — calorie deficit, 1.1 g/lb protein, 10,000 default steps.

The goal only changes target numbers (`Domain/Targets.swift` → `GoalRules`) and soft ranking/copy tilts. Heart-health targets (fiber floor; sodium, added-sugar, saturated-fat caps) apply to everyone (`Targets.HeartHealth`). There are no modes any more — never show, hide or restyle a card based on the goal.

> Persisted raw values are pinned to the retired mode names: `.gain` = `"build"`, `.lose` = `"reset"` (column `ProfileModel.modeRaw`), and the watch wire key is still `mode`. Bump a schema version before changing either. `ProfileDTO.restrictions` (allergens) is honoured by the meal rankers, but no UI sets it today — there is no allergen lock in the app.

**`CLAUDE.md` is the source of truth** — codebase map, the "Where to touch" routing table, calorie math, design rules, schema, and CI specifics. Read it first; this file is only the non-negotiable guardrails.

## Hard rules (breaking these breaks the app)

1. `Domain/` never imports SwiftData or SwiftUI — pure Swift, tested by the hostless Domain test target.
2. `Features/` use repositories or `@Query`, never open the `ModelContainer` directly.
3. Per-profile `@Query` must predicate-scope (`#Predicate { $0.userId == uid }`) — never `.filter` client-side.
4. Phone HealthKit access only via `Services/HealthKitService.swift`; the watch owns workout sessions in `OurFitnessWatch/WatchWorkoutSession.swift`. Authorization is only from an explicit Connect flow on the phone or Start-workout action on the watch, never a lifecycle callback. Preserve the correlation-type crash guard: phone read/write sets contain quantity types; the watch additionally requests `HKObjectType.workoutType()` for workout writes.
5. `.swift` filenames unique in the target; all `@Model` classes live in `Data/PersistenceModels.swift`.
6. Append-only logs; derived figures (daily/weekly/streak) are never stored. DTOs in `Domain/Models.swift`, `@Model` in `Data/PersistenceModels.swift` with `snapshot` adapters, CRUD in `Data/Repositories/Repositories.swift`. Every `Repos` write returns success; callers `guard` it before dismissing, toasting or celebrating.
7. Never hardcode kcal — `(MET − 1) × bodyWeightKg × hours`, written once in `Domain/CalorieEstimator.swift` (net of resting; see CLAUDE.md → Calorie math). Food/exercise numbers are real (USDA / reference), never model-invented.
8. One surface per job — find the existing card/sheet/row and extend it rather than adding a second (CLAUDE.md hard rule 8).

## Milestone documentation

Each milestone commit must include updates to affected Markdown guidance alongside the code: current behavior, architecture/routing changes, validation performed, and outstanding limitations. Preserve dated incident/research documents as history; mark superseded instructions rather than presenting them as current implementation work.

## Build / CI (local-first)

- **Development runs on a MacBook Pro (M5 Pro, macOS 26.6) with Xcode 26.6, Swift 6.3.3, XcodeGen 2.46.** The old mac-less loop is retired. Build and test locally; do not push to CI to discover compile errors.
  ```bash
  set -o pipefail
  xcodegen generate    # only after editing project.yml
  xcodebuild -project OurFitness.xcodeproj -scheme OurFitness \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E '(error:|BUILD)'
  ```
  The fastlane lanes wrap the same thing: `bundle exec fastlane ios compile` / `ios tests` (or Xcode ⌘R/⌘U). Green local build + tests = it builds.
- `compile.yml` still runs on push as a clean-room check. A failure there that passed locally = environment drift (stale DerivedData, untracked file), not a Swift error.
- TestFlight ships via `testflight.yml`; local `bundle exec fastlane beta` / Xcode Organizer is now viable. Signing is still manual-style + match — don't switch to automatic signing without migrating `testflight.yml` in the same change (see `docs/setup.md`).
- Tests are **hostless** — `OurFitnessTests` compiles `Domain/` directly, no `@testable import`. Never use a bare `Date()` in streak/weekly tests; pin `now`.
- XcodeGen (`project.yml`) generates the gitignored `.xcodeproj`. Never put `info:`/`entitlements:` blocks on a target — use `INFOPLIST_FILE` / `CODE_SIGN_ENTITLEMENTS` settings.

Everything else: `CLAUDE.md`. Incident history + setup: `docs/`.

## Usage limits and handoffs

During active remediation keep a handoff checkpoint current (`docs/audit-handoff.md` is the now-historical 2026-09-14 one; the open backlog is `docs/next-audit-scope.md`). Before usage runs
low or work pauses, checkpoint completed and incomplete edits, exact next steps,
validation results, pending decisions, and pre-existing user changes. Update the
checkpoint after each milestone; never label unbuilt/untested edits complete.
A successor reads `CLAUDE.md`, the checkpoint, and current git status/diff first.
