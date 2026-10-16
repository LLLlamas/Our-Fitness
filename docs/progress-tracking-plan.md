# Progress tracking & progressive-overload plan

> **Status: PLAN, not built (Oct 2026).** Research + design for tracking strength/muscle
> progress and encouraging more reps/sets over time. Nothing here is implemented yet.
> CLAUDE.md and the code stay authoritative for current behaviour.
>
> **Evidence caveat — read before using any number.** The research pass behind this doc
> could not open primary papers (journal hosts were unreachable from the research
> sandbox and the search budget ran out). Every figure in §8 comes from search-engine
> summaries of the named source or from recall, and is marked as such. Under the
> [health-data-audit](health-data-audit.md) rule ("a confidently wrong figure is worse
> than an open question"), **verify each number against its DOI before it reaches UI
> copy or a `scienceLine`.** The design does not depend on any single figure being exact.

---

## 1. What exists today (verified in code)

| Piece | What it does | Gap for this plan |
|---|---|---|
| `Domain/StrengthProgress.swift` → Strength card on Progress | Best Epley estimated max per loaded lift (sets of 1–12 reps), "+N lb · 4 wk" | Loaded lifts only. **`gainLb` can never be negative**: `estimatedMaxLb` is the all-time best and `previousMaxLb` a subset of the same rows, so a regressed lift reads "no change" and the "−" copy path is dead. Card isn't tappable: no chart or detail |
| `Domain/Progression.swift` | linear / double-progression / RPE "next target" schemes | **Dead** (tests only). Reads one set (`history.first`), not a session; always +5 lb; a nil weight suggests "5 lb" for a bodyweight move |
| `Domain/TrainingHistory.swift` | Weekly set-row counts (Progress › Training), day sessions | Counts **rows**, and every one-tap +1 is its own row. A 10-rep set of Lifted Baby counts as 10 "sets" |
| `EncouragementEngine.workoutSetMessage` | Toast at 4/6/10/12 "sets this week for {muscle}" | Count is **per exercise**, labelled per muscle; reads "this muscle group" for user-added exercises (`muscleGroups` is `[]`); fires only on exact equality, so a jump past a threshold is skipped; "Elite volume" overclaims |
| `RepCounterView` pre-fill | Silently pre-fills weight + wheel from this ISO week's last set | Query is limited to the current Monday week, so it's blank every Monday and for a lift trained once a week. No visible "last time" |
| `StallDetector` | Once-a-day gap nudge (workout gap 5 d gain / 7 d lose) | Gaps only, never a performance plateau |
| Tape trackers, weight trend | Shoulders/chest/arm/thigh/waist, weight | No change threshold, no "strength held while losing" reading |

Data facts that shape everything below:

- `WorkoutSetDTO` already has `weightLb?`, `reps`, `holdSeconds?`, `rpe?`, `notes?`, `workoutId?`. **No UI writes `rpe`, `notes` or `workoutId`**, so a "session" is a calendar day.
- Fixed-load movements (Lifted Baby 30 lb, etc.) keep the load on `ExerciseDTO.loadLb` and write `weightLb: nil` on every set. **There is no `Repos.updateExercise`**: the only way to change the load is delete + recreate, which cascade-deletes history. So the growing baby can't be tracked at all today.
- Holds record the **picked** duration, not the time actually held (cancel logs nothing; going past the target isn't recorded).
- User-added exercises store `defaultRepRange` 8–12 (never read anywhere) and `muscleGroups []`. Muscles come from `ExerciseInfo.meta(for:)` at read time.
- `Repos.setHistory(userId:exerciseId:limit:)` already exists: an exercise-scoped, newest-first fetch, used only by the watch undo.

## 2. Principles

1. **Derive on read, never store rollups.** PRs, bests, trends and per-muscle volume are computed from sets (append-only logs; sets can be edited and back-filled). The only persisted state is "already celebrated" keys in AppStorage, the `StepsCard` fired-milestone pattern.
2. **Pick the metric by exercise shape, never by goal.** Use `tracksPerSetWeight` / `isOneTapLoggable` / `isIsometric` / `kind`. Both goals see the same surfaces; the goal only tilts copy and thresholds.
3. **Compare like with like.** Celebrate "more reps at this weight" or "heavier than ever" (unambiguous). Show the estimated max as a trend, but never toast it alone: Epley is a noisy estimate, and mixing rep ranges or logging slips creates fake PRs.
4. **Observation first, suggestion second, never prescription.** "Last time: 50 lb × 10, 10, 8" is always shown; "Try 11" is a suggestion; nothing auto-changes. (RepCheck: "observation over prescription"; StallDetector: "never prescribes".)
5. **Extend the existing surfaces (hard rule 8).** RepCounter/ProjectionBar for in-flow feedback, `ExerciseInfoSheet` for per-exercise detail, the Strength card + `StatDetailSheet` for charts, `trainingVolumeDetail` for per-muscle volume, `StallDetector` for plateaus, `TrainingHistorySheet` for cross-day history. No new card, sheet or tab.
6. **Honest, self-referenced, informational copy.** Compare to the user's own past only: no badges, points, leaderboards or social comparison (rejected in `encouragement-system-plan.md`). "Not logged", never "missed". No streak-loss messaging. Estimates say so. Never encourage pushing through pain.

## 3. Progress metric per exercise shape

| Shape (predicate) | Example | "Last time" line | Best / PR types | Trend on Progress | Suggestion rule |
|---|---|---|---|---|---|
| Weighted lift (`tracksPerSetWeight`) | DB bench, squat | `Tue: 50 lb × 10, 10, 8` | Heaviest weight · most reps at ≥ a weight · estimated max (shown, not toasted) | Best estimated max per session (≤12-rep sets), top-set weight | Double progression in the exercise's rep range (§4.2) |
| Bodyweight reps (`.bodyweight`, rep counter, no weight) | Pull-ups, push-ups | `Tue: 8, 7, 6` | Most reps in one set | Best set reps per session | +1 rep on the best set; at the top of range for 2 sessions → copy suggests a harder variation or added weight |
| Isometric (`isIsometric`) | Plank, wall sit | `Tue: 45 s, 40 s` | Longest hold | Longest hold per session | +5 s on the best hold (heuristic, §8) |
| Fixed-load reps (`isOneTapLoggable`, `loadLb`) | Lifted Baby | `Tue: 24 lifts · 30 lb` | Most lifts in a day at ≥ this load | Lifts per day + load step line | None automatic. Monthly "has the load changed?" prompt (§4.6) |
| Duration (`kind == .duration`) | Carried Baby | `Tue: 12 min · 30 lb` | Longest day | Minutes per day | None |
| Pilates / live sessions | — | (existing cards) | (existing ring/streak) | Sessions & minutes per week (existing) | None |

## 4. Plan, in build order

Each phase ships on its own. Phase 0 is required first because every later phase reads its fixes.

### Phase 0: Data fixes (small, additive; no schema bump)

1. **Stamp the load on fixed-load sets.** `ExercisesCard.quickLog`, the watch `.logQuickSet` and the rep-counter path for loaded movements write `weightLb = exercise.loadLb` (the column already exists). One-time Seeder backfill: stamp existing nil-weight sets of `loadLb` exercises with the current `loadLb`. That is correct because the load could never change before step 2 existed. Check that `StrengthProgress` still excludes these sets (it filters on `tracksPerSetWeight`, so it should) and that `EditSetSheet` now shows their weight (it shows a weight field whenever a set has one).
2. **`Repos.updateExercise(id:name:loadLb:repRange:)`** (returns `Bool` via `RepositoryWrite`). Reached from `ExerciseInfoSheet` (the ONE per-exercise sheet). Changing the load affects future sets only, because history keeps its stamped loads. This alone unblocks the parent's growing-baby case.
3. **Record actual hold time.** `IsometricTimerView`: Stop early → log the elapsed time; past the target → offer "keep going" and log the real total. Store the real seconds in `holdSeconds`.
4. **Widen "last time" beyond the ISO week.** Replace the week-scoped pre-fill query with `Repos.setHistory` (bounded, e.g. last 90 days, `limit` ~50) and derive the last *session* (last day the exercise was trained, sets in timestamp order).
5. **Cluster one-tap rows into sets on read.** In `TrainingHistory`, consecutive one-tap rows for the same exercise less than ~2 minutes apart (heuristic; tune) count as **one set** for volume. Raw rows stay as they are. This stops Lifted Baby taps dominating the weekly set count.
6. **Fix `StrengthProgress.gainLb`.** Compare the best inside the window with the best before it (not all-time vs a subset), so a dip can read as a dip. Keep "nil when not trained in the window".
7. **Fix `workoutSetMessage`.** Interim: label the count as the exercise ("4 sets of Bench this week"), fire on *crossing* a threshold rather than equality, and drop "Elite volume". Phase 4 replaces it with a true per-muscle count.

### Phase 1: "Last time" + "try" inside the rep counter (highest value, no new surface)

- **Header line** under the exercise name in `RepCounterView` (and the hold timer): `Last time · Tue: 50 lb × 10, 10, 8`. Shown from the first repeat session.
- **Suggestion** (from the second session on; first sessions are baseline): `Try 50 lb × 11`. The wheel and weight pre-fill to the suggestion instead of "this week's last set". Typing still wins, as now.
- **Post-set feedback** in the existing `ProjectionBar` strip: `+1 rep vs last time` / `Matched last time` / nothing when lower (no negative messaging mid-session).
- **The rep range becomes visible and editable** in `ExerciseInfoSheet` (`defaultRepRange`, which already exists and is never read). Default 8–12; the goal sheet already writes catalog ranges.

#### 4.2 Suggestion engine: revive `Progression`, don't write a second one

Rework `Progression.doubleProgression` (pure Domain, hostless-tested, pinned `now`) to take the **last session's sets**, not one set:

- Input: last session's sets (in order), the rep range `[lo, hi]`, the increment (default 5 lb, the smallest common dumbbell/plate jump), the shape.
- **All working sets reached `hi`** → suggest weight + increment at `lo` reps. Cap the jump at **≤10% of the current load** (ACSM 2009: +2–10% once 1–2 reps over target, §8). If the increment is over 10% (light dumbbells: 10 → 15 lb is +50%), suggest **more reps first** and say why ("Dumbbell jumps are big at this weight — add reps before weight").
- **Otherwise** → same weight; +1 rep on the first set that was below `hi`.
- **Nil weight** (bodyweight) → reps only, never invent a load (fixes today's "0 + 5 lb").
- Never suggest a weight increase and a rep increase together. Never suggest anything after a gap of ≥ 3 weeks (Phase 5, comeback).
- The NSCA "2-for-2" rule (beat the target by 2+ reps on the last set, two sessions running) is a stricter alternative trigger. Start with plain double progression: it needs no effort rating, and adding reps vs adding load gave similar hypertrophy in trained lifters (Plotkin 2022, §8).
- **No RIR/RPE capture in v1.** It adds typing to a 2-tap flow, and people misjudge reps left by about one rep on average (Halperin 2022). `WorkoutSetDTO.rpe` stays available for later.

### Phase 2: PRs (derived on read, celebrated at log time)

- A pure `StrengthProgress.records(for:exerciseSets:)` lives beside `estimatedOneRepMax`, one function for every shape in §3.
- **Celebrate only like-for-like PRs:** heaviest weight ever; more reps at ≥ a weight than ever; longest hold; most bodyweight reps in a set; most fixed-load lifts in a day at ≥ this load.
- **Fake-PR guards:** no PR until the exercise has **≥ 2 earlier sessions** (first sessions are baseline); the estimated max never toasts; a PR set with a weight >25% above the previous best asks "Typo?" in the toast detail (still logged, still editable in `SetHistorySheet`).
- **Toast precedence** (one toast at a time): PR (`ToastAccent.win`, already documented as "PR beaten" but unused) > volume milestone > "Set saved". Fire only after `guard Repos.addSet(...)` succeeds (hard rule 9).
- **Dedupe:** compare against history *excluding* the new set at log time; editing or back-filling never toasts. Watch logs never toast; their PRs appear on Progress.
- **Copy:** `New best: 55 lb × 8` / detail `Incline press — 1 more rep than your best at this weight.` No confetti, no badges.

### Phase 3: Per-exercise progress on Progress (extend the Strength card)

- Make `strengthCard` a `PressableCard`. Tapping a lift opens a **`StatDetailSheet` host** (never a bespoke sheet), with:
  - Chart: best estimated max per session, 12 weeks (`chartOverride`). For bodyweight lifts: best-set reps; holds: longest hold; fixed-load: lifts per day with a load step line.
  - Headline: current best + status chip (below).
  - Footer: recent PRs, last 5 sessions (`W × R` top sets), "Estimated with Epley's formula — an estimate".
- Widen the card beyond loaded lifts: one row per trained exercise of any shape, using that shape's metric. Hide rows not trained in 8 weeks.
- **Status chip per exercise** (needs ≥ 4 sessions over ≥ 3 weeks, otherwise no chip):
  - *Getting stronger*: last-4-week best beats the prior-4-week best by more than a noise band.
  - *Holding steady*: within the band.
  - *Dipped*: below the band.
  - Band: about ±2.5% of the estimated max, because day-to-day 1RM variation is a few percent (median CV ~4%, Grgic 2020) and rep-based estimates add error. Tune it with real data before shipping.
- `ExerciseInfoSheet` gains a compact **"Your progress"** section (last session, best, status) linking to the Progress detail. It stays read-only; edits stay in `SetHistorySheet`.
- `TrainingHistorySheet` rows gain the top set (`50 lb × 10`) by extending `TrainingHistory.ExerciseLine`, so there is still one history list.
- **Performance:** Progress already recomputes over all sets every body pass (flagged in the backlog). Compute per-exercise series once per data change (memoised on set count + latest timestamp) and measure with multi-year fixtures, per `next-audit-scope.md`.

### Phase 4: Weekly sets per muscle (replace the per-exercise milestone)

- **One normalised taxonomy**, about 10 groups (chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, core). Map from `ExerciseInfo.meta(for:)` primary/secondary muscles through `ExerciseGoalMatcher.goalMuscleMap`, which is the closest existing taxonomy. This consolidates the five muscle-name sources rather than adding a sixth.
- **Fractional counting:** a set counts 1 for each primary muscle and 0.5 for each secondary muscle. This scheme fit best in the largest dose-response meta-regression (Pelland 2025/26, §8).
- **What counts as a set:** rep-counter sets, holds, and one-tap clusters (Phase 0.5). Duration minutes don't count. Warm-ups can't be told apart yet; accept that for v1.
- **Surface:** the existing `trainingVolumeDetail` (`StatDetailSheet`) gains per-muscle bars for this ISO week against a soft reference line at about **10 sets/week**. Basis: graded dose-response, with ≥10 sets associated with more growth than fewer (Schoenfeld 2017; the 2026 ACSM stand per secondary summaries).
  - Copy: "About 10+ weekly sets per muscle is linked with more growth. More helps less and less."
  - No upper "target". No "elite". Same surface for both goals; lose-goal copy says volume helps *keep* muscle while losing weight.
- **Toast:** fire once per muscle per week on crossing about 10 fractional sets ("Back: 10 sets this week"), replacing `workoutSetMessage`'s 4/6/10/12. Delete `RepCounterView.setsThisWeekForMuscle` (the second weekly counter) so `TrainingHistory` is the only one.

### Phase 5: Plateau, comeback and consistency (StallDetector, once a day, one nudge)

- **Plateau:** an exercise with ≥ 6 sessions across ≥ 4 weeks and no like-for-like best in the last 3 weeks gets a new `Stall` case.
  - Copy: "Bench has held steady for 3 weeks. Adding a rep before adding weight, or trying a different rep range, can restart progress."
  - **No deload prescription.** Deloads are common practice, but the one RCT found a full week off *reduced* lower-body gains (Coleman 2024, §8).
  - Reuse `Trends.weeksStalled`'s algorithm rather than adding a third flat-detector.
- **Comeback:** trained before but not in ≥ 3 weeks. The rep counter shows "Welcome back — last time was 5 weeks ago" with no suggestion, and the first session back is baseline with no PRs. Strength is largely retained over short breaks and returns quickly (Bosquet 2013; Ogasawara/Halonen, §8), so don't auto-reduce the load. Just don't push.
- **Consistency:** a weekly training streak (≥ 1 strength session per ISO week) through the existing `Movement` weekly-streak + `StreakChip` pattern. It is grace-based: a broken streak is never announced (broken streaks demotivate more than the miss warrants; Silverman & Barasch 2023).

### 4.6 Fixed-load movements: the parent's progress story

Once Phase 0 lands (stamped loads + `updateExercise`), the lose-goal user gets:
- "Last time: 24 lifts · 30 lb".
- A most-lifts-in-a-day PR.
- A load step line on the chart as the baby grows.
- A monthly prompt to update the load: about 0.2–0.5 kg/month after 6 months per WHO velocity (unverified), so the prompt never guesses the weight.
- Pilates/live sessions keep their existing weekly ring + streak.
- The Phase 6 "strength held while weight dropped" reading.

### Phase 6: Body signals (optional; resolve audit questions first)

- **Gain goal:** weekly weight trend against a lean-gain band of about **0.25–0.5% of bodyweight per week** (Iraki/Helms 2019, §8). **Blocked by audit open question 9** (the +500 cal surplus ≈ 1 lb/week contradicts the "quarter to half a pound" copy). Resolve that first.
- **Lose goal: the key progress signal is "strength held while weight dropped".** When the weight trend is down and lift statuses are *steady* or *stronger*, a weekly `DayInsights`-style observation says so. Energy deficits blunt lean-mass gain more than strength (Murphy & Koehler 2022), and resistance training preserves lean mass during dieting. This gives the lose-goal user a real progress story beyond the scale.
- **Tape measures:** show a change only above about **0.5 in / 1 cm**. That is an illustrative minimum detectable change for self-measured girths, not a sourced value. Measure the same landmark, take two readings, every 2–4 weeks. Copy explains this in the tracker's ⓘ.
- **Not building:** progress photos (no outcome evidence; body-checking risk), smart-scale lean mass (consumer BIA tracks individual change poorly), public strength standards (populations differ; social comparison is rejected).

## 5. Encouragement copy rules (additions to EncouragementEngine's)

- Self-referenced competence feedback ("1 more rep than last time"), not controlling language ("you must"). Autonomous motivation predicts adherence (SDT; Teixeira 2012).
- First sessions are *open* ("see how it feels"); specific "+1 rep" targets come only once there's a baseline. Specific hard goals can backfire for novices (Swann 2021).
- One message at a time, return nil at non-events, no daily-perfection framing, no shame for regressions or gaps.
- Safety line in the rep counter ⓘ: "Progress comes from adding a rep or a little weight over weeks. If something hurts — not just burns — stop and lighten it." Never encourage training through pain. No suggested jump over 10%.
- The goal tilts tone only. Gain: "building"; lose: "keeping your strength while you lose". Same numbers, same surfaces.

## 6. Data, schema, watch

- **No schema version bump.** `weightLb` stamping and actual hold seconds use existing columns. `updateExercise` edits existing columns. Any new optional column (e.g. a per-exercise `incrementLb`, if users need to override the 5 lb default) is additive, with no `.unique`, to stay CloudKit-ready (`app-expansion.md`).
- **New AppStorage keys:** celebrated-PR keys, per-muscle weekly-toast keys, baby-load prompt date. Add them to the erase-local-data inventory (`next-audit-scope.md`).
- **Watch:** optional "last time" on wrist quick-log rows needs a new **Optional** field on `QuickLogExercise` (synthesised Codable), so it's out of scope for v1. The wrist keeps sending ids only.
- **Domain placement:** everything new lives in phone-only Domain files (`StrengthProgress`, `Progression`, `TrainingHistory`, a new `MuscleVolume.swift`). None of it goes in the watch source list (hard rule 7).

## 7. Tests (hostless, pinned `now` such as `2026-05-27T12:00:00Z`)

- `ProgressionTests`: session-level double progression; 10% cap → reps-first; nil weight never yields a load; no suggestion after a ≥ 3-week gap.
- `StrengthProgressTests`: like-for-like PR types per shape; ≥ 2-session baseline guard; estimated max never a PR; `gainLb` can go negative.
- `TrainingHistoryTests`: one-tap clustering (taps 30 s apart = 1 set, 5 min apart = 2); stamped loads.
- `MuscleVolumeTests`: fractional counting, taxonomy mapping for unknown names, ISO week boundaries.
- `StallDetectorTests`: plateau edges (5 vs 6 sessions, 3-week window), comeback suppression.
- Persistence: `updateExercise` failure rollback; backfill idempotency.

## 8. Evidence table

All entries are **unverified by opening** in this research pass. Verify against the DOI before shipping copy.

| Claim used above | Source | Basis / confidence |
|---|---|---|
| +2–10% load once 1–2 reps over target | ACSM Position Stand, *Progression Models in Resistance Training*, MSSE 2009;41(3):687–708 | Search summary + well known; high. The "two consecutive sessions" wording traces to the NSCA textbook (Baechle & Earle), not ACSM |
| 2026 ACSM resistance-training stand replaces 2009: ≥2 sessions/wk per muscle group, about 10+ sets/muscle/wk for hypertrophy, adherence > exact variables | Currier et al., ACSM 2026 (137 reviews, >30,000 participants) | Secondary summaries only; medium. Exact figures **not** confirmed in the paper |
| Graded volume dose-response; ≥10 sets/muscle/wk > fewer | Schoenfeld, Ogborn, Krieger, *J Sports Sci* 2017 | Abstract summary; high. **Note:** the app's current `scienceLine` cites this as *J Strength Cond Res*, likely a citation error to check |
| Diminishing returns; fractional counting (indirect = 0.5) fits best | Pelland et al. 2025/26 meta-regression (67 studies) | Summary/preprint; medium |
| Adding reps ≈ adding load for hypertrophy | Plotkin et al., *PeerJ* 2022 | Summary; high |
| Similar hypertrophy across loads when near failure | Schoenfeld 2017/2021; Lopez 2021 | Summary; high |
| People misjudge reps-in-reserve by about 1 rep | Halperin et al., *Sports Med* 2022 | Summary; high |
| e1RM accuracy falls with reps; keep ≤10–12 | Reynolds 2006; LeSuer 1997; Strong caps at 12 | Summary; medium |
| 1RM day-to-day variation of a few percent (median CV about 4%) | Grgic et al. 2020 review | Summary; medium |
| Deload week off reduced lower-body gains | Coleman et al. 2024 RCT | Summary; medium |
| Strength largely retained over short breaks; regained fast | Bosquet 2013; Ogasawara 2013; Halonen 2024 | Summary; medium |
| Deficit blunts lean-mass gain more than strength | Murphy & Koehler 2022 | Recall; medium |
| Lean-gain rate about 0.25–0.5% BW/week | Iraki, Helms et al. 2019 | **Recall only**; verify |
| Broken streaks demotivate | Silverman & Barasch, *J Consumer Res* 2023 | Recall; low–medium |
| Open goals may suit beginners | Swann et al. 2021 | Recall; medium |
| WHO infant weight velocity: about 1 kg/mo (0–3 mo) falling to about 0.2 kg/mo (yr 2–3) | WHO Child Growth Standards | Recall; verify before any copy (copy should never state a baby's weight anyway) |

How competitors handle the same features (help-centre summaries, medium–low confidence):
- **Hevy:** a "previous" column with tap-to-copy; four PR types (heaviest, best estimated max, best set volume, best session volume); per-rep-count set records deliberately don't announce; a warm-up toggle recalculates PRs.
- **Strong:** estimated max via Brzycki, from sets of ≤12 reps only.
- **Hevy Trainer, Liftosaur:** double progression.
- **Alpha Progression:** suggestions respect plate/dumbbell increments.
- **Fitbod:** users complain of implausible auto-weights.
- **RP Hypertrophy:** feedback prompts called tedious.

Our plan copies the cheap, trusted parts (previous line, like-for-like PRs, double progression, increment awareness) and skips the noisy ones (auto-weights from little data, per-session questionnaires, heat maps on unreliable muscle tagging).

## 9. Open decisions

1. **Show "Try N" suggestions at all?** Recommended: yes, labelled as a suggestion, from the 2nd session. The always-on "Last time" line is the observation-only fallback if you'd rather not.
2. **One-tap clustering window:** recommended 2 minutes; tune with real logs.
3. **Baby-load prompt (§4.6):** a gentle monthly "Has Lifted Baby gotten heavier? Update the load" in `ExerciseInfoSheet` / the row, never a number guess. Recommended on.
4. **Reps-in-reserve capture:** recommended not in v1.
5. **Gain-rate band (Phase 6):** blocked on audit open question 9.
