# Validation records (moved from CLAUDE.md)

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

Added the Strength card + tape-measure trackers (rows in Where to touch), the Today day-insights card, the shared `TrainingHistorySheet`, the Meals past-day guard and the Train set back-fill. An independent review of the pre-existing uncommitted work found and fixed: session-delete toast firing after a failed write, and the Meals return-to-today never firing on foreground (scenePhase is background → inactive → active, so the pair never matched; now a flag). Known, not fixed: `DayInsights` says "Nothing logged yesterday" to a brand-new profile; `TodayView` freezes its day keys at init, so a view kept alive across midnight reads stale (unconfirmed whether `RootView` rebuilds it).
Verified locally on Xcode 26.6, **iPhone 17 Pro simulator**: app build; 544 unit + persistence tests; `OurFitnessUITests` smoke on an erased simulator (all tabs open, no crash report). **In-place upgrade:** built the previous commit, onboarded a profile with its UI test, installed the new build over it without erasing — launched on the old store with the profile intact (additive `BodyMetricModel` columns). Not verified: the Strength card and the new tape cards with real data on screen (the smoke profile has none), physical phone/watch.
Testing convention going forward: simulator checks run on the iPhone 17 Pro (`-destination 'platform=iOS Simulator,id=<udid>'` — `name=iPhone 17 Pro` failed to resolve in `xcodebuild` on this Mac, the id works).

