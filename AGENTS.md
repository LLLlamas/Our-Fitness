# Our-Fitness — agent guide

Native iOS / SwiftUI app (App Store target). **[CLAUDE.md](CLAUDE.md) is the single source of truth** — read it first; it holds the goal rules, codebase map, hard architectural rules, build commands and the "Find it fast" routing to `docs/map/*.md`. This file deliberately restates nothing so it cannot drift. The index of every doc, with its status, is [docs/README.md](docs/README.md).

## Non-negotiable rules (by reference)

- The nine hard architectural rules in [CLAUDE.md](CLAUDE.md) → "Hard architectural rules" (Domain purity, predicate-scoped `@Query`, HealthKit entry points, unique filenames, hostless tests, Foundation-only shared contracts, one surface per job, every `Repos` write returns success and callers guard it).
- HealthKit authorization crash traps: [CLAUDE.md](CLAUDE.md) → "HealthKit crash traps".
- Calorie math is written once, net of resting: [docs/calorie-math.md](docs/calorie-math.md). Never hardcode kcal.
- Persisted raw values and schema rules: [docs/data-model.md](docs/data-model.md). Bump a schema version before changing a persisted raw value.
- Before changing any health or fitness number: [docs/health-data-audit.md](docs/health-data-audit.md).
- Watch wire format (one envelope, one context key): [docs/map/reminders-watch.md](docs/map/reminders-watch.md).

## Working agreements

- Build and test locally ([CLAUDE.md](CLAUDE.md) → "Build and test"; details in [docs/ci.md](docs/ci.md)); do not push to CI to discover compile errors.
- Edit the matching `docs/map/` row in the same commit as the code it describes; record what was actually verified in [docs/validation-log.md](docs/validation-log.md) and never claim unbuilt or untested edits are complete.
- Handoffs: record unverified edits explicitly. A successor reads `CLAUDE.md`, the latest handoff note, and current `git status` / `git diff` first. The open backlog is [docs/next-audit-scope.md](docs/next-audit-scope.md); [docs/audit-handoff.md](docs/audit-handoff.md) is a historical record.
