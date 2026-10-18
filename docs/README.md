# Docs index

Start at [../CLAUDE.md](../CLAUDE.md) (thin: rules, map, build commands, routing). It points here and to `map/`. Load only what the task needs. Where a doc and the code disagree, the code wins.

Status key: **Living** = describes current behavior, update it in the same commit as the code. **Plan** = proposed or partly built, not authoritative. **Historical** = a dated record, kept for reasoning, never current guidance. **Shelved** = deliberately dropped for now.

## Living reference

| Doc | Status | What it is |
|---|---|---|
| [map/workouts.md](map/workouts.md) | Living | Train tab: exercises, rep counter, hold timer, set editing, live sessions, optional sections, cardio logging, workout AI |
| [map/nutrition.md](map/nutrition.md) | Living | Meals tab: food parser and DB, Add food, restaurant menus, label scanner, meal AI, heart-health micros, target math |
| [map/today-steps.md](map/today-steps.md) | Living | Today tab: Move and Steps cards, water, burn estimate, encouragement, nudges, meal push reminders |
| [map/watch.md](map/watch.md) | Living | Watch app and sync wire format |
| [map/progress.md](map/progress.md) | Living | Progress tab: trackers, stat sheet, strength, tape measurements, energy balance, history |
| [map/settings-health.md](map/settings-health.md) | Living | Settings, profile, goal rules in detail, HealthKit services, schema migration |
| [map/ui-components.md](map/ui-components.md) | Living | Shared components and services (buttons, rings, info sheets, haptics, toasts) |
| [calorie-math.md](calorie-math.md) | Living | Net-MET formula, per-activity multipliers, step-overlap rule |
| [data-model.md](data-model.md) | Living | Entities, append-only logs, legacy cardio rows, pinned raw values |
| [ci.md](ci.md) | Living | Local build/test, UI smoke test, signing, XcodeGen and TestFlight rules |
| [setup.md](setup.md) | Living | One-time Apple/GitHub setup, secrets, TestFlight operations |
| [privacy-security.md](privacy-security.md) | Living | Current data flows, storage, privacy controls, security limitations (as of 2026-09-14) |
| [watch-app-setup.md](watch-app-setup.md) | Living | Watch features, signing checklist, device verification |
| [live-activity-setup.md](live-activity-setup.md) | Living | Live Activity / widget signing checklist |
| [health-data-audit.md](health-data-audit.md) | Living | Read before changing any health or fitness number: what was fixed, what is verified, open sourcing questions |
| [next-audit-scope.md](next-audit-scope.md) | Living | Open backlog: privacy controls, erase-local-data, measured performance |
| [medication-reminders-plan.md](medication-reminders-plan.md) | Retired (feature removed; see [removed-reminders.md](removed-reminders.md)) | Medication logging spec as shipped; its safety wording rules (sections 12 and 16) are binding |

## Plans (not authoritative)

| Doc | Status | What it is |
|---|---|---|
| [progress-tracking-plan.md](progress-tracking-plan.md) | Plan, implemented on branch (Oct 2026), not yet compiled in Xcode | Progress as reps at a weight over all history, "last time" and same-day-last-week comparisons, editable fixed loads. Banner lists what was built, deferred and unverified; the map rows describe current behavior |
| [app-expansion.md](app-expansion.md) | Plan | Phase 2/3 roadmap: iCloud sync, store polish (Phase 1 shipped) |

## Shelved

| Doc | Status | What it is |
|---|---|---|
| [cardio-fitness-plan.md](cardio-fitness-plan.md) | Shelved | VO₂ max and slow cardio base-building. The owner dropped it for now (Oct 2026); kept as research, and its safety rules would bind any future cardio feature |

## Historical records

| Doc | Status | What it is |
|---|---|---|
| [validation-log.md](validation-log.md) | Historical, append-only | What was verified and not at each milestone, including the 2026-09 audit handoff notes |
| [audit-handoff.md](audit-handoff.md) | Historical | The 2026-09-14 remediation session, superseded 14 Oct 2026 |
| [ci-history.md](ci-history.md) | Historical | Incident narratives behind each CI "do not regress" rule |
| [encouragement-system-plan.md](encouragement-system-plan.md) | Historical | Encouragement design plan, partly shipped, written for the old two-mode app |
| [health-tracking-ui-plan.md](health-tracking-ui-plan.md) | Historical | Health UI refresh spec, written for the old two-mode app |
| [activity-and-ai-expansion-research.md](activity-and-ai-expansion-research.md) | Historical | Activity and AI research, written for the old two-mode app |
| [nutrition-plan-research.md](nutrition-plan-research.md) | Historical | Original nutrition research and spec (old Build mode) |
| [RepCheck.md](RepCheck.md) | Historical | UX reference from the predecessor web tracker; only its low-friction logging ideas still apply |
