# Health data audit — 14 Oct 2026

Every number this app shows a user about their body or their training was checked
against the code and against the source the code cites. This file records what was
wrong, what was fixed, and — importantly — **what is still unconfirmed**.

Rule this audit followed, and that future ones should: a confidently wrong
correction to health data is worse than an open question. Anything that could not
be verified from the repository is listed as an open question rather than
"fixed".

> **Update, Oct 2026 (Build/Circuit merge).** This audit was written while the app
> had two modes. The modes are now merged: one app, and a per-user goal (Build muscle /
> Lose weight) that only changes targets. The heart-health targets that were
> Circuit-only — fiber floor, sodium / added-sugar / saturated-fat caps — now apply to
> **every** profile (`Targets.HeartHealth`), so the open questions about them below
> affect everyone, not just people trying to lose weight. No number in this file was
> changed by the merge. "Circuit" below means what is now the Lose-weight goal, or,
> for the micros, everyone.
>
> One calorie figure *did* move: per-set burn is now chosen by exercise shape
> (`CalorieEstimator.caloriesForSet`), not by mode. A user-added movement with **no
> load** that used to be logged in Circuit mode (flat 3.5 MET at 3 s/rep) now gets
> the `ExerciseInfo` MET and tempo for its name or category, the same as a lift.
> Sets logged before the merge keep their stored figure until edited; new logs,
> edits and the watch all agree. No MET value was added or changed.

---

## Fixed

| | What was wrong | Consequence before the fix |
|---|---|---|
| Burn was gross, labelled net | `kcal = MET × kg × h` is *gross* energy (1.0 MET is resting), but `DailyBurn`, `EnergyBalance` and the Energy Balance sheet all told the user the figure "excludes resting/BMR", and the Move card set it beside Apple's genuinely net active energy for comparison | At 180 lb, 10,000 steps read ~475 cal against ~365 actual active (+30%); a 45-min Pilates session read ~184 against ~122 (+50%) |
| Running and hiking double-counted | Walking was excluded from the day's burn because its steps already come from HealthKit, but running and hiking were not, despite also producing counted steps | A 30-min logged run added its session calories *and* ~228 cal of the same steps |
| HealthKit glucose mislabelled as fasting | Any blood-glucose sample was stored as `fastingGlucose` with no check of HealthKit's meal-time metadata | A normal post-meal 150 mg/dL was classified against the ADA fasting cut-point (126) and the user was told their fasting blood sugar was high |
| Two definitions of "this week" | Progress training volume used `Calendar.current` (Sunday-based in the US) while Today and Train used ISO/Monday weeks; HealthKit's week-to-date reads used the locale week too | The tabs disagreed about the same week; weekly active-calorie and exercise-minute cells covered a different window from the "Last 7 days" strip directly above them |
| Unsourced physiological claims | The Move card showed "fat burned ≈ Ng" (50% fat oxidation applied to resistance/HIIT work, where fuel use is carbohydrate-dominant) and a "sweat estimate" of `cal / 50`, a constant that appears in no citation anywhere in the repo | Two invented numbers presented as physiology. Removed. The equivalent walking figure in the steps card is sourced (Achten & Jeukendrup 2004) and kept |
| Micronutrient bars showed a reassuring zero | Curated foods carry no sodium, added sugar or saturated fat, so those Circuit caps summed to 0 and rendered as comfortably under the limit | A Circuit user who ate 3,000 mg of sodium saw "0 / 1500 mg". The card now distinguishes "not tracked for these foods" from "you consumed little" |
| Body-fat thresholds misattributed | Header cited Gallagher et al. (2000), whose thresholds are age-stratified; the code's buckets are not, so the citation did not describe the code | A real paper lent authority to numbers it did not contain. Citation removed, see open questions |
| Wrong arithmetic in a validation comment | `CalorieEstimator` claimed "60 s plank at 150 lb → ~2.4 kcal" where the code produces 4.3 gross; the steps reconciliation ("~100 cal/mile × ~4 miles") also didn't match the model's ~84 cal/mile | The comments that existed to prove the math was right disproved it |

### What a user will actually see change

Burn figures drop, because they were overstated. At 180 lb:

| | Before | After |
|---|---|---|
| 10,000 steps | 475 cal | **364** |
| 45-min Pilates | 184 cal | **122** |
| 30-min run, as a session | 367 cal | **327** on the session row, **0** added to the day |
| A day of 10,000 steps + that run | 842 cal | **364** |

That last row is the double-count: roughly 301 cal of the old step figure *was*
the run's own steps, and the session added its 367 on top. The run is now
credited only through its steps, valued at the walking MET — so it is slightly
under-credited, which is the same under-count walking has always carried.
Under-counting once is better than counting twice.

