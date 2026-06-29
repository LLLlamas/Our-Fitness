# Health-Tracking UI & Readability Refresh — Implementation Plan

> **Status:** Spec for a future implementation agent. Researched and scoped 2026-06-01.
> All design decisions below were confirmed with the product owner. Where a value
> is an assumption rather than a confirmed decision it is tagged **[ASSUMED]** —
> verify before shipping but proceed with the default if unanswered.

This document is self-contained: it states the goal, the confirmed behavior, the
exact files to touch, implementation notes, the architectural guardrails from
`CLAUDE.md` that each change must respect, and acceptance criteria. Read
`CLAUDE.md` first — every rule there still applies.

## Implementation status (2026-06-01)

All seven workstreams are **implemented** on `claude/health-tracking-ui-docs-r4FUH`.
Notable realizations / deviations from the original spec:

- **W1:** added a `theme.dim2` token (Services/Theme.swift) and switched the Settings
  card sub-labels + profile rows to it — the centralized contrast fix.
- **W2/W3:** one combined `Components/CalorieInfoSheet.swift` (+ reusable
  `CalorieInfoButton`) surfaced on the Move card, the Today food-log header, and the
  Train header. The Move card's always-on blurb moved into the sheet.
- **W4:** `HealthKitService.latestHeartRateSample()` returns the sample date;
  `Domain/Freshness.swift` (pure, injectable `now`) renders an absolute "as of …"
  label, suppressed within 2 min. MoveCard re-reads on appear + pull-to-refresh via a
  `refreshTick`. Note: Progress markers/body metrics are stored at **day** granularity
  (no sample time), so the freshness label applies to the live HR read only.
- **W5:** glasses are drawn **in code** (`Components/GlassIcon.swift`, tappable/tintable
  `Shape`s) rather than asset-catalog PDFs — cleaner, scalable, theme-tinted, no binary
  assets. Sizes 8/12/16/32. Custom presets persist in SwiftData
  (`WaterCupPresetModel`, **SchemaV5**) with add/delete UI. Water added to Progress as
  `StatKind.water` (today-vs-goal + 7-day avg) with a read-only detail sheet.
- **W6:** signup weight seeded as the first BodyMetric in `Repos.createProfile`;
  `syncFromHealth` now also fires immediately after the Connect flow (Today + Settings +
  Progress); Progress shows a "Connect Apple Health" prompt when access isn't granted.
- Domain tests added: `OurFitnessTests/FreshnessTests.swift`, `WaterPresetTests.swift`.

The sections below are the original spec, retained for context.

## Global guardrails (apply to every workstream)

- `Domain/` is pure Swift — no `SwiftUI`, no `SwiftData`. Formatting/aggregation
  logic that belongs in Domain must stay UI-free.
- `Features/` never opens the SwiftData container directly. Use repositories or a
  **predicate-scoped** `@Query` (`init(profile:)` building `#Predicate { $0.userId == uid }`).
  Never `@Query` everything and `.filter` client-side.
- **HealthKit only through `Services/HealthKitService.swift`.** ⚠️ **Never call
  `requestAuthorization` from `.task`/`.onAppear`/pull-to-refresh** — it can raise
  an uncatchable Obj-C exception → `SIGABRT` (build 37 incident). Auth requests
  belong only in the explicit user-initiated Connect flow (onboarding / Settings).
  **Reads** (`steps()`, `latestQuantity`, `activeEnergy()`, `latestHeartRate()`,
  `syncFromHealth`) work without re-requesting and are safe to run on launch/refresh.
- Every `Button` uses `.tactile(...)`. ⓘ info buttons use `.tactile(.ghost)`, open
  a `.sheet` with `.presentationDetents([.medium])` and `.presentationBackground(theme.bg)` —
  **never `.popover`**. Don't add a 6th `TactileButtonStyle` variant.
