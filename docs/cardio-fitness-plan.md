# Cardio fitness (VO₂ max): track it, build it slowly

> **APPROVED 2026-11-20 (owner decisions in §10).** Was: **REVIVED 2026-11-20, awaiting owner approval.** The owner is getting a newer Apple Watch (Series 4+), so the October blocker (a Series 3 that can't pair) is going away. Nothing is built. §8 is the rollout: a watch check first, then the build phases. No build agents go out until the owner approves §8 and answers §7.

> **Status: PLAN, not built.** CLAUDE.md and the code stay authoritative.
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
5. **Observation over prescription** (StallDetector): comparisons are to the user's own history; "not logged", never "missed"; a lower number is shown plainly, never in red.

## 2. What the app can actually know (Apple docs, opened)

Source: [`HKQuantityTypeIdentifier.vo2Max`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/vo2max).

- Read-only estimate in **ml/kg/min** (iOS 11+). Apple Watch Series 3+ writes it; an iPhone alone never will.
- Generated only after an **outdoor walk, outdoor run or hike** on fairly flat ground. No indoor or treadmill sessions, no estimate from the first workout, and the watch must be worn for a day first.
- It is a **sub-maximal prediction** from the heart-rate response. People on heart-rate-lowering medication can set a switch in the Health app for a better estimate.
- **Accuracy (search summaries, not opened):** validation studies found a mean absolute percentage error around 13–16% against lab tests, with poor test–retest agreement in one ([Series 7 study](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11325102/), [2025 study](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12080799/)). So the copy says a change of a point or two is noise and the multi-month trend is what counts.
  - Re-checked 2026-11-20 (search summary of [PubMed 40373042](https://pubmed.ncbi.nlm.nih.gov/40373042/), not opened): Lambe et al., *PLOS ONE* 2025, n = 30. The watch **underestimated** VO₂ max against a lab treadmill test by a mean of 6.07 ml/kg/min (limits of agreement −6.11 to 18.26). Mean absolute percentage error was 13.31%. The authors say it needs refinement before clinical use. Copy consequence: never present the number as a lab measurement. "Estimate" every time, as §6 already says.
- **Apple's own requirements** (re-checked 2026-11-20; search summaries of [Apple Support 108790](https://support.apple.com/en-us/108790) and [Apple's VO₂ max white paper](https://www.apple.com/healthcare/docs/site/Using_Apple_Watch_to_Estimate_Cardio_Fitness_with_VO2_max.pdf), not opened; open both before any of this reaches UI copy):
  - Estimates come from **Outdoor Walk, Outdoor Run or Hiking** workouts. Indoor workouts don't count. The ground has to be fairly flat (grade under 5%), with a good GPS and heart-rate signal and enough effort.
  - The **first estimate** takes at least 24 hours of wear, then several of those workouts plus passive measurements. The empty state has to expect weeks, not days.
  - The supported range is **14–65 ml/kg/min**. Apple shows its own low/normal/high classifications only for users aged 20 and over, and those users can opt into a notification if the estimate stays consistently low. That notification is Apple's feature, so we don't duplicate it (§1 rule 4 still holds: no labels from us).
  - Inputs are age, sex, weight, height and heart-rate medications. Heavy loads, sand, strollers or assistive devices, dehydration, caffeine, heat and recent altitude can lower accuracy or produce an underestimate. That list is for the ⓘ footer.

- **Which watches (search summaries of Apple's white paper and compatibility table, not opened):** the estimate needs a **Series 3 or later** (SE and Ultra too); the original, Series 1 and Series 2 don't make one. Our companion watch app targets **watchOS 10.0**, which Apple lists as Series 4 or later (Series 3 tops out at watchOS 8.8.1). VO₂ max reaches the phone app through Apple Health, so **the companion app is not needed for it**.

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

1. **Which watch: superseded 2026-11-20.** The October finding still stands for the old watch: a Series 3 GPS 42mm (part number MTF32LL/A) whose OS is too old for the owner's iPhone. The owner is now getting a newer watch, model not yet known. Needed before Phase 1 ships: the model (Series 4 or later runs our watchOS 10 app; per §2, Series 3+ makes VO₂ max) and that it pairs with the owner's own iPhone.
2. **"Felt dizzy" note:** an optional one-tap flag at the end of a session, saved with the session, so the history can be shown to a clinician. Not in the plan unless you want it; it must never be read as a medical signal. *Recommended: yes, phone-only, Phase 3. It costs a schema field (see §8).*
3. **Cardio minutes: Progress only, or also on StepsCard?** Recommended: Progress only.
4. **Heart-rate recovery and walking heart rate:** add later as the "response" tier, or skip? *Recommended: skip for now. Revisit after a month of VO₂ max data.*
5. **Cardio minutes: REOPENED by the newer watch.** October's answer was "logged sessions only", because no watch workouts could reach Health. A paired watch changes that. VO₂ max needs Apple's **Outdoor Walk / Outdoor Run / Hiking** workouts (§2), and those land in Health as `HKWorkout`s that never pass through our logs. Our own watch runner also saves an `HKWorkout` (`WatchWorkoutSession.endWorkout` → `finishWorkout`) *and* the phone logs the same session. Options:
   - **a) Logged sessions only (October rule).** No new HealthKit read. Apple Workout-app walks don't count unless the user logs them again in `LogPastSessionSheet` (double entry).
   - **b) Logged sessions + Health workouts from other apps.** Needs a workout read (`workoutType` is currently in `writeTypes`, not `readTypes`). Drop workouts whose source is our own bundle, since they're already logged. Minutes only, never burn: `DailyBurn` and active energy stay as they are, so nothing gets double-counted. One extra explicit Connect for already-connected users.
   - *Recommended: b.* The whole point of the new watch is outdoor walks in Apple's Workout app, and under a) those walks would be missing from cardio minutes.
6. **Should our own watch runner feed VO₂ max?** It sets `config.locationType = .unknown` (`WatchWorkoutSession.swift:78`). Apple's docs name *its* Outdoor Walk/Run/Hiking workouts. **Not verified** whether a third-party `.walking` session marked `.outdoor` counts. *Recommended: no change in this plan.* Tell the owner to use Apple's Workout app for VO₂ max walks. Flipping to `.outdoor` would mislabel indoor walks, so it would need an indoor/outdoor choice on the wrist.
7. **Cardio minutes from Health, deduped by time too?** If the owner starts an Apple Workout-app walk *and* our phone live session for the same walk, b) counts it twice. *Recommended: drop a Health workout that overlaps a logged session by more than half its length, and say so in the ⓘ.*

## 8. Rollout (for owner approval, 2026-11-20)

Each phase is one build agent working from this doc and the matching `docs/map/` rows, with a local `xcodebuild` + hostless tests before its commit. Phase 0 is first and stays read-only.

**Coordination.** The add-food redesign is in progress elsewhere. Rules for every phase:
- Start each phase only after that work has landed on `main`.
- One agent at a time on Xcode or the simulator, per the working agreement.
- None of these phases touches `AddFoodSheet` or `Features/Nutrition/`.

| Phase | What | Files (expected) | Verification | Model |
|---|---|---|---|---|
| 0 | **Watch check, simulator.** Pair an iPhone 17 simulator with a watchOS simulator. Walk all three tabs, the "Not synced yet" state, sync after a phone log, water and quick-set from the wrist, a meal shortcut, and the stale-day notice (clock change). Start and end a workout; record what the simulator does for heart rate. Fix `docs/map/watch.md`, whose root row still lists the removed `ReminderListView`/`ReminderDetailView`. | Read-only except the map row and `validation-log.md` | Screenshots via XCUITest if the sim tools are denied (memory: fix-ios-screenshots-via-xcuitest); `devclean` after | Sonnet / low Opus (mapped) |
| 1 | **VO₂ max tracker.** §4 steps 1–4 and the pure half of step 6 (`vo2Trend`). Also: the ~2-year backfill, the 14–65 range note, and the §2 accuracy footer. | `Domain/Models.swift` (`HealthMarkerKind`), `Domain/HealthRanges.swift`, `Domain/TargetRationale.swift` and `Domain/EncouragementEngine.swift` (their `HealthMarkerKind` switches), `OurFitness/Info.plist` (Health usage text), new `Domain/CardioFitness.swift`, `Services/HealthKitService.swift`, `Features/Progress/ProgressView.swift` (`StatKind` + switches), `StatDetailSheet` host, tests, `map/progress.md`, `map/settings-health.md` | Build + hostless tests; simulator Health app with a manually added VO₂ max sample if it allows one (**not verified** that it does) | Opus high: HealthKit authorization traps |
| 2 | **Cardio minutes.** §4 step 5 plus `weeklyMinutes`, sourced per the answer to §7 Q5 (and Q7 if b). | `Domain/CardioFitness.swift`, `HealthKitService` (workout read, if b), `ProgressView.swift`, tests, `map/progress.md` | Build + tests, with pinned `now` and ISO-week edges | Opus high if Q5 = b (new Health read); Sonnet if a |
| 3 | **Optional: "felt dizzy" flag** (only if §7 Q2 = yes). It's a new field on the session model, so read `docs/data-model.md` first, then the schema-version rules and a migration test. Phone `LogPastSessionSheet` / end-of-session only, no watch wire change. | `Data/PersistenceModels.swift`, `Data/Schema.swift` (new SchemaV8 + `AppSchema.current`; an optional column is additive per `Schema.swift:10-19`), session DTO, `LogPastSessionSheet` (it lives in `Features/Workouts/LiveSessionCard.swift`), `docs/data-model.md`, the schema rows in `map/settings-health.md`, `OurFitnessPersistenceTests` | Build + both test targets | Opus high: schema |
| 4 | **On the owner's real watch**, after pairing. Everything Phase 0 couldn't show: real heart rate, Health permissions, and a VO₂ max estimate arriving after a few outdoor walks (weeks, §2). Owner-run, with a checklist from `watch-app-setup.md` Step 5. | none | Owner | — |

**Not in this plan:** intervals or intensity of any kind (§5), watch-side VO₂ max UI, heart-rate recovery and walking heart rate (Q4), and writing VO₂ max samples by hand.

**What could go wrong**
- A new read type makes already-connected users reconnect. The empty state must say so calmly, without the word "denied" (§4.3).
- `StatKind` has 13 exhaustive switches, but three spots fall through silently (`markerKind` `default: nil`, `canLog`'s exclusion list, `detailSheet` `default:`). See §9.
- The simulator may not generate heart rate or VO₂ max at all. If so, Phase 1's visual check is limited to the empty state and the code is verified only by tests. Say that plainly in the validation log.

## 9. Audit fixes (2026-11-20, binding for build agents)

An independent read-only audit checked this plan against the code at `5a0a7bd`. Blockers 1–3 were spot-checked in the code before being written here.

**Phase 1 must:**
1. **Never label VO₂ max.** `TargetRationale.statusWord` returns the *optimal* word for `.unknown` (`Domain/TargetRationale.swift:218-224`), and every marker-backed tracker goes through `markerMeaning` (`ProgressView.swift:~597`) and `HealthRanges.context(for:)`. A bare "no-classification case" would still say "healthy range". Return nil from both for `.vo2Max`, apply no `statusTint`, and add a test pinning it.
2. **Not use a one-time backfill flag.** Already-connected users have the step-backfill flag set (`Domain/HealthAccess.swift:21-23`), and a VO₂ max read before they reconnect returns nothing (denied reads look empty), so a one-shot backfill would never run again. Instead, every sync queries from the newest stored `vo2_max` day, or 2 years back if there is none.
3. **Make the tracker findable** (owner choice, §7 Q8). `hasLoggedData` only matters while `enabledStatsRaw` is empty (`ProgressView.swift:104-110`). Anyone who has ever edited trackers never sees new ones appear, and nobody sees an empty state.
4. **Handle the silent fall-throughs:** set `markerKind` → `.vo2Max` explicitly, add `.vo2Max` and `.cardioMinutes` to `canLog`'s can't-log list (no manual VO₂ max entry), and give `detailSheet` a real case.
5. **Show the date only** ("as of Nov 18"). `HealthMarkerDTO.date` is a day key, while `Freshness.label` takes a `Date` and prints a time.
6. **Fetch existing markers once per backfill** and dedupe in memory. `upsertMarker` fetches all markers on every call (`HealthKitService.swift:462-466`); about 300 samples would mean about 300 fetch+save cycles.
7. **Update `OurFitness/Info.plist:30`** (Health read usage text) to include cardio fitness (VO₂ max). Edit the plist directly; there's no `info:` block in project.yml. Run `xcodegen generate` after adding `Domain/CardioFitness.swift`.
8. **Also update** the "Add health marker kind" row in `docs/map/progress.md` to list the `TargetRationale` and `EncouragementEngine` switches.

**Phase 2 must:**
- **Define which activities count as cardio.** Pilates, yoga and stretching are `ActivitySessionDTO` too (`ActivityCatalog.swift:24-29`). Decide whether legacy `CardioSessionDTO` rows count. Test both.
- **If Q5 = b:** drop Health workouts whose source is `com.ourfitness.app` **or** `com.ourfitness.app.watchkitapp` (the watch saves its own; `project.yml:206`). Which ID HealthKit stamps is **not verified**, so log the source on first run. Add "workouts" to the Info.plist usage text.

**Known and accepted:**
- An older TestFlight build reading a `vo2_max` row falls back to `.ldl` (`PersistenceModels.swift:381`), so a rollback would show VO₂ max as LDL. Don't roll back past Phase 1.
- Checked by the audit: the phone never writes HKWorkouts, so phone and watch can't duplicate each other. `DailyBurn` is unaffected. Appending to `HealthMarkerKind` needs no schema bump.
- `Domain/Models.swift` is shared with other work. Check whether the add-food redesign touched it before starting Phase 1.

**Owner question added:**

8. **How do you find the VO₂ max tracker?** (a) A one-line hint under Settings › Apple Health ("Have an Apple Watch? Add the Cardio fitness tracker in Progress › Edit trackers."), plus it appears automatically once data exists for anyone who hasn't edited trackers; or (b) on by default for everyone, showing the calm empty state until data arrives. *Recommended: a.* Most people have no watch, so a default-on empty card would read as broken. Either way it's the same for every goal.

## 10. Owner decisions (2026-11-20) — these override the recommendations above

- **Phases 0–3 approved.** Order changed: **1 → 2 → 3 → 0**. The add-food redesign is using Xcode and the simulator in its own worktree (`../Our-Fitness-addfood`), so the simulator walk goes last and can also check the new trackers.
- **Q5 = b, and the general rule is to integrate with Apple Health as much as possible** ("for accuracy and feature"). Cardio minutes include Health workouts from other apps (Apple's Workout app), deduped per §7 Q7 and §9.
- **Q2 = yes, the "felt dizzy" flag, with real data recorded alongside it** (Phase 3):
  - Optional severity: mild / moderate / severe.
  - **Average and peak heart rate from Health over the session window.** `heartRate` is already in `readTypes` (`HealthKitService.swift:34`), so this needs no new permission. If there are no samples, store nil and show "no heart-rate data" — never an estimate.
  - **Also write it to Apple Health as a Dizziness symptom** ([`HKCategoryTypeIdentifier.dizziness`](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/dizziness); exists per Apple's docs, search summary). The value is believed to be an `HKCategoryValueSeverity` (**not verified**: open the docs page before coding). It goes in `writeTypes`, so it's a new write permission, granted only via the explicit Connect action (hard rule 4 / crash traps). If permission isn't granted, the flag still saves locally.
  - Still never a medical signal: no warnings, no gating, no "see a doctor" nag beyond §1 rule 2's single ⓘ line.
- **Q8 = b: the VO₂ max tracker is on by default for everyone**, with the calm empty state. It has to reach existing users who already edited their trackers (non-empty `enabledStatsRaw`): add it once via a one-time migration flag that appends `vo2Max` to the stored set, without touching anything else in it. Same for every goal.
- **Q4: skip** heart-rate recovery and walking heart rate.
- **Watch:** a couple of years old, currently on the owner's wife's iPhone. To use it with the owner's own iPhone it must be unpaired from hers and re-paired (Apple's normal flow; it erases the watch). Phase 4 waits for that.
- **Machine rule for every build agent:** work only in `../Our-Fitness-cardio`. Before any `xcodebuild`, wait until `pgrep -x xcodebuild` is empty, and use a private `-derivedDataPath` inside the worktree. Never boot a simulator in Phases 1–3. Filter build output to errors.
