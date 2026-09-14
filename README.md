# Our Fitness

A native iOS fitness app for two modes: **Build** (gain mass, fuel hoops) and **Circuit** (drop weight, fix cardiovascular markers). SwiftUI, SwiftData, Apple Health integration — no backend, no subscription.

Show up, log honestly, let the numbers tell the truth.

---

## Modes

| | Build | Circuit |
|---|---|---|
| Calories | TDEE + 400–600 surplus | TDEE − 300–500 deficit |
| Protein | ~1 g/lb | 1.0–1.2 g/lb |
| Steps/day | 8,000 | 10,000 |
| Focus | Strength, rep/set tracking, isometric holds | Parenting movement, Pilates, steps, cardio markers |

One profile per install; mode is changeable in Settings. The app stores data locally and syncs selected snapshots and photos to a paired Apple Watch, which caches them locally. Apple Health access and notification/Lock Screen surfaces also handle selected data. See the [privacy and security account](docs/privacy-security.md) for the current data flows and limitations.

---

## Docs

- [CLAUDE.md](CLAUDE.md) — architecture, codebase map, where-to-touch for every feature
- [docs/privacy-security.md](docs/privacy-security.md) — current data flows, storage, privacy controls, and security limitations
- [docs/watch-app-setup.md](docs/watch-app-setup.md) — watch features, signing, and device verification
- [docs/setup.md](docs/setup.md) — one-time Apple/GitHub setup, CI workflows, TestFlight operations
- [docs/ci-history.md](docs/ci-history.md) — incident narratives behind every CI rule
- [docs/live-activity-setup.md](docs/live-activity-setup.md) — Live Activity / widget signing checklist
- [docs/RepCheck.md](docs/RepCheck.md) — friction-free logging UX
- [docs/nutrition-plan-research.md](docs/nutrition-plan-research.md) — Build nutrition spec
- [docs/medication-reminders-plan.md](docs/medication-reminders-plan.md) — medication logging spec, with the notification wording rules it ships under

### Audit maintenance

See [the active handoff](docs/audit-handoff.md) for remediation status and verified
checks, and [privacy/security](docs/privacy-security.md) for current data flows
and remaining release/privacy work. The scheme runs both the hostless Domain
suite and a separate persistence/session regression suite.
