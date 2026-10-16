# Progress tracking plan: reps at a weight, over all history

> **Status: PLAN, not built (Oct 2026).** How the app tracks strength progress and
> encourages doing more over time. Nothing here is implemented yet; CLAUDE.md and the
> code stay authoritative for current behaviour.
>
> **Decisions (owner, Oct 2026):**
> 1. **No sets.** Progress is **reps, at what weight (if any)**. A day's reps for an exercise are summed per weight; set structure is ignored.
> 2. **All history, not this week.** Every comparison and "last time" reads the exercise's full history, not the current Monday week.
> 3. **Show decreases.** Comparisons may say "fewer reps than Tue" or "than last week"; that's information, not failure.
> 4. **Fixed loads are editable.** The baby's weight (any fixed-load exercise) can be updated, and history keeps the weight each rep was done at.
> 5. **Both comparison views:** "vs last time" and "vs same day last week" are shown side by side.
> 6. **Progress tracker = reps this week**, with notes based on the amount (§3.5).
> 7. **Exact weight matches** — 50 lb and 52.5 lb are different weights; no rounding buckets.
>
> **Evidence caveat.** The research behind §7 could not open primary papers (journal
> hosts were unreachable from the research sandbox). Figures are from search summaries or
> recall and are marked so. Per [health-data-audit](health-data-audit.md), verify any
> number against its DOI before it reaches UI copy. The design depends on none of them.

---

## 1. What exists today (verified in code)

| Piece | What it does | Gap for this plan |
|---|---|---|
| `WorkoutSetDTO` rows | One row per log: `reps`, `weightLb?`, `holdSeconds?`, `timestamp`. The rep counter writes one row per "Save set"; the one-tap +1 writes one row per rep | None for reps: **summing `reps` per day per weight already works for both paths**. Fixed-load rows store `weightLb: nil` (the load lives on the exercise) |
| `RepCounterView` pre-fill | Silently pre-fills weight + wheel from **this ISO week's** last row | Blank every Monday and for a lift done once a week; no visible "last time" |
| `Domain/StrengthProgress.swift` → Strength card | Best Epley estimated max per weighted lift, "+N lb · 4 wk" | Weighted lifts only. **`gainLb` can never be negative** (all-time best vs a subset of the same rows), so a decline reads "no change". Not tappable; no history view |
| `Domain/TrainingHistory.swift` | Day sessions for `TrainingHistorySheet`; weekly **row** counts for Progress › Training ("sets") | Counts rows, so ten baby +1 taps read as "10 sets". Rows carry no weight in the history list |
| `EncouragementEngine.workoutSetMessage` | "N sets this week for {muscle}" toast | Set-based, and the count is per exercise, not per muscle. Removed by this plan |
| `Domain/Progression.swift` | Set-based next-target schemes | Dead code (tests only). Not used by this plan; leave it (its enum is persisted) |
| Fixed-load exercises | `ExerciseDTO.loadLb` (Lifted Baby 30 lb, …) | **No `Repos.updateExercise`**; changing the load means delete + recreate, which deletes all history |
| `Repos.setHistory(userId:exerciseId:limit:)` | Exercise-scoped, newest-first fetch | Used only by the watch undo; the natural read for full history |

## 2. The model: reps at a weight

For each exercise and each day, fold the rows into **reps per weight**:

```
Bench press · Tue Oct 14   →  50 lb × 30 reps · 55 lb × 8 reps
Push-ups    · Tue Oct 14   →  bodyweight × 42 reps
Lifted Baby · Tue Oct 14   →  30 lb × 24 reps        (load stamped per row, §3.1)
Plank       · Tue Oct 14   →  longest hold 50 s · total 2 min 10 s
Carried Baby· Tue Oct 14   →  30 lb × 12 min
```

- **Weight key:** the row's exact `weightLb` (owner decision: exact matches, no rounding buckets); nil means "no weight" (bodyweight). Entry is typed, so to keep exact matching honest the weight field pre-fills the last weight used (§3.2) and the history view lists each distinct weight on its own line.
- **Day** = `Dates.dayKey`; **week** = Monday ISO week (`Dates.startOfISOWeek`), the app-wide definitions.
- Holds and duration exercises have no reps; their unit is seconds/minutes (longest hold and total time for holds, total minutes for duration). The same day/week folding applies.
- Everything is **derived on read** from the append-only rows, so editing or back-filling a row updates every comparison automatically. Nothing new is stored except the per-row load (§3.1).

