# Validation log and milestone history

> Moved from CLAUDE.md so the always-loaded file stays thin. Chronological record of what was actually verified (and what was not) at each milestone. Append new milestone records at the bottom; do not rewrite old ones. This is history, not current guidance: CLAUDE.md, docs/map/*.md and the code are authoritative.

## Milestone documentation rule

Update affected Markdown in every milestone commit alongside its code. Record current behavior, changed architecture/routing, validation actually performed, and remaining limitations. Keep dated incident narratives and research intact, with explicit historical/planned status where guidance has been superseded. Do not claim tests or external signing state were verified without evidence.

## Audit remediation and handoff

The 2026-09-14 audit-remediation handoff note (`docs/audit-handoff.md`, deleted Oct 2026 as superseded) is recoverable with `git show ff15fa5:docs/audit-handoff.md`. The open backlog it fed into is [next-audit-scope.md](next-audit-scope.md) (privacy controls,
erase-local-data, measured performance), which is still accurate.

When a session hands off, record unverified edits explicitly and update affected
docs in the same milestone commit.

Successful repository saves, live-session changes, and defaults changes schedule
one coalesced phone-to-watch snapshot. The snapshot fetches 30 days of food logs
and today's water/steps through `Repos+SnapshotReads.swift`; historical shortcut
resolution and full medication history remain available. Move refreshes its
Health readings on pull-to-refresh and foregrounding. Watch water keeps the
original action timestamp. `SessionInputValidation` resolves known activity
values on the phone and permits bounded custom intensity only for Other.

The separate hostless `OurFitnessPersistenceTests` target compiles Domain,
persistence models/repositories and selected session services directly. It checks
failed-save recovery, completion idempotency, stale runners, seeded profiles and
query equivalence with multi-year fixtures. System notification cleanup is
injected out of hostless tests; physical phone/watch integration still needs
manual verification. No historical schema or persisted raw value was changed.

## Goal merge (Oct 2026) — validation record

Build and Circuit were merged into one app (see Goals). Verified locally on Xcode 26.6:
app + watch + widget build; `OurFitnessTests` + `OurFitnessPersistenceTests` pass;
`OurFitnessUITests` smoke test passes on a freshly erased iPhone 17 simulator (it had been
failing on `main` — uppercased button label, keyboard over the button, and the unhandled
Connect-Health step); every tab was screenshotted on a Build-muscle profile (light theme,
rings, merged Train list, heart-health card). Not verified: physical phone/watch,
the Lock Screen Live Activity palette on device, and the launch backfill against a real
pre-merge Build store.

Follow-up the same day: app + watch icon recoloured into the light palette (same artwork:
cream background, deep-sage glyph, terracotta bell); the CI placeholder generator uses the
same tokens; the Lock Screen Live Activity banner is cream with dark text (the Dynamic
Island stays system black). Duplicates removed: meal-idea detail sheet → `MealIngredientDetailSheet`,
camera free-text form → `DescribeMealForm`, three slot pickers → `SlotPicker`, two macro
chips → `MacroChip`, private info helpers → `InfoSheet` components, two food-search tasks
→ `debouncedFoodSearch`/`FoodResultRow`, Pilates list → `RecentActivitySessions`, the
double "WATER" label, the Meals empty-state's second Add button, two duration formatters,
and the double nudge computation. Same validation as above (build, unit + persistence +
UI smoke tests, simulator screenshots).

## Restaurant menus, supplement brands, meal reminders (Oct 2026) — validation record

Bundled DB rebuilt from FDC Foundation + Branded 2026-04-30 (SR Legacy 2018-04, final): 271,931 USDA rows (2 old IDs gone — white/whole-wheat bread; nothing references bundled-DB IDs, logs store their own macros) + 16,562 menu/product rows from 58 chains and 18 supplement brands, 66 MB. Negative USDA nutrients clamp to 0 in the build script. Every chain/brand file was audited row-by-row against its official source (fixes and removals logged in each file's `notes`). Audit measured on the Mac: FTS queries 5–20% slower than the old DB ("chicken" 11.7 → 14.1 ms), restaurant catalog loads off-main in ~100 ms (+~10 MB), menu filter < 1 ms per keystroke on the largest menu. Verified locally: app build, `OurFitnessTests` + `OurFitnessPersistenceTests`, `OurFitnessUITests` smoke test on an erased iPhone 17 simulator. Not verified: physical device timings, meal-reminder delivery and the cold-launch tap into Meals, the iOS 26 delete popover position on device.

## Strength + tape measurements, Today insights (Oct 2026) — validation record

*Superseded in part (Oct 2026, progress-tracking branch): the Strength card described here listed weighted lifts only and its `gainLb` could not go negative; it now lists every trained exercise and can show a decline, and the Training tracker is "Weekly Reps". See the record at the bottom of this file and [map/progress.md](map/progress.md).*

Added the Strength card + tape-measure trackers (rows in Where to touch), the Today day-insights card, the shared `TrainingHistorySheet`, the Meals past-day guard and the Train set back-fill. An independent review of the pre-existing uncommitted work found and fixed: session-delete toast firing after a failed write, and the Meals return-to-today never firing on foreground (scenePhase is background → inactive → active, so the pair never matched; now a flag). Known, not fixed: `DayInsights` says "Nothing logged yesterday" to a brand-new profile; `TodayView` freezes its day keys at init, so a view kept alive across midnight reads stale (unconfirmed whether `RootView` rebuilds it).
Verified locally on Xcode 26.6, **iPhone 17 Pro simulator**: app build; 544 unit + persistence tests; `OurFitnessUITests` smoke on an erased simulator (all tabs open, no crash report). **In-place upgrade:** built the previous commit, onboarded a profile with its UI test, installed the new build over it without erasing — launched on the old store with the profile intact (additive `BodyMetricModel` columns). Not verified: the Strength card and the new tape cards with real data on screen (the smoke profile has none), physical phone/watch.
Testing convention going forward: simulator checks run on the iPhone 17 Pro (`-destination 'platform=iOS Simulator,id=<udid>'` — `name=iPhone 17 Pro` failed to resolve in `xcodebuild` on this Mac, the id works).

## Progress tracking: reps at a weight (Oct 2026) — validation record

Implemented plan sections 3.1 to 3.5 of [progress-tracking-plan.md](progress-tracking-plan.md) on branch `claude/awesome-dirac-rremd5` in a container with no Xcode: new `Domain/RepHistory.swift`, `StrengthProgress`/`TrainingHistory`/`EncouragementEngine` changes, `Repos.updateExercise` + fixed-load stamping and one-time backfill, rep counter / hold timer / `ExerciseInfoSheet` / new `ExerciseProgressSheet` / Strength card / Weekly Reps tracker / `TrainingHistorySheet` UI, new-best and weekly-reps toasts. Docs restructured the same day (thin CLAUDE.md, `docs/map/`, this log).

**Verified**
- Linux harness (docker image `ourfitness-swift`: `Domain/*.swift` + `Shared/WatchSyncPayload.swift` + all `OurFitnessTests/*.swift` in a throwaway SwiftPM package, run by the docs-sync pass after all code edits): **601 tests executed, 0 failures, 0 compile errors** (baseline before the change: 545). Covers `RepHistoryTests` (exact-weight folding, one-tap vs rep-counter rows, week edges, holds, duration, last time / same day last week, comparisons, bests and the 2-day baseline guard, weekly notes and the 75% edge, once-per-week announcement gate, canonical 0.01 lb weights), the `StrengthProgress` negative `gainLb`, `TrainingHistory` rep counts and `ExerciseLine.tally`, `SetEditCaloriesTests` (load override), `EncouragementEngineTests` (new copy, banned-words check).
- `swiftc -parse` (syntax only) on `RepCounter`, `ToastCenter`, `ExerciseProgressSheet`, `ExerciseInfoSheet`, `ProgressView`, `TrainingHistorySheet`. Pure formatting/folding helpers extracted from those views were compiled against the real `Domain/` files on Linux and probed (reference lines, tally strip, `TrainingSummary.make`, `StrengthEntry.entries`).
- Reviews: each agent re-read its own diff adversarially; an independent review of the integrated change found three real defects (weekly-reps toast not wired, no new-best/weekly toast on the one-tap `+1` path, metric vs imperial entry splitting one weight into two lines), all fixed and re-tested on Linux. Docs: all relative Markdown links re-checked; stale mentions of the removed set-based APIs grepped across every `.md`.

**NOT verified**
- Xcode compile of any SwiftUI/SwiftData code (`Features/`, `Repositories.swift`, `Seeder.swift`, `ToastCenter.swift`, `WatchSyncService.swift`) — API uses such as `chartForegroundStyleScale`, `Menu`/`Section`, `onChange`, and `StatDetailSheet` generic inference are unconfirmed.
- `OurFitnessPersistenceTests`, including the new `FixedLoadTests` (17 tests: `updateExercise`, stamping, backfill idempotence, once-flag, `updateSet` re-pricing); the failed-save branch of `backfillFixedLoadWeightsOnce` is not injectable and untested.
- Simulator, physical phone and watch: sheet layouts (medium-detent reference block, wheel inside a `ScrollView`, 375 pt comparison grid), hold haptic and backgrounding mid-hold, toast order and the weekly-note gate against real UserDefaults, `UnitSystem` day-label formats.
- In-place upgrade of an existing store with nil-weight fixed-load rows (backfill, then a load edit) — the backfill and `updateExercise` stamping have never run against a real pre-change store.
- Full-history fetch cost per rep save (`Repos.setHistory(limit: 100_000)`, `Repos.weeklyReps`) against a multi-year fixture; non-UTC time zones (Linux runs were UTC).
- Research figures in the Weekly Reps ⓘ (about 10 hard sets per muscle per week; 80-120 reps rule of thumb) are unchecked against the papers.
- The Linux harness cannot catch a Swift 6 / iOS-only API error in files it does not compile.

## Docs audit, build and test on `main` (2026-10-18) — validation record

Verified locally on Xcode 26.6, `main` at `ff15fa5` (before the docs and comment-only edits below): `xcodegen generate`; app build (scheme `OurFitness`, iPhone 17 simulator, `CODE_SIGNING_ALLOWED=NO`) **BUILD SUCCEEDED**; `scripts/validate-ci-invariants.sh` exit 0; scheme test run **TEST SUCCEEDED** with 496 `OurFitnessTests` + 26 `OurFitnessPersistenceTests` cases, 0 failures (run through `xcodebuild test`: fastlane gems are not installed on this Mac). This is the first Xcode compile of the progress-tracking branch code (reps at a weight, `FixedLoadTests`) that the entry above lists as unverified.
Not run: `OurFitnessUITests` smoke test; any simulator walk-through, physical phone or watch check; the in-place upgrade of a store holding nil-weight fixed-load rows.
Docs: deleted the superseded or duplicate `where-to-touch-notes.md` (every row already lives in `docs/map/`; its Strength entry was stale), `validation-records.md` (the same three records are above), `audit-handoff.md`, `medication-reminders-plan.md`, and the old-two-mode research and plan docs (`health-tracking-ui-plan`, `encouragement-system-plan`, `activity-and-ai-expansion-research`, `nutrition-plan-research`, `RepCheck`), plus root `nutrition-plan.html` and `screen.png`. All are recoverable with `git show ff15fa5:docs/<name>`. Fixed dead links (`AGENTS.md` → `map/watch.md`), the Reminders/plant text in `watch-app-setup.md`, and code comments that cited deleted docs.
Shipped 2026-10-18 from the Mac (fastlane not installed): Release `xcodebuild archive` (automatic signing, team `GYFN949Q5E`) → ARCHIVE SUCCEEDED with the watch app embedded; `-exportArchive` with `destination upload` and `manageAppVersionAndBuildNumber` → "Upload succeeded". The archive's own build number reads 1; the number App Store Connect assigned was not captured, so check TestFlight. Not verified: App Store Connect processing finishing, and the build on a device.
