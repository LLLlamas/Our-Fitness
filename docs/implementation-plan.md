# Our-Fitness — Implementation Plan (Round 1)

> Archived planning note. Current source of truth is [../CLAUDE.md](../CLAUDE.md) plus [../AGENTS.md](../AGENTS.md). Several items below have shipped, moved, or changed names; do not treat the checkboxes as current backlog.

Distilled from the 2026-05-26 planning conversation. This is the work to land before the daily loop is "solid enough to live in." Numbered phases run roughly in order; items within a phase can be parallel.

---

## 0. Decisions locked in this round

| Topic | Decision |
|---|---|
| Profiles | Two fixed profiles (Build / Circuit). No add-button, no third user. Both profiles always exist in the shared store; either device can view either profile via a header switcher. |
| Onboarding | No "claim a slot" gate. Both seeded on first launch. User flips via Settings / header. |
| HealthKit | Wired into onboarding step + a "Connect Apple Health" CTA on Today if not yet granted. Reads steps, weight, RHR, active energy + Apple Watch–originated steps. |
| Caps (Circuit) | Each cap (sodium / sugar / sat-fat / fiber) gets an `info.circle` button → sheet with plain-English explanation + medical reasoning. |
| Custom food entry | Name + quantity. Lookup pipeline: **USDA FoodData Central API → Apple Intelligence estimate → manual label-photo OCR fallback**. User confirms before save. |
| AI provider | **Apple Intelligence (FoundationModels framework, iOS 18.1+)** on-device. No Anthropic tokens. No network. Free. |
| Circuit Train tab | Steps & cardio + Pilates only. **Strength removed entirely.** Goal: lower LDL, raise HDL, BP control, habit formation. |
| Build Train tab | Strength + mobility track. Mobility surfaces three ways: daily card on Today, warm-up block prepended to lift days, and a standalone Mobility day in the program. |
| Progress modals | Pilates summary, Steps deep-dive, Health markers (Circuit-critical). Weight + PR modals deferred. |

---

## 1. HealthKit wiring (blocking — nothing works without this)

**Current state:** `OurFitnessService/HealthKitService.swift` has `requestAuth()` but nothing calls it. Entitlement + Info.plist strings are already in place.

- [ ] Onboarding adds a **"Connect Apple Health"** step. Tap → `HealthKitService.requestAuth()` → native iOS sheet → store result (`granted: Bool`) on `Profile`.
- [ ] Today view: if `!profile.healthGranted`, render a banner card "Connect Apple Health to track steps automatically" → same call.
- [ ] `HKObserverQuery` registered at launch for `stepCount`. On fire → `UPSERT` `StepCount` row for today.
- [ ] Apple Watch steps come for free once authorization is granted — no separate watch target in v1. Document this in `README.md`.
- [ ] Add `activeEnergyBurned` + `appleExerciseTime` to the read set (Circuit cares about cardio minutes).
- [ ] Settings screen exposes "Apple Health permissions" → opens iOS Settings deep link if user wants to change.

**Files:** `Services/HealthKitService.swift`, `Features/Onboarding/*`, `Features/Today/TodayView.swift`, `App/RootView.swift`, `Domain/Models.swift` (add `healthGranted: Bool` to `Profile`).

---

## 2. Profile model — fixed two, switchable view

- [ ] Remove any "create profile" flow. Seed both `Build` and `Circuit` profiles on first launch (`SeedProfiles.swift`, idempotent).
- [ ] Add `@AppStorage("activeProfileID")` to RootView; defaults to Build on one device, Circuit on the other (manually picked on first launch).
- [ ] Header avatar switcher: tap top-left avatar → small sheet with both profiles → switch. No password, no auth — household trust.
- [ ] All `@Query` filters that currently take a profile keep working; just the active profile flips.

**Files:** `Data/Seed/SeedProfiles.swift` (new), `App/RootView.swift`, `Components/ProfileSwitcher.swift` (new).

---

## 3. Caps — info tooltips (Circuit)

- [ ] `Components/CapBar.swift` (new or extend existing `ProgressBar`) — same visual, with an `info.circle` button trailing the label.
- [ ] Tap → `.sheet` with a `CapExplanation` view: plain-English **why this cap exists** + medical reasoning + source (AHA, USDA, etc.).
- [ ] Copy lives in `Domain/CapExplanations.swift` — one struct per cap (sodium, added sugar, sat fat, fiber). Pure data, easy to revise without touching views.