One pure Domain type does this, e.g. `Domain/RepHistory.swift`:

```swift
RepHistory.days(for exercise: ExerciseDTO, rows: [WorkoutSetDTO]) -> [DayTally]
//  DayTally { dayKey, byWeight: [WeightKey: Int reps], totalReps, longestHoldSec?, totalSeconds? }
RepHistory.weeks(...) -> [WeekTally]       // same, folded by ISO week
RepHistory.compare(_ a: Tally, to b: Tally) -> Comparison
//  per weight: reps delta (+/-), plus "new weight" / "weight not done"
```

## 3. Plan, in build order

### 3.1 Data fixes (small, additive, no schema bump)

1. **Stamp the load on fixed-load rows.** `ExercisesCard.quickLog`, the rep counter and duration paths for loaded movements, and the watch `.logQuickSet` write `weightLb = exercise.loadLb` (the column exists).
   - A one-time Seeder backfill stamps existing nil-weight rows of `loadLb` exercises with the current `loadLb`. This is correct because the load could never change before step 2.
   - Check `StrengthProgress` still excludes these rows (it filters on `tracksPerSetWeight`).
2. **Edit the fixed weight: `Repos.updateExercise(id:name:loadLb:)`** (returns `Bool` via `RepositoryWrite`).
   - UI: a "Weight" row in `ExerciseInfoSheet` (the ONE per-exercise sheet) for any exercise with `loadLb`, e.g. "Lifted Baby · 30 lb · Update". It uses the same weight-field idiom as the rep counter (numeric keyboard + Done).
   - The new weight applies to rows logged **from now on**. History keeps the weight each rep was stamped with, so "24 reps @ 30 lb" in September and "24 reps @ 32 lb" in October both stay true.
   - Calories already read the exercise's current `loadLb` at log time. **Fix `Repos.updateSet`'s recompute to use the row's stamped weight**, not the exercise's current load, so editing an old row doesn't re-price it at the new baby weight.
