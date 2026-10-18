# Our Fitness

A native iOS fitness app: log meals, training, steps and water in one place, with targets tuned to your goal — **Build muscle** or **Lose weight**. SwiftUI, SwiftData, Apple Health integration — no backend, no subscription.

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

- [CLAUDE.md](CLAUDE.md) — architecture, codebase map, where-to-touch for every feature
- [docs/privacy-security.md](docs/privacy-security.md) — current data flows, storage, privacy controls, and security limitations
- [docs/watch-app-setup.md](docs/watch-app-setup.md) — watch features, signing, and device verification
- [docs/setup.md](docs/setup.md) — one-time Apple/GitHub setup, CI workflows, TestFlight operations
- [docs/ci-history.md](docs/ci-history.md) — incident narratives behind every CI rule
- [docs/live-activity-setup.md](docs/live-activity-setup.md) — Live Activity / widget signing checklist
- [docs/RepCheck.md](docs/RepCheck.md) — friction-free logging UX
- [docs/nutrition-plan-research.md](docs/nutrition-plan-research.md) — original nutrition spec (written for the old Build mode; now informs the Build muscle goal)
- [docs/removed-reminders.md](docs/removed-reminders.md) — Reminders/plants/medication removal, retired-feature notes, leftover DB tables

### Audit maintenance

[docs/next-audit-scope.md](docs/next-audit-scope.md) is the open backlog;
[docs/audit-handoff.md](docs/audit-handoff.md) is the historical record of the
September 2026 remediation. See [privacy/security](docs/privacy-security.md) for
current data flows and remaining release/privacy work. The scheme runs both the hostless Domain
suite and a separate persistence/session regression suite.