**Example copy (sodium):**
> **Sodium ≤ 1,500 mg/day** — the American Heart Association's recommended cap for adults with elevated BP or a family history of heart disease. Most Americans hit this in a single restaurant meal. Lowering sodium directly lowers systolic BP by 5–6 mmHg on average — meaningful for cholesterol/heart-risk profile.

**Decision:** caps render on `TodayView` next to the live totals (the only place the gram counts mean anything in real time); `NutritionView` stays the library browser only.

**Files:** `Components/CapBar.swift`, `Components/CapExplanationView.swift`, `Domain/CapExplanations.swift`, `Features/Today/TodayView.swift`.

---

## 4. Custom food entry (name + quantity → full macros)

Pipeline: user types name + quantity → app tries lookups in order, surfaces confidence, lets user confirm/edit.

- [ ] **USDA FoodData Central** integration. `Services/USDAClient.swift`. Free public API, no key needed at our volume (1000 req/hr unkeyed). Endpoint: `api.nal.usda.gov/fdc/v1/foods/search`. Pick top match by `dataType: ["Foundation", "SR Legacy"]` (most accurate, not branded user-submitted).
- [ ] **Apple Intelligence fallback** when USDA returns nothing or low confidence. `Services/AIEstimator.swift` wraps `FoundationModels` framework — structured prompt: "estimate macros for `<quantity> <name>`" → returns JSON `{calories, protein, carbs, fat, sodium, fiber, sugar}`.
- [ ] **Label-photo OCR** as opt-in third path. `Services/LabelScanner.swift` — `VNRecognizeTextRequest` on captured image → field-by-field extraction → user confirms.
- [ ] All paths land on the same **Confirm Food** sheet: editable macros, source badge (USDA / Estimate / Label), Save.
- [ ] Saved custom foods go into the same `Food` store, tagged `source: .userCustom`, scored against the active mode's caps automatically.

**Files:** `Services/USDAClient.swift`, `Services/AIEstimator.swift`, `Services/LabelScanner.swift` (later), `Features/Nutrition/AddCustomFoodFlow.swift`, `Data/PersistenceModels.swift` (add `source` enum to `Food`).

**Notes:**
- USDA returns per-100g — convert to user's quantity before display.
- AI estimates flagged visually so user knows to double-check.
- Network failures (USDA down) → silently degrade to AI estimate, no error toast.

---

## 5. Circuit Train tab — full rewrite

Currently seeds DB bench, DB row, etc. **Strip all strength from Circuit.**

- [ ] `SeedExercises.swift` — gate strength exercises behind `availableForMode: [.build]`.
- [ ] `Features/Workouts/WorkoutsView.swift` — when `profile.mode == .reset`, render at top a **three-ring "Movement Minutes" summary** (Steps / Pilates / Cardio active-energy), then **two stacked cards** below:
  1. **Steps & Cardio** card (primary, large)
  2. **Pilates** card
- [ ] **Steps & Cardio card** content:
  - Big progress ring → today's steps / goal (10,000 default)
  - Milestone toasts at 3k / 5k / 8k / 10k (via `ToastCenter`)
  - "Ahead/behind yesterday" line ("+1,247 vs this time yesterday") computed from intraday HealthKit samples
  - Weekly trend strip — 7-day mini-bars, last 7 days
  - Tap → Steps deep-dive modal (see §7)
  - Active energy + exercise minutes secondary stats
- [ ] **Pilates card** content:
  - "Log Pilates" PressableCard → modal: duration slider + focus-area chips (Core, Lower Back, Hips, Full Body, Flexibility) + optional notes
  - Today/yesterday sessions strip; older sessions live in Progress → Training history
  - Weekly frequency vs goal (default 3x/wk)
- [ ] Habit-building: weekly streak indicator on each card. Persistent banner if she hits a 4-week+ streak. No streak-shame on breaks (per CLAUDE.md).

**Files:** `Features/Workouts/WorkoutsView.swift`, `Features/Workouts/Circuit/StepsCardioCard.swift` (new), `Features/Workouts/Circuit/PilatesCard.swift` (new), `Domain/Models.swift` (`PilatesSession` entity + `FocusArea` enum), `Data/PersistenceModels.swift` (matching `@Model`).