3. **Record the time actually held.** `IsometricTimerView` logs elapsed seconds when stopped early and lets a hold run past the target; `holdSeconds` stores the real time.
4. **Read full history.** Replace the rep counter's week-scoped query with a per-exercise, predicate-scoped full-history read (`Repos.setHistory` without the 50-row cap, or an equivalent `@Query` on `exerciseId`).
5. **Fix `StrengthProgress.gainLb`** so a decline can show (compare the recent window's best with the best before it).

### 3.2 "Last time" and a live comparison in the rep counter

In `RepCounterView` (and the hold timer), under the exercise name:

Two reference lines, both from full history, at the weight now in the field:

```
Last time · Tue Oct 14      30 reps @ 50 lb
Last week · Wed Oct 8       26 reps @ 50 lb     (same weekday, 7 days ago)
```

- **Last time** = the most recent earlier day this exercise was done. **Last week** = the same weekday one week ago; if the exercise wasn't done that day, the line names the nearest day in that ISO week it was ("Last week · Thu Oct 9"), or reads "Last week · not logged".
- If the weight in the field wasn't done on a reference day, that line shows the day's top weight instead plus the last day this weight *was* done ("50 lb: 26 reps on Oct 2").
- **Running tally today** (in the existing `ProjectionBar` strip): **`Today 18 reps @ 50 lb · 12 to match last time · +2 vs last week`** — each delta flips from "N to match" to "+N" once passed.
- The weight field pre-fills from the **last weight used for this exercise, ever** (not this week). The wheel keeps its current behaviour. Typing still wins.
- Bodyweight: the same without the weight ("Last time: 42 reps"). Holds: "Last time: longest 50 s". Fixed load: "Last time: 24 reps @ 30 lb".

This is observation-only: no "try" targets and no weight-increase advice. Matching or passing the last day is the implicit goal, and the tally makes it visible.

### 3.3 History and comparisons per exercise

The per-exercise progress view is a `StatDetailSheet` host (never a bespoke sheet), opened from:
- the **Strength card** (made a `PressableCard`), widened to list every trained exercise, not just weighted lifts;
- the **"Your progress"** row added to `ExerciseInfoSheet`.

Contents:
- **Chart:** reps per day (or per week, a toggle) over all history. One series per weight, so the line steps when the weight changes (e.g. the baby gets heavier). Holds chart the longest hold; duration charts minutes.
- **Compare:** two columns by default — **vs last time** and **vs same day last week** — plus a "Compare with" picker that swaps the second column for **any day or week from history** (the days actually trained, like `MealHistoryList` lists only logged days). Rows read per weight:
  - `50 lb   34 reps   +4 vs last time (Tue)   +8 vs last week (Wed)`
  - `55 lb    8 reps   new weight              new weight`
  - `45 lb    —        — (12 on Oct 2)         —`
  - Decreases print plainly, "4 fewer than Tue Oct 14". Neutral colour, no red, no warning icon.
- **Bests (all-time, per weight):** most reps in a day at each weight, heaviest weight ever, longest hold, most minutes. Derived on read.
- **Day list:** every day trained, newest first: `Tue Oct 14 · 50 lb × 30 · 55 lb × 8`. Tapping a day opens `SetHistorySheet` on that day (the ONE editor), the same as `TrainingHistorySheet` rows do today.

`TrainingHistorySheet` rows switch from "N sets · M reps" to the same reps-at-weight line (`50 lb × 30 · 55 lb × 8`), via one shared formatter, so the two lists read alike.

**Performance:** full history per exercise is small (one exercise's rows), but Progress already recomputes over all sets every body pass. Fold per exercise once per data change (memoise on row count + newest timestamp). Measure with a multi-year fixture, per `next-audit-scope.md`.

### 3.4 Celebrate bests, honestly

- At log time (after `guard Repos.addSet(...)`, hard rule 9), if today's reps at a weight now exceed that weight's all-time best day, toast once: **`New best: 34 reps @ 50 lb`** with detail "4 more than your best day (Oct 2)". A heavier weight than ever gets **`Heaviest yet: 55 lb`**. Uses `ToastAccent.win` (documented as "PR beaten", unused today).
- **Guards:**
  - No "best" until the exercise has ≥ 2 earlier days; the first days are the baseline.
  - Bests are per weight, so going heavier for fewer reps never reads as worse.
  - Back-fills and edits never toast.
  - Watch logs never toast (their bests still show in the history view).
  - One toast at a time: best > "Set saved".
- No badges, points or confetti (rejected in `encouragement-system-plan.md`).

### 3.5 Replace the set-based pieces

- **Progress › Training tracker:** "sets this week" (row count, inflated by +1 taps) becomes **reps this week** (sum of `reps` across rep exercises; holds/duration excluded), trend chip "+N vs last wk". This is one change in `TrainingHistory.setsInWeek` / `weeklySetCounts` → reps. The tracker title changes, while its persisted `StatKind` case keeps its raw value. Its detail sheet (the existing `trainingVolumeDetail` `StatDetailSheet`) adds the per-exercise breakdown for the week.
- **Notes based on the amount.** The tracker shows at most one note, chosen from the user's OWN history (honest, because it's arithmetic on their logs):
  - *Approaching:* "40 reps to match last week" (shown once this week reaches ≥ 75% of last week's total).
  - *Passed:* "+35 reps vs last week".
  - *Best:* "Most reps in a week yet" (needs ≥ 3 earlier weeks with logs).
  - *Back:* first logged week after a gap → "First week back — this is your new baseline", no comparison.
  - The same note fires as one toast the first time it becomes true each week (AppStorage once-per-week key), after a successful write.
- **Hypertrophy note — in the ⓘ, not as a claim on the number.** Research measures muscle-building work in **hard sets per muscle per week** (about 10+ is linked with more growth, with diminishing returns — Schoenfeld 2017; ACSM 2026 per secondary summaries, §7), across a wide rep range (~5–30) when sets are close to failure. A weekly *reps* total adds different muscles and effort levels together, so it **cannot** say whether a muscle got "enough". The ⓘ says so plainly and offers a rough, labelled translation: *"about 10 hard sets of 8–12 reps is roughly 80–120 reps per muscle per week"* — a derived rule of thumb, not a sourced threshold, and only shown per exercise in the detail sheet (one exercise ≈ one main muscle group), never as a toast or a green/red judgement. Verify the 10-sets figure against the papers before shipping, per the evidence caveat.
- **Delete `workoutSetMessage`** and the rep counter's per-exercise weekly count (`setsThisWeekForMuscle`). The running tally in §3.2 replaces that feedback.
- **`StallDetector`:** keep the gap nudge as is. A gentle "steady" nudge can be added later: an exercise done on ≥ 6 days over ≥ 4 weeks with no new per-weight best in 3 weeks. It never says "plateau" and never prescribes.

### 3.6 Body signals (optional, later)

- **Lose goal:** a weekly observation when the weight trend is down while reps at a weight are holding or rising: "Your strength held while your weight dropped." An energy deficit blunts muscle gain more than strength (Murphy & Koehler 2022, §7), so this is a real progress signal for that goal.
- **Gain goal:** a weight-gain-rate band is blocked on audit open question 9 (the +500 cal surplus vs the "quarter to half a pound a week" copy).
- **Tape measures:** show a change only above ~0.5 in (an illustrative measurement-error threshold, not a sourced value).

## 4. Copy rules

- Compare to the user's own history only. Neutral wording for both directions: "+4 vs Tue", "4 fewer than Tue".
- First days are open ("see how it feels"); comparisons start from the second day.
- "Not logged", never "missed". No streak-loss messages. Estimates say so (the Strength card's estimated max stays labelled).
- The goal tilts tone only (gain: "building"; lose: "keeping your strength while you lose"). Same numbers and surfaces for both.
- One safety line in the rep counter ⓘ: "If something hurts — not just burns — stop and lighten it."

## 5. Data, schema, watch

- **No schema bump:** load stamping uses the existing `weightLb`; `updateExercise` edits existing columns; hold time uses `holdSeconds`.
- **New AppStorage keys:** celebrated-best keys and the compare-picker choice. Add them to the erase-local-data inventory (`next-audit-scope.md`).
- **Watch:** stamps the load on `.logQuickSet` (phone side, from the exercise id; no wire change). A wrist "last time" label would need a new Optional field on `QuickLogExercise`; it's out of scope.
- **Domain placement:** `RepHistory.swift` and the `StrengthProgress` fix are phone-only Domain files, so they stay out of the watch source list (hard rule 7).

## 6. Tests (hostless, pinned `now`, e.g. `2026-05-27T12:00:00Z`)

- `RepHistoryTests`:
  - Day/week folding per exact weight (50 vs 52.5 stay separate; nil = bodyweight).
  - One-tap rows and rep-counter rows sum the same.
  - Comparison deltas both ways, plus "new weight" / "not done"; "same day last week" falls back to the nearest day in that ISO week, else "not logged".
  - Weekly-reps notes: 75% approaching edge, passed, best-week guard (≥ 3 earlier weeks), first week back.
  - Holds (longest + total) and duration.
  - ISO week edges (Sunday night vs Monday).
- `StrengthProgressTests`: `gainLb` can go negative.
- Bests: per-weight best day, the ≥ 2-day baseline guard, heaviest-ever.
- Persistence:
  - `updateExercise` success and rollback.
  - The load-stamping backfill is idempotent and only touches nil-weight rows of `loadLb` exercises.
  - `updateSet` re-prices from the row's stamped weight.

## 7. Evidence (unverified by opening; check before copy)

| Claim | Source | Confidence |
|---|---|---|
| Adding reps at a weight builds muscle about as well as adding weight; strength slightly favours weight. This supports "reps at a weight" as the progress unit | Plotkin et al., *PeerJ* 2022 | Summary; high |
| Muscle growth is similar across a wide range of loads when sets are hard. This supports tracking reps at whatever weight is used | Schoenfeld 2017/2021; Lopez 2021 | Summary; high |
| Day-to-day performance varies a few percent. Don't over-read one day's dip, so show trends and per-weight bests | Grgic et al. 2020 (1RM reliability); rep counts vary more | Summary; medium |
| Strength is largely kept over short breaks and comes back fast | Bosquet 2013; Ogasawara 2013; Halonen 2024 | Summary; medium |
| An energy deficit blunts muscle gain more than strength | Murphy & Koehler 2022 | Recall; medium |
| ACSM 2026 resistance-training stand: train each muscle group ≥ 2×/week; adherence matters more than exact variables | Currier et al., ACSM 2026 | Secondary summaries; medium |
| Broken streaks demotivate more than the miss warrants | Silverman & Barasch 2023 | Recall; low–medium |

How competitors show the same things (help-centre summaries):
- **Hevy:** "previous" values per exercise.
- **Strong:** per-rep-count records.
- **Boostcamp:** "max reps at a weight" PRs.

Reps-at-weight comparison is a familiar pattern. Our version drops set structure entirely and keeps the full history one tap away.

## 8. Decisions log

All open questions are resolved (Oct 2026): both comparison views; reps-this-week tracker with own-history notes and an ⓘ hypertrophy explainer; exact weight matches. Next step when building: §3.1 data fixes, then §3.2.
