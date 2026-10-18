# Where-to-touch notes (moved from CLAUDE.md)

Behaviour notes and invariants per row of the CLAUDE.md "Where to touch" table. Look up one row at a time; do not read whole.

### Add-exercise sheet
ONE sheet, one field set for everyone: name, reps/duration, isometric, optional fixed weight (any non-hold; blank on a rep exercise = it logs through the rep counter, `Draft.tracksWeight` is derived from that, there is no toggle). Hands back an `AddExerciseSheet.Draft` normalised to a valid shape; the call site (`ExercisesCard`) owns the rep range + `Repos.createExercise`. Never add a second add-exercise sheet

### Exercise ⓘ info sheet
ONE sheet, same for every profile; opened from `ExercisesCard` rows (passes today's tally) and from the rep counter / isometric timer. Content priority: `Movement.postExerciseHint` → `ExerciseInfo.meta` → on-device AI (only when neither library knows the movement). Single `loadAIIfNeeded`

### Isometric timer UI
30/45/60/90s preset pills above the 5-second wheel (presets + fine control, same shape as the live-session picker)

### Rep counter
a wheel picker for the set's count (1–100 reps, or 1–180 min for a `.duration` exercise; same `.wheel` idiom as `IsometricTimerView`), starting on this week's last logged count for that exercise (else 10 reps / 5 min) and keeping its value after Save set — no tap-to-count buttons. Half-sheet (`[.medium, .large]`). The weight field (labelled optional, with the dumbbell/one-arm hint — the app doesn't model per-arm vs pair; calories ignore weight) pre-fills from this week's last logged weight for that lift and never overwrites typing. Opened from every `ExercisesCard` row; the field shows only when `tracksPerSetWeight`, a `.duration` exercise counts minutes. The post-set strip (`EncouragementEngine.repProjection(setCalories:totalCaloriesToday:)`) prints the figure the set was stored with; the weekly-volume (hypertrophy) toast fires only for unloaded rep sets — never minutes or fixed-load movements

### Edit / delete / back-fill a logged set
the ONE set editor, for any day: a 7-day strip (plus the opening day if older) switches days; tap a row → `EditSetSheet` (same file), trash = delete, "Add a set" → the same `EditSetSheet` with `isNew: true` (writes `Repos.addSet` on that day: now for today, else a minute after the day's last set, else midday; calories via `Repos.setCaloriesEstimate`). Reached from the clock on every `ExercisesCard` row (today) and from an exercise row in `TrainingHistorySheet` (that day), so don't add a second one. Writes `Repos.updateSet` / `Repos.deleteSet`; "Delete … and all its sets" (confirmed) = `Repos.deleteExercise`; press-and-hold on an `ExercisesCard` row raises the same confirmed delete as a shortcut

### Per-set calories (log, edit, preview, watch)
THE per-set estimate, dispatched on exercise SHAPE, never goal: hold → `caloriesForIsometric` + `ExerciseInfo` MET; `.duration` → `caloriesForDuration` (reps = minutes); fixed `loadLb` → flat `caloriesForReps(reps:loadLb:)`; else `caloriesForReps(reps:exercise:)`. Phone callers go through `Repos.setCaloriesEstimate(exercise:reps:holdSeconds:bodyWeightLb:)` (rep counter, hold timer, `ExercisesCard` +1, `EditSetSheet` preview, `Repos.updateSet` recompute); `WatchSyncService`'s quick-set and `ExerciseInfoSheet` call `caloriesForSet` directly. Never re-branch the math at a call site. Tests: `SetEditCaloriesTests`

### Log pilates
ONE manual form: `LogPastSessionSheet` in `Features/Workouts/LiveSessionCard.swift` (focus-area chips + notes appear when the chosen activity is Pilates). `Features/Workouts/ActivitySectionCard.swift` (`section: .pilates`, an optional Train section

see next row) is ring/streak/weekly goal + "Log Pilates" only — NO session list — and opens that sheet via `lockedActivityId: section.activityId`; a live session with the Pilates activity writes only a `PilatesSessionDTO` (`Repos.completeLiveSession`), so it lists once. Never add a second Pilates form or give `ActivitySectionCard` its own list. Today/yesterday Pilates sessions are listed, edited and deleted in `RecentActivitySessions` (see next row)

### Optional Train sections (Pilates / Yoga / Stretching)
ONE card for every section (ring of sessions this week vs weekly goal, streak, "Log <section>" → `LogPastSessionSheet` locked to the activity). Pilates reads `PilatesSessionModel`; Yoga/Stretching read `ActivitySessionModel` scoped by `activityId`. Enabled set = AppStorage `trainSections.<uuid>` CSV: "" (never set) → sections with logged data (existing Pilates users keep their card), "none" = explicitly empty. Pilates keeps goal key `pilatesWeeklyGoal.<uuid>`. Add = "Add a section" pills in `WorkoutsView`; remove = press-and-hold (context menu) → confirm; logged data is kept. Tests: `TrainSectionsTests`

### Edit a logged session's duration
ONE duration editor, used only by `RecentActivitySessions` (same file) — THE today/yesterday session list on Train, covering `ActivitySessionDTO` (writes `Repos.updateActivitySession`, which recomputes `caloriesEst` from the stored MET; delete `Repos.deleteActivitySession`) and `PilatesSessionDTO` (writes `Repos.updatePilatesSession`; Pilates stores no calorie figure, the burn is derived on read via `caloriesForPilates`; delete `Repos.deletePilatesSession`). Caller owns the preview + the write and returns false on failure so the sheet stays open. Deleting a session: the trash button or a press-and-hold on the row's info area raises ONE `confirmationDialog` (`pendingDelete`); no context menu. Train is the home for correcting today/yesterday sessions — Progress › Training history stays the cross-day read + delete surface

### Log cardio (run / bike / swim / row / hike)
"Log session" on `LiveSessionCard` (Train tab). Saves an `ActivitySessionDTO` with the activity's Ainsworth MET from `Domain/ActivityCatalog.swift`. There is no separate cardio logger: `CardioSessionDTO` is legacy read-only (see Data model) — never add one back

### Exercise list (Train tab)
THE one list of every exercise the profile owns (lifts, holds, quick-log movements, each once), A→Z, with a `ProgressRing` header (distinct exercises logged today / total + today's burn). `WorkoutsView` order: `LiveSessionCard` → `ExercisesCard` → "Training history" row → enabled `ActivitySectionCard`s (Pilates, Yoga, Stretching) → "Add a section" → "what should I work on?". Row controls come from shape: isometric → hold timer; `tracksPerSetWeight` → rep counter; `isOneTapLoggable` → inline +1 (+1 min for duration), row tap still opens the rep counter. The inline undo removes only sets that +1 created in this view's lifetime (`quickLoggedSetIds`) — never a rep-counter set; anything older is corrected via the clock. Every row: clock → `SetHistorySheet` · ⓘ → `ExerciseInfoSheet`. Deleting an exercise: press-and-hold the row body (`simultaneousGesture(LongPressGesture(minimumDuration: 0.5))` on the two row-body buttons only → one `confirmationDialog` attached per row and keyed off the card's single `pendingDelete`, so the iOS 26 popover points at that row; `Haptics.warn()` fires once when the hold is recognised; the release tap is ignored while `pendingDelete` is set) or the confirmed action in `SetHistorySheet` — rows sit in a `Card`'s VStack, where `.swipeActions` is a silent no-op. Sheets hang off the list, not the rows

### Live sessions (timer)
`ActivityTile` / `IntensitySection` in that file are shared by `ActivityPicker` (start live) and `LogPastSessionSheet` (log after the fact)

single definitions, don't re-copy. Phone/watch completion is centralized in `Services/LiveSessionCompletionService.swift` + `Data/Repositories/Repos+SessionCompletion.swift`

### Live Activity (Lock Screen)
[docs/live-activity-setup.md](docs/live-activity-setup.md)

### AI exercise insights
consumed only by `Features/Workouts/ExerciseInfoSheet.swift`

### AI "what to work on?" suggestions
both take `fitnessGoal:` for a light tilt (gain → loadable lifts; lose → higher-burn, joint-friendly) → `WorkoutGoalSheet` in `WorkoutsView`. Tests: `ExerciseGoalMatcherTests`

### **Shared on-device-AI scaffolding**
`isAvailable`, `generate(instructions:_:)` (session + do/catch, returns nil on any failure → caller falls back to its Domain matcher), `goalLine(_:gain:lose:)`, `Cache<Value>` (JSON in UserDefaults). All five AI services use it; prompts + `@Generable` shapes stay in each service

### Live-session activities
stable ids `otherId` / `pilatesId` / `walkingId` / `yogaId` / `stretchingId` (Stretching = Ainsworth 02101 "stretching, mild", 2.3 MET; the watch maps it to `.flexibility`) (use the constant, never the literal). Walking/running/hiking are excluded from the day's burn — the exclusion set lives in `DailyBurn`, not here

### Add / update curated food
aliases drive matching, curated shadows USDA. Append new foods to `expanded` (tie-break = `all` order; check Atwater + no alias collisions)

### Add food (search + describe + browse, one sheet)
single field: empty = recipes/recently logged/favorites pills + full library (`LazyVStack`, order favorites → `FoodAffinity.frequencyByFoodId` 30-day → rest via `defaultOrdered`); typed = "Log ‘…’" describe card (pushes `DescribeMealForm`: AI/full-DB parse + manual macros — also `CameraFoodLogSheet`'s fallback, the ONE free-text logger) + matches via the shared `View.debouncedFoodSearch` / `FoodResultRow` (also used by `IngredientFoodSearchSheet`). Picks — including `MoodMealSheet` meal ideas — confirm in `MealIngredientDetailSheet`. `onSave` returns the write's success; the sheet dismisses only on `true` (rule 9). Used by Meals; never add a second food-search/log sheet, and the Meals empty state has no button of its own ("Add food" sits right above it)

### Restaurant / chain menus (search + browse)
one file per chain, numbers ONLY from the chain's own published nutrition (official page/PDF/calculator, or the Nutritionix menu the chain's site links), five nutrients only (never sodium/sugar/sat fat — see `capCoverage`). Merged into `usda-foods.db` by `python3 scripts/build-food-db.py --merge-restaurants-into OurFitness/Resources/usda-foods.db` (idempotent; items land in `foods` as `rest:<slug>:<item>` so normal search finds them, plus `restaurant_chains` / `restaurant_items`). The merge drops limited-time rows, exact duplicates and rows whose 4P+4C+9F contradicts the stated calories (`_broken_row`; alcohol exempt) — source typos are dropped, never corrected. Swift: `Domain/RestaurantCatalog.swift` (`RestaurantMatcher`: compacted-alphanumeric exact → prefix ≥3 → later-word prefix → one typo ≥5; `split` peels a whole chain name off "shake shack fries") loaded once into memory; UI = Restaurants row in `AddFoodSheet` → `Features/Nutrition/RestaurantMenuView.swift`, picks route through the same `MealIngredientDetailSheet` flow. Tests: `RestaurantCatalogTests`. The same folder holds sports-nutrition brands (`"kind": "supplement"` → `RestaurantChain.isBrand`: header "Brands", "Products · N items", dumbbell icon) — USDA Branded mostly lacks Supplement Facts products (whey, gainers), so these come from each brand's own label. Every file was re-audited against its source in Oct 2026 (bot-blocked sites re-checked in the Mac's Chrome); a new file needs the same check before it merges. Skipped for lack of usable official data (Oct 2026): Burger King, Sonic, Jack in the Box, Smashburger, MOD Pizza, Jason's Deli, Wawa, Cracker Barrel; brands Muscle Milk, Garden of Life Sport

### Camera food label scanner
no separate free-text form. `onLog` returns the write's success; dismiss only on `true`

### AI "what are you in the mood for?"
flavours have strong/weak signals scored by density, antagonist suppression (salty↔sweet/fruity, warm↔cold) and gated+capped affinity, so a stated flavour never returns its opposite; plus a small goal macro tilt (gain → protein/calorie density; lose → fibre/leaner) → `MoodMealSheet` in `NutritionView`; a meal idea opens `MealIngredientDetailSheet(.logging)` via `SuggestedMeal.resolvedIngredients()` (single-ingredient fallback at the meal's `perServing` when nothing resolves), so a logged idea is the sum of its ingredients. Tests: `MealCravingMatcherTests`

### Meal log UI + day history + past-day logging
order: day strip → Add food (+ camera) → "What are you in the mood for?" → the day's log → macro rings (totals card) → `HeartHealthCard` → weekly trend → smarter swaps (today only). Day strip (last 7 days, dot = has logs) for quick switching + a history button opening `Features/Nutrition/MealHistorySheet.swift`. **`MealHistoryList` is THE day-history list** (one row per logged day: date · totals · the meals eaten); the trend sheet's "Recent days" renders the same component, so never write a second one. All three entry points route through `NutritionView.selectDay(_:)` so animation + haptic match. **Past-day guard:** with a past day selected the page, selected pill, Add button and `MealHistorySheet` wear the `accent2` tint, a banner offers "Back to today", and every add (`requestAdd` — Add food and the mood sheet) asks first via `confirmationDialog` (Add to <day> / Add to today instead / Cancel). `returnToToday()` (1 s "Back to today" toast) fires on tab re-appear and on background→active, so a stale past day never survives a new session No calendar picker — a grid makes users hunt through empty dates; the list shows the days they actually logged

### Ingredient-level editing / logging
takes `targetDate:` for past-day logging. Also owns the shared `SlotPicker` (all `Slot.allCases`, used by every meal form) and `MacroChip` — never re-roll either

### Heart-health micros (fiber floor + sodium/sugar/satfat caps)
rendered in `NutritionView` after the totals card. **Only fiber gets a ProgressBar**: sodium/added sugar/sat fat exist in no curated or USDA food row (camera label scan is the only source), so those three render off `MacroBudget.capCoverage` — `.none` = em-dash vs the cap ("not tracked"), `.partial` = `N+` floor figure, `.full` = real inverted bar. Never draw a cap bar straight off `DailyTotals`: a summed 0 would colour itself safely-under-cap for someone who ate 3,000 mg. Pass `entries:` (the day's `[FoodLogEntryDTO]`) to get `.partial`/`.full`; omitted, coverage falls back to what the totals alone can prove

### Remaining macros / headroom under caps
`Repos.backfillHeartHealthTargets` recomputes those at launch). Prefer `remaining(totals:targets:entries:)` — it also nils the three caps when nothing logged measured them, so nil = "no number to show" (no cap configured **or** unmeasured); use `capCoverage` to tell those apart

### Calorie / macro target math
see Calorie math

### Move card (steps + 2×3 cols)
top of Today. Generic over a `steps` `@ViewBuilder` slot: `TodayView` passes the one `StepsCard(embedded: true)`, rendered at the top of the card; then row 1: Apple Total · Our Total Estimate · Training Only; row 2: Distance · Flights · Heart Rate. MoveCard draws **no step figures of its own** — the slot is the `StepsCard` (an earlier steps row duplicated its count, goal, goal-picker and info sheet, plus a stale gross-MET formula string). Single `metricColumn` helper (uniform 22pt value font, no differential shrink). `activityRow(kcal:)` takes `Int`. Burn figures come from `DailyBurn.breakdown` (never re-derive MET math or the step-overlap exclusions here — `countedCardio` / `countedActivities` read `DailyBurn`'s sets); unit conversions via `Units.kgPerLb` / `Units.kmPerMile`; the 7 column info sheets sit on `Components/InfoSheet.swift`. Move only renders when `profile.healthGranted` — ungranted, `TodayView` shows `connectHealthCard` at the top instead; that card is the ONLY Health-connect surface on Today (`StepsCard` has no Connect pill)

### Steps card (Today only)
one card, the same for everyone; `embedded: true` inside `MoveCard` (no card chrome, title "Steps"), standalone before Health is connected: `ProgressRing` + projection + pace-vs-yesterday + 7-day strip + week-to-date active cal / exercise min + weekly streak chip + milestone toasts. One goal-picker sheet (shared `Components/GoalPickerSheet.swift`; daily-target + days/week wheels) + one info sheet (`StepsInfoSheet`, on `Components/InfoSheet.swift`). The goal only sets the default daily target (`computedTargets.stepsDaily`). Goal keys live in `StepsGoalPrefs` in the same file; `StepsGoalPrefs.resolve(custom:goalDefault:)` (stored 0 = no override) is the one resolver, shared with `TodayView`'s streak math. Never add a second steps card

### Water tracker (presets + day-streak)
the bar row reads "TODAY")

### Log water (shared path — use for ANY new water surface)
one write + remembers the repeat-last amount + one copy of the toast; also owns the `waterGoalFlOz.\(profileId)` / `waterLastFlOz.\(profileId)` AppStorage keys. No explicit haptic (ToastCenter.show fires one)

### Water quick-log (app-wide FAB)
tap = repeat last, press-and-hold = dim screen + radial preset picker; logs via `WaterLog.add`. Overlaid in `App/RootView.swift`

### Today burn estimate
see Calorie math. The step-overlap exclusions live here as `stepOverlappingCardio` / `stepOverlappingActivityIds`. Tests: `OurFitnessTests/DailyBurnTests.swift`

### Meal-logging push reminders (learned timing)
breakfast/lunch/dinner only; median of each day's earliest REAL-TIME log (timestamp day == `date` key) over 14 days, today excluded; needs 4 days before scheduling or display; no fallback defaults; +60 min grace; quiet hours 22:00–06:00; plans today + 2 days (≤ 9 requests), skips a slot already logged that day; wall-clock components (DST). Tests: `MealLogPatternTests`. Scheduling `Services/MealReminderService.swift` (activated in `OurFitnessApp`), opt-in per profile `mealReminders.enabled.<uuid>` (default off); ids `mealLog.<day>.<slot>` (`AppNotificationDelegate.willPresent` banners nothing, so they stay silent in foreground, where the in-app nudge covers it; the `reminder.` prefix belonged to the removed Reminders tab and is swept once by `RetiredReminderCleanup`); re-plans on `.repositoryDidSave` (coalesced), foreground (`RootView`) and the Settings toggle; authorization ONLY from the toggle (`MealReminderService.enable`). Tap posts `.openMealsTab` → `RootView` selects Meals. Settings: "Meal logging reminders" + caption with learned times; the in-app toast toggle is "In-app meal nudge" (`nudge.meal.enabled`)

### Watch companion sync
`WatchConnectivity`: `updateApplicationContext` (phone→watch push), `transferUserInfo` (watch→phone actions). Watch is a thin client with no local SwiftData; phone is source of truth

### Adding anything to the watch's data
never add a second key.** `updateApplicationContext` replaces the whole dictionary, so a second key silently clobbers the first. Phone builds it in one pass in `WatchSyncService.pushSnapshot`; give any new field a default in the hand-written `init(from:)` (a memberwise default is ignored by synthesised `Codable` for a missing key, which would break older payloads wholesale). **Only `WatchSnapshotEnvelope` and `TodaySnapshot` have that hand-written decoder.** The nested element types — `QuickLogExercise`, `MealShortcut`, `LiveSessionSnapshot` — use synthesised decoding, so a new NON-Optional field on any of them is a breaking wire change: the throw propagates out of `decodeIfPresent([…])` and costs the watch the whole envelope (today's numbers included), not just that element. Add it as Optional, or bump `currentSchemaVersion`. Tests: `OurFitnessTests/WatchSyncPayloadTests.swift` (incl. the two tests pinning that boundary)

### Wrist → phone mutations
never trust numbers off the wire, a stale snapshot must not be able to write wrong data

### Watch app (thin client, no local SwiftData)
root `OurFitnessWatchApp.swift` is a 4-tab `TabView`: `WatchTodayView` (glance + water quick-log) · `WatchTrainView` (`WatchLiveSessionView` + `WatchQuickLogView`) · `WatchMealsView` (the Reminders tab was removed with the feature). State in `WatchSyncStore.swift` — [docs/watch-app-setup.md](docs/watch-app-setup.md)

### What may appear in the watch quick-log
a wrist `+1` on a barbell press was logging a weightless rep into training volume. The filter is `ExerciseDTO.isOneTapLoggable`; fixed-`loadLb` movements (the starter movements) pass it, and the quick-set's calories come from `CalorieEstimator.caloriesForSet`. Re-adding either needs a wire field AND an input affordance, not just lifting the filter

### …nor present an OLD day's data as today's
the phone pushes only on activation/foreground/mutation, so a watch opened on a morning the phone hasn't been touched holds yesterday's numbers under a "Today" title. `WatchSyncStore.snapshotGeneratedAt` (the already-on-wire `generatedAt`; nil-guards the `.distantPast` an older payload decodes to) drives one notice, shown ONLY once the snapshot predates today — a DAY boundary, matching the `Dates.dayKey` the numbers are folded on. A same-day snapshot gets no row: there's no wrist-side refresh to offer and a permanent timestamp above the hero number is noise at 40mm

### Watch target extra sources
Of those, `LiveSessionState.swift` is currently referenced by the watch only in comments

`WatchLiveSessionView` re-derives elapsed from `LiveSessionSnapshot.startDate` because the wire snapshot has no `profileId`. **Each must stay Foundation-only with no other Domain type** or it drags the rest of Domain onto the wrist — that's why `CalorieEstimator`'s exercise-aware overload lives in `Domain/ExerciseCalories.swift`

### On-wrist workout / heart rate
`HKWorkoutSession` + `HKLiveWorkoutBuilder`. `startWorkout` has exactly ONE caller, `ActivityPickerView.start` in `WatchLiveSessionView.swift` (the Start tap), and `endWorkout` exactly one, `EndSessionButton`; that pairing is the whole of hard rule 4 on the wrist, since `startWorkout` is also the only place watch HealthKit authorization is requested (uncatchable-NSException rule). Additive telemetry: the phone still stores the deterministic MET estimate, and the runner shows the sensor bpm *alongside* it rather than instead of it. Needs `OurFitnessWatch.entitlements` + `WKBackgroundModes: workout-processing` + a HealthKit-enabled watch profile

### Show/hide trackers
`AppStorage "progressStats.\(profileId)"`. Default set = `StatKind.isDefault` (one set for every goal): weight / steps / training volume / resting HR / blood pressure — trackers the app fills itself, plus BP as the one cheap self-measure; BMI (duplicates Weight) and everything needing calipers, a tape or a lab starts hidden. `ProgressTabView.enabledSet(body:markers:)` then re-adds any tracker that already `hasLoggedData`, so shrinking the default never hides a card someone was filling in. A stored CSV always wins.

### Stat detail sheet (chart + entries + log)
ONE sheet for every tracker. Metric-specific bits come in as slots (`headline`, `chartOverride`, `logOverride`, `footer`) plus `validate` / `showsEntries` / `minChartPoints` / `detents`; `StatDetailRow` is the shared label/value row. Weight (wheel picker), Body fat, BMI, and Blood pressure in `ProgressView.swift` are all thin hosts over it — never write another bespoke detail sheet

### Strength progress (estimated max per loaded lift)
only `ExerciseDTO.tracksPerSetWeight` exercises, only sets of 1–`maxReps` (12) reps with a weight; headline = best Epley estimate (`weight × (1 + reps/30)`, an ESTIMATE — copy says so), `gainLb` = vs the best set from before the last 28 days (nil for a newer lift). Rendered by `strengthCard` in `Features/Progress/ProgressView.swift` (top 5 by recency; hidden until a weighted set exists). Fixed-load movements (Lifted Baby etc.) are deliberately NOT included — the load lives on the exercise, not the set, so a carry-weight trend can't be derived; tracking it would need the load stamped on each set (not built). Tests: `StrengthProgressTests`

### Tape measurements (frame size: waist, shoulders, chest, arm, thigh)
ONE code path for all five via `StatKind.tapeIn` (a `WritableKeyPath` into `BodyMetricDTO`); values stored in canonical inches on `BodyMetricDTO.{waistIn,shouldersIn,chestIn,armIn,thighIn}` (+ `BodyMetricModel`), converted at the UI boundary. New StatKind cases are appended last (the enabled set is a persisted CSV). All start hidden (`isDefault` false) and re-appear automatically once logged. The four new columns are optional/additive and shipped WITHOUT a schema version bump (same pattern as earlier optional fields; container opens `AppSchema.current` directly). Upgrade verified on the simulator — see the Oct 2026 validation record

### Weeks ("this week")
Monday-anchored, the app-wide definition. Never `Calendar.current` week components (Sunday-based in the US). `Domain/Movement.swift` still builds its own Monday calendars — migrate it to this helper when touched. Tests: `DatesTests`

### Calorie intake vs activity burn
active-only, step-overlapping sessions excluded). Card `energyBalanceCard` (both modes) in `Features/Progress/ProgressView.swift` → detail `Features/Progress/EnergyBalanceDetailSheet.swift` (Charts: intake bars vs burn line + target rule). Tests: `OurFitnessTests/EnergyBalanceTests.swift`

### Training history (cross-day)
opened from Train and Progress; an exercise row opens `SetHistorySheet` on that day. Tests: `OurFitnessTests/TrainingHistoryTests.swift`

### Latest value of a health marker
via the single `latestMarkerValue` helper in `ProgressView.swift`. Don't re-filter/sort markers inline

### App tab layout
same for every goal: Today / Meals / Train / Progress. `WorkoutsView` is the same for everyone (live sessions · `ExercisesCard` · optional Pilates / Yoga / Stretching sections · suggestions). Today is a **read-only status board**: move (steps on top) · macro rings · today-vs-yesterday insights (`Domain/DayInsights.swift` → `Features/Today/DayInsightsCard.swift`; ≤3 rules-based observations with a next step, no claim off a day with no data; tests `DayInsightsTests`) · water, and a log list with no tap target. One surface per job — logging food happens on Meals, nowhere else

### Units (metric ↔ imperial)
canonical storage IMPERIAL; convert only at UI boundary

### Sync current weight
called after progress log, HK sync, TodayView task

### Fasting glucose from Health
only samples HealthKit marks pre-meal (`HKMetadataKeyBloodGlucoseMealTime` == `.preprandial`) become `.fastingGlucose`; post-meal and metadata-less samples are **dropped**, because a normal post-meal 150 filed as fasting trips `HealthRanges` ≥126 → high (ADA diabetes cut-point). Storing them needs a new non-fasting glucose `HealthMarkerKind`

### Weekly Health totals
Sunday-first in the US locale, which desyncs the StepsCard week cells from every other weekly figure

### Button variants (5 total)
never add a 6th. Decorative layers (`GlareSweep`) stay `.accessibilityHidden` — the off-screen glare once inflated every primary button's accessibility frame, so VoiceOver boxes and UI-test taps landed beside the button. Primary labels render uppercased (`textCase`), so UI tests match labels case-insensitively

### Circular progress
never inline `Circle().trim`

### ⓘ info-sheet chrome
Nutrition goals does) + `InfoSection`, `InfoBody`, `InfoFootnote`, `InfoRow(label:detail:emphasis:)`, `InfoCalcRow(label:detail:labelWraps:)`, `InfoMetricRow`, `InfoHeroStat`, `Bullet(_:marker:)`. Carries chrome only — all copy/numbers/citations stay at the call site. Never re-roll a private `infoSection`/`calcRow`/`bullet` helper

### Progress-fill replay (sweep from 0 on appear)
resets to 0 on scroll-out, springs to full on re-entry. Used by `ProgressBar` + `MacroQuadGrid` (`pct * reveal`)

### Toast
`show(_:for:)` for a `Toast`, `show(_:accent:for:)` for an `EncouragementMessage` (every encouragement wrapper is a one-liner over it). `show` fires the outcome haptic itself: never call `Haptics.*` right before it

### Schema migration
current SchemaV7. Additive (new optional field / entity) = automatic. Structural = `.custom` stage.

### Exercise shape (which controls a row gets)
Isometric → hold timer. Read these predicates; never branch on goal

### Food parser (NL → macros)
Keystroke = curated only; submit = full USDA DB. Tests: `FoodParserTests`

### Can a logged food supply sodium / added sugar / sat fat?
`CommonFoods` (5 nutrients), the USDA SQLite table (5 columns), `MealIngredient.from`, and every manual-macro form leave them 0. `MacroBudget.capCoverage` reads provenance off the values: a positive figure can only be label-sourced, and one positive vouches for the other two on that entry

### Training volume
Tests: `TrainingHistoryTests`

### BMI / body-fat thresholds
The Progress sheets read labels from them (`bmiIsHealthy`, the probe-value range tables); never restate 18.5 / 25 or a body-fat band in a view

### Goal-picker wheel sheet
Fires the Save success haptic itself
