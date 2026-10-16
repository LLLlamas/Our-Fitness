# Calorie math

> Moved from CLAUDE.md. Keep this file in the same commit as any change to `Domain/CalorieEstimator.swift`, `Domain/DailyBurn.swift` or `Domain/ActivityCatalog.swift`. See also [health-data-audit.md](health-data-audit.md) before changing any health number.

Formula: **`kcal = (MET − 1) × bodyWeightKg × hours`** — written once, in `Domain/CalorieEstimator.swift`.

Ainsworth 2011 METs are **gross**: 1.0 MET *is* resting metabolism, so `MET × kg × hours` includes the calories you'd have burned sitting still for the same stretch. Every figure the app labels "active" / "burn" sits beside Apple Health's active energy, which is net of resting — so the estimator subtracts that one resting MET. Sub-resting METs clamp to zero. The gross product is `private` and nothing needs it: `Domain/Targets.swift` derives TDEE independently (Mifflin-St Jeor BMR × activity multiplier) and consumes nothing from `CalorieEstimator`. If a surface ever genuinely wants gross, add a gross entry point — don't drop the −1.

| Activity | MET (gross, as published) | Net multiplier used |
|---|---|---|
| Steps (3.5 mph) | 4.3 | 3.3 |
| Pilates | 3.0 | 2.0 |
| Resistance | 4.0–8.0 (see `Domain/ExerciseInfo.swift`) | 3.0–7.0 |
| Isometric hold | 3.8 default | 2.8 |
| Loaded carry, by duration (`caloriesForDuration`, `loadLb != nil`) | 4.5 | 3.5 |
| Logged cardio (run/bike/swim/…) | per-activity, `Domain/ActivityCatalog.swift` | MET − 1 |
| Live sessions | 2.8–11.8 (see `Domain/ActivityCatalog.swift`) | 1.8–10.8 |

Never hardcode kcal/rep — always (MET − 1) × weight × time.

**Never double-count steps.** Sessions whose movement the day's step count already contains are dropped from the day total by `Domain/DailyBurn.swift`: `stepOverlappingCardio` (`.walk`, `.run`) and `stepOverlappingActivityIds` (walking, running, hiking). `Activity.tracksDistance` is **not** that signal — cycling tracks distance but registers no steps, so excluding it would lose the ride entirely. Any surface that lists the contributing sessions must filter on those two sets (see `MoveCard.countedCardio` / `countedActivities`) so the rows add up to the total.
