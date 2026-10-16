# Cardio fitness (VO₂ max): track it, build it slowly

> **Status: PLAN, not built (Oct 2026).** CLAUDE.md and the code stay authoritative.
> **Constraint from the owner:** they get dizzy easily, so everything starts slow and
> the app must never push intensity. The safety rules in §1 are binding for any cardio
> feature, not just this one.
>
> **Evidence caveat.** Apple's docs (§2) were opened and read. Everything else comes from
> search summaries or recall and is marked so; verify before it reaches UI copy
> ([health-data-audit](health-data-audit.md): "a confidently wrong figure is worse than
> an open question").

---

## 1. Safety rules (binding)

1. **The app never prescribes intensity.** No heart-rate zones, pace targets, "push harder", or interval timers in v1. It records, compares to the user's own past, and offers plain-language guidance in an ⓘ.
2. **Dizziness is for a clinician, not the app.** One calm line in the VO₂ max ⓘ: dizziness at easy effort, or often, is worth mentioning to a doctor before adding intensity. Seek urgent help for chest/arm/jaw pain, trouble breathing, fainting, or sudden speech/vision changes (Mass General Brigham, search summary: [dizzy spells after workout](https://www.massgeneralbrigham.org/en/health-wellness/dizzy-spells-after-workout), not opened). Shown once in the ⓘ, never a nag or a gate.
3. **No VO₂ max target or goal.** It's a slow outcome, not something to chase. Show the value and a trend, never "you should be at N".
4. **No ranges or "good/bad" labels** until age/sex norms are sourced (they aren't). `HealthRanges` gets a no-classification case for this kind.
5. **Observation over prescription** (RepCheck, StallDetector): comparisons are to the user's own history; "not logged", never "missed"; a lower number is shown plainly, never in red.

## 2. What the app can actually know (Apple docs, opened)

Source: [`HKQuantityTypeIdentifier.vo2Max`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/vo2max).

- Read-only estimate in **ml/kg/min** (iOS 11+). Apple Watch Series 3+ writes it; an iPhone alone never will.
- Generated only after an **outdoor walk, outdoor run or hike** on fairly flat ground. No indoor or treadmill sessions, no estimate from the first workout, and the watch must be worn for a day first.
- It is a **sub-maximal prediction** from the heart-rate response. People on heart-rate-lowering medication can set a switch in the Health app for a better estimate.
- **Accuracy (search summaries, not opened):** validation studies found a mean absolute percentage error around 13–16% against lab tests, with poor test–retest agreement in one ([Series 7 study](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11325102/), [2025 study](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12080799/)). So the copy says a change of a point or two is noise and the multi-month trend is what counts.

Other Health types worth knowing (Apple docs, opened): `heartRateRecoveryOneMinute` (iOS 16+, drop in heart rate one minute after a workout) and `walkingHeartRateAverage` (iOS 11+; Apple **rewrites today's and yesterday's samples** as the day goes on, so only read days at least 2 days old).

## 3. Three kinds of signal

Because VO₂ max moves slowly and is noisy, show what the user *does* and how their body *responds* alongside it:

| Tier | Signal | Source | Surface |
|---|---|---|---|
| Do | Cardio minutes this week vs last | Logged live/past sessions (`ActivitySessionDTO`), derived on read | New Progress tracker (below) |
| Respond | Resting heart rate (already tracked); walking heart rate; heart-rate recovery (optional) | Health | Existing resting-HR tracker; the others later |
| Outcome | VO₂ max | Health (Apple Watch) | New Progress tracker (below) |

Note on "Do": Apple's exercise-minutes figure on `StepsCard` needs brisk movement, so slow walking may not count. Count the user's own logged sessions instead, and label it differently ("Cardio minutes") so it doesn't read like a second exercise-minutes figure (hard rule 8: decide whether it extends that StepsCard line or lives only on Progress; recommended: Progress only).

## 4. Tracking: build order

Follows the resting-HR path exactly (`HealthKitService` → `upsertMarker` → `StatKind`).

1. **`HealthMarkerKind.vo2Max = "vo2_max"`** (append; additive, no schema bump). `HealthRanges`: no-classification case.
2. **`HealthKitService`:** add `.vo2Max` to `readTypes`; read it in the sync; use a type-safe `HKUnit` (`literUnit(with: .milli)` ÷ (`gramUnit(with: .kilo)` × `.minute()`)), never `HKUnit(from:)`, per the file's own rule. Add a **one-time history backfill** (about 2 years, deduped per day by `upsertMarker`): estimates arrive only a few times a week, so `latestQuantity` alone would leave the chart empty.
3. **Authorization traps:**
   - A new read type is only granted through an explicit Connect action (hard rule 4). People already connected need to run it again, so the tracker's empty state offers the existing Connect path and never requests from `.task`/`.onAppear`.
   - HealthKit never reveals a denied read, so the empty state must not say "denied". Say: "No estimate yet. Apple Watch makes one from outdoor walks or runs."
4. **`StatKind.vo2Max`** (appended last; ~11 exhaustive switches; default-hidden, re-appears once data exists via `hasLoggedData`, like the tape trackers). Detail = `StatDetailSheet` host: chart over time, "as of <date>" (`Domain/Freshness`), footer = the accuracy note above.
5. **`StatKind.cardioMinutes`:** weekly total of logged session minutes (all activities), Monday ISO weeks (`Dates.startOfISOWeek`), with the same own-history notes as reps this week: "10 min to match last week", "+8 vs last week", "First week back" after a gap.
6. **Pure Domain** (`Domain/CardioFitness.swift`, phone-only, not in the watch source list): `weeklyMinutes(sessions:now:)`, `vo2Trend(samples:now:)` (latest vs the closest sample 8+ weeks earlier; "about the same" inside a noise band; no verdict on one reading). Hostless tests with a pinned `now`.
7. **Watch:** no change. The watch computes the estimate itself; the phone reads the result from Health.

## 5. Improving it, slowly

- **v1 is base-building only:** more easy minutes, gently. Guidance lives in the ⓘ, user-controlled, and nothing is auto-assigned:
  - Pace where you can speak in full sentences (the talk test).
  - Short easy walks to begin with; add a minute or two at a time rather than big jumps. (Running guidance cited by Mass General Brigham: no more than about 10–20% more per week; use the low end.)
  - Warm up and cool down, drink water, don't hold your breath, stand up slowly.
  - Dizzy? Stop, sit, sip water.
- **No intervals in v1.** Evidence (summaries, not opened) says harder intervals raise VO₂ max more than easy walking: Bacon 2013 pooled 37 studies, +0.51 L/min, 6–13 weeks ([meta-analysis](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3774727/)); a small 2014 trial in inactive overweight adults found about +1.0 ml/kg/min for intervals vs about −1.0 for walking (n = 16–17 per group; adherence problems). But intensity is exactly what dizziness argues against. Revisit only if the owner says a clinician cleared it, and even then as a user-set option, not a prescription.
- **Why bother (recall; verify):** Kodama et al., *JAMA* 2009 meta-analysis: each 1-MET (3.5 ml/kg/min) higher fitness is associated with about 13% lower all-cause mortality. Cohort data, so association, not a promise.

## 6. Copy rules

Spell out acronyms; "VO₂ max" with a short plain gloss ("how well your body uses oxygen during effort"); "estimate" every time; no streak-loss or shame wording; one note at a time; no number target.

## 7. Open questions (need the owner)

1. **Do you have an Apple Watch?** Without one there is no VO₂ max (an iPhone cannot estimate it). The plan then reduces to cardio minutes + resting heart rate.
2. **"Felt dizzy" note:** an optional one-tap flag at the end of a session, saved with the session, so the history can be shown to a clinician. Not in the plan unless you want it; it must never be read as a medical signal.
3. **Cardio minutes: Progress only, or also on StepsCard?** Recommended: Progress only.
4. **Heart-rate recovery and walking heart rate:** add later as the "response" tier, or skip?