Also lower: the Move card's estimate and training total, the steps card's
"~N cal burned", Progress energy balance and training history, live-session and
rep-counter calories, Circuit quick-log calories (now the shared exercise list's one-tap +1), and the step/rep projections.

### Two consequences worth knowing

1. **Historical calorie figures are now mixed.** Sets, cardio and live sessions
   store their estimate at log time, so rows logged before this change still hold
   the old gross value and will read high next to new ones. Fixing it means a
   one-time recompute migration. Deliberately not done — it touches the schema,
   and the artifact is bounded and explainable.
2. **Glucose coverage regressed on purpose.** Samples with no meal-time metadata
   — most CGM feeds and manual Health entries — are now dropped rather than
   filed as fasting. A user who previously saw a glucose marker sync may now see
   none. The complete fix is a separate non-fasting glucose marker kind.

### Found while fixing: servings were never multiplied

`DailyTotals.totals(from:)` summed `perServing` and ignored each entry's
`servings` count, so a food logged at 2 servings counted once. Every macro read
low, not just the micros. The label scanner is the only path that stores an
unscaled figure plus a count (every other path pre-scales and leaves servings at
1), so this only bit scanned foods — but it bit all of their macros. Fixed via
`FoodLogEntryDTO.totalNutrition`, which the day totals and the log row now use.

## Verified correct — no action

- **Mifflin-St Jeor** is implemented correctly (`10·kg + 6.25·cm − 5·age`, `+5` male / `−161` female) with the standard activity multipliers.
- **Atwater consistency across all ~1,200 curated foods**: mean absolute deviation 1.4–9.5% per category. Every entry off by more than 20% is alcoholic, which is correct — ethanol's 7 cal/g has no macro field. This verifies *internal* consistency only; absolute agreement with USDA FoodData Central cannot be checked from the repo.
- **HealthKit query semantics**: cumulative types use `.cumulativeSum`, discrete types (heart rate, body mass, body fat, waist, BP, glucose) go through the latest-sample path. The discrete-average trap is avoided. Units, the 0–1 → % body-fat conversion, and local-midnight day bounds are all right.
- **No hardcoded kcal anywhere** — every path routes through `CalorieEstimator`. No 3,500-cal-per-pound shortcut.
- **BMI** (`× 703`, CDC cut-points), **Tudor-Locke step bands**, **ADA A1c/glucose cut-points**, **ATP III total-cholesterol and triglyceride bands**, and the **IOM water AIs** all match their citations.
- Units are canonically imperial with conversion only at the UI boundary; no double conversion found.

---

## Open questions — do not "fix" these without confirming the source

These are either published values that could not be verified from the repository,
or product decisions that are not the code's to make. Each needs a human with the
actual guideline in hand.

1. **Resting heart rate range.** `HealthRanges` says "Healthy adult: 60–80 bpm (AHA)" and warn-tints 81–90, while the Move card's own copy says "60–100 bpm is normal. Athletes often sit at 50–70." These contradict each other. If the AHA range is 60–100, Progress currently warns on a normal 85 and calls an athletic 48 "worth watching".
2. **Blood pressure classification.** 80–89 diastolic maps to a status whose word is "slightly elevated", though the code's own comment calls it Stage 1. The cited guideline also evaluates systolic **and** diastolic together — "Elevated" requires systolic 120–129 *and* diastolic under 80 — so judging the two independently loses the conjunction. 125/85 currently reads as healthy-ish on both.
3. **Body-fat category thresholds.** See above: no confirmed primary source.
4. **Added-sugar cap** is a flat 25 g for everyone; the AHA limits are sex-specific. The cited paper (Te Morenga 2012) is about sugar and body weight, not a gram cap.
5. **Fiber floor** is a flat 35 g and carries no citation, while its companion saturated-fat cap *is* calorie-scaled. The IOM AIs are sex-specific.
6. **Saturated-fat cap**: implemented at the DGA 10% of calories. This was raised for the old Circuit mode, whose purpose was fixing cardiovascular markers, where the AHA's 5–6% may be the right target instead. The cap now applies to everyone, so the question is now also whether one universal figure fits both goals.
7. **Sodium target** of 1,500 mg is attributed to a DASH-Sodium arm that should be checked.
8. **Strength-training calories are probably much too low.** Session calories use the activity's MET × time-under-tension only, but the Compendium's resistance values describe a whole session *including rest* — which is what the cited measurements captured. A real 20-set session is ~600 s of tension, so "Training Only" may understate a genuine strength session by roughly 5×. Fixing this means either modelling rest time or choosing a per-set MET that matches tension-only, and it would change the app's headline training number. Deliberately left alone.
9. **Build-muscle surplus vs the promise made to the user.** The target adds 500 cal/day (≈1 lb/week) while the rationale copy says "about a quarter to half a pound a week" (≈125–250 cal). The spec sanctions 400–600, so the code, the copy and the spec don't agree. Product decision.
10. **Ainsworth MET values** in `ActivityCatalog` and `ExerciseInfo` are plausible and self-labelled, but no MET was checked against the Compendium itself. `ExerciseInfo` claims every value comes from Ainsworth while the isometric holds are openly derived, since the Compendium has no code for them.

---

## Known gaps that are not bugs

- **Sodium, added sugar and saturated fat are only available for foods logged from a scanned nutrition label.** The curated database has no fields for them. Until it does, the heart-health card (now shown to everyone) can only ever report on part of the day.
- **Lab markers (LDL, HDL, total cholesterol, A1c, fasting glucose) are manual-entry only** and cannot come from Apple Health. This is by design, not an omission.
- **`HealthMarkerKind.triglycerides`** has range support but no tracker, no card and no way to enter it.
