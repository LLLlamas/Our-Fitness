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

## Build / CI (mac-less)

- No local Xcode. Loop: **push → `compile.yml` builds + tests → patch → push.** Green CI = it builds.
- Tests are **hostless** — `OurFitnessTests` compiles `Domain/` directly, no `@testable import`. Never use a bare `Date()` in streak/weekly tests; pin `now`.
- XcodeGen (`project.yml`) generates the gitignored `.xcodeproj`. Never put `info:`/`entitlements:` blocks on a target — use `INFOPLIST_FILE` / `CODE_SIGN_ENTITLEMENTS` settings.

Everything else: `CLAUDE.md`. Incident history + setup: `docs/`.
