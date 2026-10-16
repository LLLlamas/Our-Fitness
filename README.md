# Our Fitness

A native iOS fitness app: log meals, training, steps, water and reminders in one place, with targets tuned to your goal — **Build muscle** or **Lose weight**. SwiftUI, SwiftData, Apple Health integration — no backend, no subscription.

Show up, log honestly, let the numbers tell the truth.

---

## Goals

Every screen is the same for everyone. Your goal only changes the numbers (calorie, protein and fat targets, the default step goal) and gently tilts suggestions and encouragement copy. Values from `OurFitness/Domain/Targets.swift`:

| | Build muscle | Lose weight |
|---|---|---|
| Calories | TDEE + 500 | TDEE − 400 |
| Protein | 1.0 g/lb | 1.1 g/lb |
| Fat | 27% of calories | 28% of calories |
| Default steps/day | 8,000 | 10,000 |

Heart-health targets apply to everyone: fiber ≥ 35 g, sodium ≤ 1,500 mg, added sugar ≤ 25 g, saturated fat ≤ 10% of calories.

One profile per install; the goal is changeable in Settings. The app stores data locally and syncs selected snapshots and photos to a paired Apple Watch, which caches them locally. Apple Health access and notification/Lock Screen surfaces also handle selected data. See the [privacy and security account](docs/privacy-security.md) for the current data flows and limitations.

---

## Getting started

Requires Xcode 26.x (stable) with the iOS simulator runtime downloaded.

```bash
brew install xcodegen && bundle install
xcodegen generate            # .xcodeproj is gitignored — re-run after project.yml changes
open OurFitness.xcodeproj    # ⌘R to run, ⌘U to test
```

CLI: `bundle exec fastlane ios compile` (build) / `bundle exec fastlane ios tests` (unit tests). TestFlight releases + full setup: [docs/setup.md](docs/setup.md).

---

## Docs

- [CLAUDE.md](CLAUDE.md) — architecture rules, codebase map and routing; start here
- [docs/README.md](docs/README.md) — index of every doc with its status (living reference / plan / historical / shelved)
- [docs/map/](docs/map) — per-area "where to touch" tables (workouts, nutrition, today, reminders + watch, progress, settings + health, UI components)
- [docs/calorie-math.md](docs/calorie-math.md), [docs/data-model.md](docs/data-model.md), [docs/ci.md](docs/ci.md) — calorie formula, persistence rules, CI and signing
- [docs/setup.md](docs/setup.md) — one-time Apple/GitHub setup and TestFlight operations
- [docs/privacy-security.md](docs/privacy-security.md) — current data flows, storage, privacy controls and security limitations
- [docs/watch-app-setup.md](docs/watch-app-setup.md) — watch features, signing and device verification
- [docs/next-audit-scope.md](docs/next-audit-scope.md) — the open backlog (privacy controls, erase-local-data, measured performance)

The scheme runs both the hostless Domain suite and a separate persistence/session regression suite.