- User-facing calorie copy says **"cal"**, never **"kcal"** (the info sheet is the
  one place we explain the kcal equivalence — that's allowed inside the sheet body).
- Don't inline `Circle().trim` — reuse `Components/ProgressRing.swift`. Don't inline
  card chrome — reuse `Card` / `PressableCard`. Corner radii per the table in `CLAUDE.md`.
- Don't double-haptic: `.tactile()` already fires on press.
- `.swift` filenames in the target must be unique; `@Model` classes live only in
  `Data/PersistenceModels.swift`.

---

## Workstream 1 — Settings & Mode-Switch readability

**Problem.** In the screenshot the Settings cards ("Connected to Apple Health",
"Circuit") look washed-out gray with low-contrast text. Root cause: when the
mode-switch sheet (`ModeSwitchSheet`, themed to the **destination** mode) is
presented, iOS dims the Settings view behind it. In Reset mode the Settings is
the light palette (white `theme.card` on cream `theme.bg`, sub-labels in the muted
`theme.dim` ≈ `#7A7368`), and the system dim turns those muted labels nearly
illegible.

**Decision (confirmed):** Keep the destination-preview theming of the sheet — just
**fix the font/text contrast so labels read clearly in BOTH modes**, including when
dimmed behind a sheet. This is a targeted contrast fix, not a re-theme or restyle.

**Files to touch:**
- `Features/Settings/SettingsView.swift`
  - Apple Health card (≈ lines 23–40): primary label already `theme.text`; the
    **sub-label** ("Tap to manage per-metric toggles…" / "Tap to grant access")
    uses `.foregroundStyle(theme.dim)` → raise contrast.
  - Mode card (≈ lines 72–87): same — sub-label "Tap to switch to …" uses `theme.dim`.
  - `ModeSwitchSheet.compareRow` (≈ lines 175–195): the *from* value and unit use
    `theme.dim`; ensure they stay legible against `theme.card` in both themes.
- `Services/Theme.swift` — **preferred fix:** introduce a single higher-contrast
  secondary-text token (e.g. `dim2` / `subtle`) that sits between `dim` and `text`,
  defined per mode, and use it for these card sub-labels. This keeps the change
  centralized and reusable rather than sprinkling literal colors. **[ASSUMED]** token
  name `dim2`; pick values with ≥ 4.5:1 contrast on `theme.card` in each mode
  (Build card `#131313`, Circuit card `#FFFFFF`).

**Implementation notes:**
- Do **not** fight the system dimming with opacity hacks; the confirmed approach is
  contrast of the text itself. Bumping the sub-label color from `dim` to the new
  `dim2` (or to `theme.text` for the most important line) restores legibility even
  when the layer is dimmed.
- Keep primary labels at `theme.text`. Keep accent glyphs (`checkmark.circle.fill`,
  `arrow.left.arrow.right`) at `theme.accent`.
- Verify both directions: Build→Circuit (dark Settings, light sheet) and
  Circuit→Build (light Settings, dark sheet).

**Acceptance:** In both modes, with the switch sheet open, every label on the Apple
Health card, the Mode card, and the compare rows is comfortably readable (no muddy
gray-on-gray). No new button variant; no popover.

---

## Workstream 2 — Explain "cal" (shared Calorie info sheet)

**Problem.** Most users don't know "cal" = kcal. We show "cal" in ~18 places but
only the nutrition macro grid explains it (`MacroInfoSheet` in
`Components/MacroQuadGrid.swift`, which already carries good copy: *"Displayed in
calories (cal) — the everyday unit on food labels. 1 cal here = 1 kilocalorie
(kcal)…"*). Workout and Move-card calorie figures have no explanation.

**Decision (confirmed):** A **shared ⓘ "what's a calorie" sheet**, surfaced via small
ⓘ buttons on the **key calorie surfaces**: the Move card, Today's food-total, and the
workout calorie figures. Consistent with the existing nutrition info pattern.

**Files to touch:**
- **New** `Components/CalorieInfoSheet.swift` — a reusable sheet (`.presentationDetents([.medium])`,
  `.presentationBackground(theme.bg)`, `.themed(theme.mode)`), modeled on
  `MacroInfoSheet`. Body explains: cal = everyday food/energy calories, 1 cal = 1
  kcal (the scientific unit), and (briefly) that burn figures are estimates. Plain
  language — no jargon up front.
- Extract/share the existing calorie copy so nutrition and the new sheet don't drift.
  Either move the calorie string into `CalorieInfoSheet` and have `MacroInfoSheet`'s
  calorie case present it, or keep both but source the text from one constant.
- Add a small `.tactile(.ghost)` ⓘ button (`Image(systemName: "info.circle")`,
  ~10–11pt) next to the calorie readouts in:
  - `Features/Today/MoveCard.swift` (combine with Workstream 3's ⓘ — see note below).
  - `Features/Today/TodayView.swift` (the food-log "… cal" total, ≈ line 179) — one
    ⓘ on the section/total, not per row.
  - `Features/Workouts/WorkoutsView.swift` (rep/hold cells, ≈ lines 250/274) and/or
    the exercise card header — a single ⓘ per card, not per cell, to avoid clutter.
  - `Features/Workouts/Circuit/StepsCardioCard.swift`, `PilatesCard.swift`,
    `BabyExercisesCard.swift` — one ⓘ near the "~N cal" summary each. **[ASSUMED]**
    one ⓘ per card is enough; don't stamp every figure.

**Implementation notes:**
- Reuse the existing `MacroChip`/info-button visual weight so it doesn't shout.
- Keep "cal" in all the inline labels; the word "kcal" appears only inside the sheet.

**Acceptance:** Tapping any ⓘ near a calorie figure opens the same clear explanation;
copy is sourced from one place; no `.popover`; medium detent.

---

## Workstream 3 — Explain MET + move the Move-card blurb behind ⓘ

**Problem.** `MoveCard` shows an always-visible paragraph: *"Apple Health measures
active energy from your Watch/iPhone. The MET estimate is our own science-based
calculation (MET × weight × time) from your steps and logged training."* (≈ lines
77–79). MET itself is never explained, and the always-on blurb is heavy.

**Decision (confirmed):** Replace the always-visible blurb with a tappable **ⓘ** that
opens a sheet explaining **what MET is** and **how we turn it into calories burned
using the user's own info** (body weight from their profile × activity time), plus
the Apple-Health-vs-MET distinction (the current blurb goes *inside* the sheet).

**Files to touch:**
- `Features/Today/MoveCard.swift` — remove the inline `Text(...)` blurb (≈ 77–79),
  add a `.tactile(.ghost)` ⓘ in the card header (near "APPLE HEALTH" / the MET row).
- Add a **"How we estimate burn (MET)"** section to `Components/CalorieInfoSheet.swift`
  (CONFIRMED: one combined sheet, not a separate file). Content:
  - Plain-language MET definition ("MET = a multiple of resting energy; walking ≈
    4.3 METs means ~4× the energy of sitting still").
  - The formula in friendly terms: **calories ≈ MET × your body weight × time**
    (we use your profile weight; heavier bodies burn more for the same activity).
  - Why two numbers: Apple Health's active energy is **measured** by your
    Watch/iPhone for the whole day; our MET estimate is **calculated** from your
    steps + logged training so a science-based figure sits beside the measured one.
  - Cite that METs come from the Ainsworth 2011 Compendium (keep it light).

**Implementation notes (CONFIRMED — one combined sheet):**
- Use a **single shared sheet** with two short sections — "What's a calorie?"
  (Workstream 2) and "How we estimate burn (MET)". The Move card's one ⓘ opens it;
  the calorie-only surfaces (food total, workout figures) open the same sheet. Build
  this as `Components/CalorieInfoSheet.swift` with both sections rather than a
  separate `MetInfoSheet.swift`.
- The MET math facts to surface (do not invent kcal/rep): formula `kcal = MET ×
  bodyWeightKg × hours`; sources/METs are tabulated in `CLAUDE.md` ("Calorie math")
  and `Domain/CalorieEstimator.swift` / `Domain/ExerciseInfo.swift`.

**Acceptance:** Move card no longer shows the wall of text; an ⓘ opens a sheet that
explains MET and the weight-based calorie calculation in plain language; the
old blurb content survives inside the sheet.

---

## Workstream 4 — Heart rate freshness + timestamps on retrieved Health data

**Problem & answer to the product question.** Heart rate is **not** live. `MoveCard`
calls `HealthKitService.latestHeartRate()` once on load — a one-shot `HKSampleQuery`
for the single most recent sample. (Steps have a live `HKObserverQuery` +
background delivery; HR does not. Also, the Watch only feeds Health new HR samples
periodically — true real-time HR exists only during an active workout session, which
is out of scope.)

**Decision (confirmed):** Don't chase real-time. Instead, **re-read on natural
moments and show an accurate timestamp** for any retrieved point-in-time reading,
while **reducing redundancy** (don't show a timestamp where it's meaningless, and
don't re-fetch needlessly).

**Files to touch:**
- `Services/HealthKitService.swift`
  - `latestHeartRate()` (≈ 238–242) currently drops the sample date. Add a variant
    that returns the value **with its `endDate`** (the private `latestQuantity`
    already returns `(value, date)` — surface it). **[ASSUMED]** add
    `latestHeartRateSample() async -> (bpm: Int, date: Date)?` and keep the old
    method or refactor callers.
  - Do the same for the other "latest sample" reads used on Progress (body fat,
    waist, BP, glucose, weight) so each can carry its true sample timestamp.
- `Features/Today/MoveCard.swift`
  - Re-read HR on Today's `.task`/appear **and** pull-to-refresh (reads only — never
    re-auth). Display freshness next to the bpm, e.g. "as of 1:48 PM" or a relative
    "12m ago".
- **New** small helper for freshness labels (keep formatting in the view layer or a
  tiny pure formatter in `Domain/` that takes `now:` injectable — **see CI rule:
  never bare `Date()` in time-sensitive Domain code; thread `now`**). A relative
  formatter is fine via `Text(date, style: .relative)` or `RelativeDateTimeFormatter`.

**"Reduce redundancy" rules (confirmed intent):**
- Show a timestamp only for **point-in-time** readings that have a real sample date:
  latest HR, latest body fat, waist, BP, glucose, weight.
- Do **NOT** attach a timestamp to **whole-day cumulative** figures — steps and Apple
  Health active energy are day sums with no single sample time; a timestamp there is
  noise.
- Suppress the label when the reading is essentially "now" (CONFIRMED: within the
  last **2 minutes**) to avoid clutter; show it once it's meaningfully stale.
- Time format is **absolute** (CONFIRMED), e.g. "as of 1:48 PM" via a localized
  short time style — not relative ("12m ago").
- Don't re-fetch on every render — fetch on appear + explicit refresh only.

**Acceptance:** HR refreshes on appear/refresh and shows an honest "as of …";
point-in-time Progress values show their sample time; day-sum metrics (steps, active
energy) show no timestamp; no auth request fires from any of these paths.

---

## Workstream 5 — Water: glasses, custom sizes, and a Progress tracker

### 5a. Replace coffee-cup icons with glasses (keep bottle)

**Current presets** (`Domain/Water.swift`, ≈ 21–26) use coffee-shop SF Symbols:
`cup.and.saucer`, `cup.and.saucer.fill`, `takeoutbag.and.cup.and.straw.fill`, and
`waterbottle.fill` (Owala, 32 oz).

**Decision (confirmed):** Use **custom-drawn glass assets** for Small / Medium /
Large (visibly different glass sizes), **keep a bottle** option (SF Symbol
`waterbottle.fill` is acceptable for the bottle, or a custom bottle asset to match),
and add a custom-size feature (5b).

**Files to touch:**
- Add custom glass vector assets to `Assets.xcassets` (e.g. `glass.small`,
  `glass.medium`, `glass.large`) — template/tintable PDFs so they take `theme`
  accent/text tint like SF Symbols. Three visibly distinct fill levels/heights.
- `Domain/Water.swift` — the `CupPreset.symbol` field currently holds an SF Symbol
  name. Decide how to distinguish **asset images** from **SF Symbols**:
  - **[ASSUMED]** add a `kind`/`isAsset` flag (or a small `enum IconRef { case
    sfSymbol(String); case asset(String) }`) to `CupPreset` so the view can render
    either `Image(systemName:)` or `Image(_:)`. Keep `Domain` pure (no SwiftUI) — the
    enum is just data; the view decides which `Image` initializer to call.
  - Update the default presets to **fl-oz 8 / 12 / 16 / 32** (CONFIRMED):
    8 = small glass, 12 = medium glass, 16 = large glass, 32 = bottle. Small/Medium/
    Large use the glass assets; bottle keeps `waterbottle.fill` (or a matching asset).
- `Features/Today/WaterCard.swift` (≈ 89–107) — render asset vs symbol per the new
  `IconRef`; keep the same button layout, accessibility labels, haptics.

### 5b. "Add a size" — custom presets

**Decision (confirmed):** Tapping **"Add a size"** lets the user specify **a name +
fl-oz amount + an icon** (pick from the glass/bottle set). Saved as a reusable preset.

**Persistence (CONFIRMED — SwiftData, like reps/steps/meals):** Custom presets are
**persisted in SwiftData**, the same way logged data lives in `@Model` classes — NOT
AppStorage. This means a **new entity** and therefore a new schema version.

**Files to touch:**
- `Data/PersistenceModels.swift` — add `WaterCupPresetModel` (a `@Model`), per-profile
  scoped (`userId`/`profileId: UUID`), fields: `id: UUID`, `name: String`,
  `flOz: Double`, `iconName: String`, `isAsset: Bool`, `sortOrder: Int`,
  `createdAt: Date`. Built-in S/M/L/bottle stay as code constants; only **user-created**
  presets are persisted here (mirrors how exercises/meals are user data while the
  food *library* is code).
- `Data/Schema.swift` — define **`SchemaV5`** listing all current models **plus**
  `WaterCupPresetModel`, and bump `AppSchema.current` to it. This is an **additive**
  change (new entity) → rides SwiftData's **automatic** migration with **NO staged
  `MigrationPlan`** (same pattern as `WaterEntryModel` in SchemaV4). ⚠️ Do **not**
  write a lightweight/staged stage — those threw uncatchable exceptions historically.
  Test an upgrade-in-place on a device with existing data before shipping.
- `Domain/Models.swift` — add a matching value-type `WaterCupPresetDTO` with a
  `snapshot` adapter, consistent with the other DTO/@Model pairs. Keep `Domain` pure.
- `Domain/Water.swift` — `CupPreset` stays the in-memory render model; the full preset
  list the card shows = built-in defaults (8/12/16/32) + the user's persisted custom
  presets mapped into `CupPreset`. Aggregation unchanged (entries are just `flOz`).
- `Data/Repositories/Repositories.swift` — add `Repos.addWaterPreset(...)`,
  `listWaterPresets(profileId:)`, `deleteWaterPreset(_:)` mirroring the existing
  `addWater`/`listWater`/`deleteWater` surface.
- `Features/Today/WaterCard.swift` — load custom presets via a **predicate-scoped
  `@Query`** of `WaterCupPresetModel` (build `#Predicate { $0.userId == uid }` in
  `init(profile:)`, per the scoping rule). Add an "Add size" affordance (a trailing
  `+` pill) opening a small sheet/form: name field, fl-oz field (Done keyboard
  toolbar per the numeric-keyboard rule), icon picker (glasses + bottle). On save →
  `Repos.addWaterPreset` + toast. Allow deleting custom presets (swipe/long-press →
  `Repos.deleteWaterPreset` + toast).
  - **[ASSUMED]** with custom sizes the row can overflow — use a horizontally
    scrollable preset row (built-ins first, then customs by `sortOrder`). Confirm if
    you'd rather have a "manage sizes" sheet; default to the scrollable row.

**Acceptance:** S/M/L show distinct glass icons; bottle remains; users can add a
named custom size with an icon that persists per profile and is tappable like a
built-in preset; numeric entry has a Done toolbar; every add fires a toast.

### 5c. Water tracker on the Progress tab

**Decision (confirmed):** Add water to the **Progress** tab showing **both** the
7-day daily average (like the steps tracker) **and** today-vs-goal.

**Files to touch:**
- `Domain/Models.swift` — add a `StatKind.water` case. ⚠️ Adding a `StatKind`
  requires updating **every exhaustive switch** over it:
  - `Features/Progress/ProgressView.swift` → `displayValue` (render avg + today/goal)
    and `isRelevant(for:)` (decide default visibility — **[ASSUMED]** relevant in
    both modes, like steps).
  - `Features/Progress/EditTrackersSheet.swift` — appears in the toggle list with the
    right per-mode default subtitle.
  - Check for any other `switch` over `StatKind` (grep) — make them exhaustive.
  - `StatKind` is not a `HealthMarkerKind`, so `Domain/HealthRanges.swift`'s
    `HealthMarkerKind` switches do **not** need a water case — but confirm water has
    no range/status expectations wired through there.
- The Progress card pulls water via a **predicate-scoped `@Query`** of
  `WaterEntryModel` (mirror `WaterCard`), then `Water.average(entries, days: 7)` and
  `Water.total(entries, on: todayKey)` vs the per-profile goal
  (`"waterGoalFlOz.\(profileId)"`). Show today-vs-goal with `Components/ProgressRing`
  (don't inline `Circle().trim`).
- Per-profile `@Query` scoping rule applies (build the predicate from the profile id).

**Acceptance:** Progress shows a water tracker (toggleable in EditTrackersSheet) with
both 7-day average and today-vs-goal; values match the Today water card; scoping is
predicate-level.

---

## Workstream 6 — Auto-populate Progress cards (signup + HealthKit + empty states)

All four sub-items were confirmed.

### 6a. Seed weight from signup

**Problem.** Signup captures `weightLb`, but it only seeds the weight **picker
default** — the weight log starts empty, so the Weight and BMI cards show nothing on
day one until a manual log.

**Decision (confirmed):** On profile creation, **write the signup weight as the first
`BodyMetric` entry** so Weight + BMI populate immediately.

**Files to touch:**
- `Data/Repositories/Repositories.swift` → `createProfile(...)`: after inserting the
  profile, `upsertBodyMetric(ctx, userId: profile.id, day: Dates.dayKey(), weightLb:
  weightLb)` (only if `weightLb > 0`). Reuse the existing dedup upsert so a later
  HealthKit/manual weight for the same day fills/wins per the existing nil-only rule.
- Verify `Features/Progress/ProgressView.swift` weight/BMI now read this seeded row
  (BMI = `BodyComposition.bmi(weightLb:heightIn:)` with `profile.heightIn`).
- **[ASSUMED]** tag the seeded entry's source as signup-derived if a `source`/`notes`
  field is available, so it's distinguishable from a manual log. Not required.

### 6b. Pull all available HealthKit on first launch / connect

**Decision (confirmed):** Proactively run the full `syncFromHealth` (body fat, waist,
resting HR, BP, glucose; steps + weight via their existing paths) at first
launch/connect so cards fill where Health has data.

**Files to touch / notes:**
- `Services/HealthKitService.syncFromHealth(profileId:ctx:)` already covers these and
  dedupes per (day, kind)/(userId, day). It's currently called from `TodayView`'s
  task/refresh when granted.
- ⚠️ **Crash-safety:** `syncFromHealth` is **reads only** — safe on launch. Do **NOT**
  add a `requestAuthorization` to any launch path. The *authorization* still happens
  only in the explicit Connect flow (onboarding / Settings). After the user grants in
  that flow, kick `syncFromHealth` once there too so cards fill immediately rather
  than waiting for the next Today visit.
- Reads return nothing if the user never granted or has no data — that's fine; 6d
  covers the empty presentation. **LDL/HDL/total cholesterol/A1c are not in Apple
  Health** (lab/FHIR only) — they stay manual; don't try to sync them.

### 6c. (covered) — water on Progress is Workstream 5c.

### 6d. Clear empty / "connect Health" states

**Decision (confirmed):** For cards with no data yet, show an inviting empty state or
a connect-Health prompt instead of a blank/zero.

**Files to touch:**
- `Features/Progress/ProgressView.swift` — per-tracker empty rendering:
  - If the metric **can** come from Health and access **isn't** granted → a compact
    "Connect Apple Health" prompt that routes to the Connect flow (Settings/onboarding
    path — user-initiated, so auth is safe there).
  - If access is granted but there's **no data** (e.g. body fat with no smart scale,
    or lab-only markers) → a short "No data yet — log your first reading" with the
    existing add affordance, and for lab-only markers make clear they're manual.
  - Keep the all-trackers-hidden message as-is ("No trackers shown. Tap the sliders…").
- Reuse `Components/Banner` / `Card` chrome and `.tactile` buttons; don't invent new
  chrome.

**Acceptance:** New install with signup weight shows Weight + BMI immediately; after
granting Health, available markers fill without revisiting Today; cards with no data
show a helpful prompt (connect vs log-first vs manual-only), never a bare blank/0.

---

## Suggested implementation order

1. **W1** (contrast token + Settings labels) — small, isolated, high visible win.
2. **W2 + W3** (shared Calorie/MET info sheet + ⓘ wiring) — do together; they share a sheet.
3. **W4** (HR re-read + timestamps + freshness helper).
4. **W6a/6b/6d** (seed weight, proactive sync, empty states) — Progress data plumbing.
5. **W5** (water glasses assets, custom presets, Progress water tracker) — largest;
   asset work + a new `StatKind` touching several exhaustive switches.

## Cross-cutting acceptance / "do not regress"

- App compiles via the Mac-less `compile.yml` path; no Mac-only steps added.
- `OurFitnessTests` stays hostless; any new Domain logic (freshness formatter, water
  preset decoding, water aggregation tweaks) is pure and unit-tested with an
  **injected `now`** (never bare `Date()` in time-sensitive tests — pin to a mid-week
  date like `2026-05-27T12:00:00Z`).
- Custom water presets are a **new `@Model` → `SchemaV5`** (CONFIRMED), additive, no
  staged `MigrationPlan` (automatic migration, same as `WaterEntryModel` in V4). Test
  upgrade-in-place on a device with existing data before shipping.
- `project.yml` is the source of truth; don't add `info:`/`entitlements:` blocks to
  the OurFitness target. New asset catalog entries are fine.
- Every meaningful mutation fires a toast; numeric inputs get a Done keyboard toolbar;
  ⓘ sheets use medium detents + `.presentationBackground(theme.bg)`; no `.popover`;
  no 6th button variant.

## Confirmed decisions (2026-06-01)

1. **One combined info sheet** (calorie + MET sections), reachable from the Move
   card's single ⓘ and the calorie-only surfaces. ✅
2. **Custom water presets persist in SwiftData** (like reps/steps/meals) → new
   `WaterCupPresetModel` + `SchemaV5` (additive). ✅
3. **Absolute** timestamps ("as of 1:48 PM"); freshness label suppressed within the
   last **2 minutes**. ✅
4. Water preset fl-oz sizes: **8 / 12 / 16 / 32**. ✅

## Remaining minor items (defaults assumed if silent)

1. **Secondary-text token name/values** for the contrast fix (`dim2`?) — confirm the
   exact colors meet ≥ 4.5:1 contrast in both palettes.
2. **Water preset row layout** once custom sizes exist: horizontally scrollable row
   (default) vs a "manage sizes" sheet.