---

## 6. Build Train tab — add mobility / lower-back track

Mobility surfaces **three ways simultaneously** (user picked all three options):

- [ ] **Daily mobility card on Today** (Build only) — 5–10 min routine, tap to log. Suggests one of: McGill Big 3 (curl-up, side plank, bird-dog), hip flexor stretch series, hamstring mobility, cat-cow flow.
- [ ] **Warm-up block prepended to lift days** — each strength session in `Program` now has a `warmupBlock: [Exercise]` field. Block runner steps through warm-up first.
- [ ] **Standalone Mobility day** added to seeded programs — 1x/week dedicated session, ~20 min.

**New mobility exercises in `SeedExercises.swift`:**
- McGill curl-up, side plank, bird-dog
- 90/90 hip stretch, couch stretch, pigeon
- Hamstring strap stretch, dead bug
- Cat-cow, thoracic rotation
- Wall hip flexor lunge

Tag with `category: .mobility` so they don't pollute the strength PR view in Progress.

**Files:** `Data/Seed/SeedExercises.swift`, `Data/Seed/SeedPrograms.swift`, `Features/Today/MobilityCard.swift` (new), `Features/Workouts/BlockRunner.swift` (warm-up block support), `Domain/Models.swift` (`Program.warmupBlock`).

---

## 7. Progress section — modals + better visuals

Use frontend-design agent for visual polish (see §10). Functional spec below.

### 7a. Steps deep-dive modal (both modes)
- Hourly bar chart for today (24 bars, HealthKit intraday)
- Week vs last-week overlay
- Monthly average + 30-day rolling line
- Longest streak (consecutive goal-hit days)
- Tap-and-hold on any bar shows that hour's exact step count

### 7b. Pilates modal (Circuit)
- Calendar heatmap (last 90 days) — color intensity by session duration
- Focus-area breakdown — donut chart: % of sessions tagged each area, surfaces gaps ("you haven't logged Lower Back in 3 weeks")
- Total minutes this month vs last
- Progress history table — date, duration, focus tags, notes

### 7c. Health markers modal (Circuit-critical)
- One card per marker: BP, LDL, HDL, triglycerides, A1c, fasting glucose, RHR
- Tap card → full-screen chart: target range overlay (green band), historical trend, last reading badge
- Manual entry sheet with date picker (these come from blood-work, not auto)
- Optional doctor-visit notes per reading
- 8-week stagnation flag → soft suggestion to discuss with doctor (never prescribe)
- **`LabResult` parent entity** groups markers from a single blood draw by `drawnDate`. LDL/HDL/triglycerides/total cholesterol typically come from one panel — entering them as a group preserves that relationship for trend math.
- **Screenshot/photo import** (opt-in, low-friction path):
  - "Import from photo" button on the entry sheet
  - Pipeline: photo → Vision OCR (reuses §4 OCR plumbing) → text → Apple Intelligence with structured-output schema (`{ldl, hdl, triglycerides, totalCholesterol, a1c, fastingGlucose, drawnDate }`) → pre-filled review sheet → user confirms each field
  - Lab formats vary wildly (LabCorp / Quest / hospital PDFs / Apple Health screenshots) — never auto-save; always show confirmation sheet with raw OCR text visible alongside parsed fields
  - Falls back gracefully: if AI returns null for a field, that field stays empty and waits for manual entry

### Other progress cards (existing, may need design polish)
- Weight trend (Build emphasis)
- ~~Lift PRs (Build only)~~ — not planned

**Files:** `Features/Progress/ProgressView.swift`, `Features/Progress/Modals/StepsDeepDive.swift` (new), `Features/Progress/Modals/PilatesProgress.swift` (new), `Features/Progress/Modals/HealthMarkersDetail.swift` (new), `Components/CalendarHeatmap.swift` (new), `Components/RangeBandChart.swift` (new).

---

## 8. Nutrition library — clickable food modals

Current library is "tap to log." Add a **detail view** before the log action.

