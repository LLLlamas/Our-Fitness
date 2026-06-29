# Our Fitness

A native iOS fitness app for two modes: **Build** (gain mass, fuel hoops) and **Reset** (drop weight, fix cardiovascular markers). SwiftUI, SwiftData, Apple Health integration — no backend, no subscription.

Show up, log honestly, let the numbers tell the truth.

---

## Modes

| | Build | Reset |
|---|---|---|
| Calories | TDEE + 400–600 surplus | TDEE − 300–500 deficit |
| Protein | ~1 g/lb | 1.0–1.2 g/lb |
| Steps/day | 8,000 | 10,000 |
| Focus | Strength, rep/set tracking, isometric holds | Parenting movement, Pilates, steps, cardio markers |

One profile per install. All data stays on-device. Mode is changeable at will in Settings.

---

## Docs

- [CLAUDE.md](CLAUDE.md) — architecture, codebase map, where-to-touch for every feature
- [docs/setup.md](docs/setup.md) — one-time Apple/GitHub setup, CI workflows, TestFlight operations
- [docs/ci-history.md](docs/ci-history.md) — incident narratives behind every CI rule
- [docs/live-activity-setup.md](docs/live-activity-setup.md) — Live Activity / widget signing checklist
- [docs/RepCheck.md](docs/RepCheck.md) — friction-free logging UX
- [docs/nutrition-plan-research.md](docs/nutrition-plan-research.md) — Build nutrition spec
