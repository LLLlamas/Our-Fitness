# Our-Fitness — agent guide

Native iOS / SwiftUI app (App Store target). One profile per install. Two modes:

- **Build** — gain lean mass. Picky-eater hardgainer + basketball. Calorie surplus, hypertrophy (6–12 reps), nut-free allergen lock.
- **Circuit** — drop weight, fix heart-health markers (cholesterol, BP, blood sugar). Steps + cardio + Pilates + parenting movements; fibre-forward, low-sodium. No allergens.

> `Mode.circuit` is the Swift symbol; its SwiftData raw value stays `"reset"` for back-compat (needs a schema migration to change). All UI copy says "Circuit".

**`CLAUDE.md` is the source of truth** — codebase map, the "Where to touch" routing table, calorie math, design rules, schema, and CI specifics. Read it first; this file is only the non-negotiable guardrails.

## Hard rules (breaking these breaks the app)

1. `Domain/` never imports SwiftData or SwiftUI — pure Swift, fully unit-tested.
2. `Features/` use repositories or `@Query`, never open the `ModelContainer` directly.
3. Per-profile `@Query` must predicate-scope (`#Predicate { $0.userId == uid }`) — never `.filter` client-side.
4. HealthKit only via `Services/HealthKitService.swift`. Call `requestAuthorization` ONLY from an explicit user Connect flow (it throws an uncatchable NSException); add only quantity types to read/write sets (correlation types crash auth).
5. `.swift` filenames unique in the target; all `@Model` classes live in `Data/PersistenceModels.swift`.
6. Append-only logs; derived figures (daily/weekly/streak) are never stored. DTOs in `Domain/Models.swift`, `@Model` in `Data/PersistenceModels.swift` with `snapshot` adapters, CRUD in `Data/Repositories/Repositories.swift`.
7. Never hardcode kcal — `MET × bodyWeightKg × hours` (`Domain/CalorieEstimator.swift`). Food/exercise numbers are real (USDA / reference), never model-invented.

## Build / CI (local Mac)

- **Development runs on a MacBook Pro (M5 Pro, macOS 26.6) with Xcode 26.6, Swift 6.3.3, XcodeGen 2.46.** The old mac-less loop is retired. Build and test locally; do not push to CI to discover compile errors.
  ```bash
  xcodegen generate    # only after editing project.yml
  xcodebuild -project OurFitness.xcodeproj -scheme OurFitness \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E '(error:|BUILD)'
  ```
- `compile.yml` still runs on push as a clean-room check. A failure there that passed locally = environment drift (stale DerivedData, untracked file), not a Swift error.
- TestFlight ships via `testflight.yml`; local `bundle exec fastlane beta` / Xcode Organizer is now viable. Signing is still manual-style + match — don't switch to automatic signing without migrating `testflight.yml` in the same change (see `docs/setup.md`).
- Tests are **hostless** — `OurFitnessTests` compiles `Domain/` directly, no `@testable import`. Never use a bare `Date()` in streak/weekly tests; pin `now`.
- XcodeGen (`project.yml`) generates the gitignored `.xcodeproj`. Never put `info:`/`entitlements:` blocks on a target — use `INFOPLIST_FILE` / `CODE_SIGN_ENTITLEMENTS` settings.

Everything else: `CLAUDE.md`. Incident history + setup: `docs/`.