- [ ] Tap a food → `FoodDetailModal`:
  - Photo (or symbolic icon if none)
  - Full macros breakdown (visual bars not just numbers)
  - Mode-fit explanation ("Fits Circuit because: high fiber, low sodium, omega-3")
  - "Why we suggested this" if it's from the suggestion engine
  - Common pairings (e.g. "Pairs with brown rice for a complete meal")
  - **Log this** button at bottom (primary CTA)
  - "Add to favorites" secondary
- [ ] Long-press a food → quick-log without opening modal (preserves current fast path).

**Files:** `Features/Nutrition/FoodDetailModal.swift` (new), `Features/Nutrition/NutritionView.swift`, `Domain/Suggestions.swift` (expose the reasoning behind a score, not just the score itself).

---

## 9. Apple Intelligence integration (FoundationModels)

iOS 18.1+ only. Gate behind availability check; degrade to deterministic-only on older devices or unsupported regions.

- [ ] `Services/AIEstimator.swift` — wraps `FoundationModels` `LanguageModelSession`. Structured-output API.
- [ ] **Use case 1 (active):** estimate macros for custom food (§4).
- [ ] **Use case 2 (active):** "Explain why" — given a logged meal + active mode caps, generate a 1-sentence natural-language summary ("Good Circuit choice — this hits your fiber gap without breaking sodium").
- [ ] **Use case 3 (later):** ingredient-list → meal recommendation. User taps "What can I make?" → picks from a list of in-house ingredients → AI returns 3 meal ideas ranked by mode fit. Deterministic scoring still runs on top of AI output.
- [ ] **NOT yet:** any open-ended chat surface, any medical advice generation. Hard rule: AI never prescribes; it suggests.

**Files:** `Services/AIEstimator.swift`, `Services/AIExplainer.swift`, `Domain/AIAvailability.swift` (capability check).

**Availability check:**
```swift
import FoundationModels
let model = SystemLanguageModel.default
guard model.availability == .available else { /* degrade */ }
```

---

## 10. Frontend design pass (Progress + Nutrition library)

Delegate to `frontend-design` agent after §7 and §8 functional code lands. Scope:

- Progress section visual polish — charts, modals, transitions
- Nutrition library + FoodDetailModal — photo treatment, macro visualization, mode-fit badge design
- Mode-aware palette already exists (Build warm dark, Circuit warm light) — agent must respect `Theme.for(profile.mode)`
- Preserve all tactile UX rules from CLAUDE.md (TactileButtonStyle, PressableCard, ToastCenter, Haptics)
- Dynamic Type must stay clean at XXL

Hand the agent: this plan + CLAUDE.md design section + nav-bar-implementation.md.

---

## 11. Build order (revised)

The CLAUDE.md "Build order" is unchanged in spirit, but specific items here re-prioritize:

1. **HealthKit wiring** (§1) — blocking
2. **Profile model fix** (§2) — quick, unblocks testing both modes
3. **Circuit Train rewrite** (§5) — biggest single behavior change
4. **Caps tooltips** (§3) — low effort, high clarity gain
5. **Custom food pipeline** (§4) — USDA first, AI later, OCR last
6. **Build mobility track** (§6)
7. **Progress modals** (§7)
8. **Nutrition library modal** (§8)
9. **Apple Intelligence** (§9) — incremental, behind capability check
10. **Design pass** (§10)

Ship §1–§5 before §6+. The daily loop is still the product.

---

## 12. Resolved decisions

- **Pilates**: logging only. No app-suggested routines in v1.
- **Movement-minutes display**: three separate rings (Steps / Pilates / Active-energy-from-cardio). More legible than a combined ring; lets her see which lever is lagging.
- **Lab Result parent entity**: yes. Cholesterol panel + A1c + fasting glucose from a single blood draw group under one `LabResult { drawnDate, markers: [HealthMarker] }`.
- **Lab screenshot import**: yes, included (§7c). Reuses §4 OCR + Apple Intelligence plumbing — no significant added cost.
- **USDA API**: 1000/hr unkeyed is plenty for two users. Register a free key later only if we hit limits.
- **Apple Intelligence**: confirmed iOS 18.1+ / US region for both devices.

---

## 13. What's Not in this round

- Apple Watch companion target (post-v1 still)
- Notifications / Live Activities
- Grocery list + weekly planner
- Export/import (JSON backup)
- 14-day auto-adjust cards
- Third profile, ever
- Any social / sharing / leaderboard surface
- Any medical advice generation

These stay non-goals.
