# Expanding exercises, activities & food detection — research + proposal

_Research date: 2026-06-02. Grounds: the existing codebase (`Domain/CalorieEstimator.swift`, `Domain/ExerciseInfo.swift`, `Domain/FoodParser.swift`, `Domain/CommonFoods.swift`, `Services/ExerciseInsightService.swift`, `Domain/Models.swift`) + external sources cited at the end._

---

## TL;DR — the one principle that decides everything

> **Numbers come from data. Language comes from AI.**

The app already lives by this (see the guardrail comment in `ExerciseInsightService`: "we do NOT let the model touch MET / calorie math"). Every recommendation below keeps that line:

- **Calorie/MET/macro numbers** must come from a deterministic source — the Ainsworth MET compendium (already used) for activity, and a real nutrition database (USDA FoodData Central) for food. These are accurate, auditable, and offline.
- **Apple's on-device AI (FoundationModels)** is excellent for *parsing, extracting, classifying, and writing plain-English copy* — but it has **no internet access and is explicitly "not suitable for world knowledge"** ([Apple ML Research](https://machinelearning.apple.com/research/introducing-apple-foundation-models), [WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/)). If we ask it "how many calories in a bagel with lox," it will *confidently invent* a number. That's dangerous in a fitness app. So AI's job is to turn messy user text into a **structured query** against our data — never to be the data.

This single principle resolves all four of your questions cleanly. Ranked by value-to-effort:

| Feature | Accuracy ceiling | Effort | Verdict |
|---|---|---|---|
| **Activity sessions (basketball, skating…)** | **High** — pure MET math we already do | Low | **Do this first** |
| More named exercises (reverse plank, holds, dumbbell, arms) | High (curated METs) | Low–med | Do incrementally |
| Bigger food database (USDA FDC bundled) | High | Medium | High value |
| AI free-text → structured food/exercise parse | High *if* it queries a DB | Medium | The "magic," done safely |
| AI inventing nutrition numbers directly | **Unsafe** | — | **Don't** |

---

## 1. Activities like basketball, skating, soccer (Train tab) — the easiest win

**This is the highest-value, fully-accurate feature, and the data model already exists.**

Calorie burn for a timed activity is exactly the formula the app already uses everywhere:

```
kcal = MET × bodyWeightKg × hours
```

We already have the user's **current weight** (now live, post the weight-sourcing fix), and `CalorieEstimator.kcal(mets:bodyWeightLb:hours:)` already does this math. A "basketball session for 45 min" is *more* accurate than a rep-counted strength set, because duration × MET is the compendium's native unit.

### What exists today
`CardioSessionDTO` (Circuit) already models exactly this shape: `type`, `durationMinutes`, optional `distanceMiles`, optional `rpe`, `caloriesEst`. But:
- `CardioType` is a fixed 6-case enum (`walk/run/bike/swim/elliptical/other`).
- `CalorieEstimator.caloriesForDuration` uses a **flat 3.5/4.5 MET**, which is wrong for vigorous sport (basketball is 8.0, not 4.5).

### Proposal: a MET-keyed activity catalog + a "Log activity" sheet in Train

1. **`Domain/ActivityCatalog.swift`** (pure, tested) — a list of activities each with a compendium MET and an SF Symbol, e.g.:

   ```swift
   public struct Activity: Identifiable, Sendable {
       public let id: String      // "basketball-game"
       public let name: String    // "Basketball (game)"
       public let met: Double     // 8.0
       public let symbol: String  // "figure.basketball"
       public let tracksDistance: Bool
   }
   ```

2. **MET table** (from the 2011 Compendium — verify each code against [pacompendium.com/sports](https://pacompendium.com/sports/) at implementation time; representative values below):

   | Activity | MET | | Activity | MET |
   |---|---|---|---|---|
   | Basketball, game | 8.0 | | Ice skating, general | 7.0 |
   | Basketball, shooting around | 4.5 | | Inline/roller skating | 7.5 |
   | Soccer, casual | 7.0 | | Skateboarding | 5.0 |
   | Soccer, competitive | 10.0 | | Swimming, laps moderate | 7.0 |
   | Tennis, singles | 8.0 | | Cycling, 12–14 mph | 8.0 |
   | Tennis, doubles | 6.0 | | Jump rope, moderate | 11.8 |
   | Volleyball, casual | 3.5 | | Rowing machine, moderate | 7.0 |
   | Hiking | 6.0 | | Boxing, bag work | 5.5 |
   | Dancing | 5.5 | | Rock climbing | 8.0 |

   These are MET *point estimates*. They're the same evidence basis the app already cites, so they fit the existing "calorie math — sources and validation" table in `CLAUDE.md`.

3. **Optional RPE refinement** (the model already has an `rpe` field): scale the catalog MET by a small factor from perceived effort (e.g. ±15% across RPE 4→9). Keep it optional; the base MET is the honest default.

4. **UI**: a "Log activity" entry in the Train tab (Build) — pick activity → enter duration → optional RPE → save. Calories = `CalorieEstimator.caloriesForActivity(met:minutes:bodyWeightLb:)` (a 3-line addition). Reuse the existing `CardioLogCard` patterns; the data can either generalize `CardioSessionDTO` (rename `CardioType` → a freer activity id, additive Codable) or add a parallel `ActivitySessionDTO`.

**Why this is safe and accurate:** the number is `MET × kg × hours` with a peer-reviewed MET and the user's real weight. No AI, no guessing. This is strictly better than asking the user to rep-count a basketball game.

> ⚠️ Honest caveat: MET tables assume an "average" person; individual burn varies ±15–20%. When the user has an Apple Watch, Apple's *measured* active energy (already shown in `MoveCard`) is the better number for whole-day burn — so we should keep presenting the MET estimate as an *estimate* beside the Watch number, exactly as the app already does for steps.

---

## 2. More exercises: reverse plank, holds, dumbbell & arm work

The exercise system has three tiers; expanding it means feeding the right tier.

**Tier 1 — curated named library (`ExerciseInfo.namedMeta`).** This is a substring matcher: `"deadlift"` → MET 6.0 + muscles + cited benefits. Adding exercises is just adding `if lower.contains("…")` branches.
- **Holds (reverse plank, hollow hold, wall sit, dead hang, L-sit)** are already first-class: `isIsometric: true` turns the rep counter into a countdown, and `caloriesForIsometric(seconds:met:)` handles the math (default 3.8 MET). Reverse plank ≈ 3.5–4.0 MET — just add a `contains("reverse plank")`/`"wall sit"`/`"dead hang"` branch with the right MET and muscle list. **The machinery exists; it needs entries.**
- **Dumbbell / arm exercises** (lateral raise, hammer curl, concentration curl, skull crusher, dumbbell fly, Arnold press, reverse fly, kickback, Zottman curl, etc.): most already route through existing branches (`curl`, `tricep`/`extension`, `press`, `fly`/`rear delt`). Gaps worth adding: **lateral raise** (currently falls to OHP), **chest/dumbbell fly**, **shrug variants** (have it), **wrist/forearm work**. Each is a small MET (3.5–4.5) isolation entry.

**Tier 2 — category defaults.** Any unknown exercise already gets a sane MET by `ExerciseCategory` (isolation 3.5, compound 5.5, etc.). This is the safety net that keeps calorie math deterministic for *anything* the user types.

**Tier 3 — on-device AI description (`ExerciseInsightService`).** For genuinely novel exercises, the model already writes plain-English muscles + benefits (descriptive only). 

### The one AI upgrade worth making here
Today, an unknown exercise gets a category-default MET only if the user picked the right category. We can let the on-device model **classify** an unknown exercise into `{category, isCompound, primaryPattern}` (a classification/extraction task it's genuinely good at) and use that to pick a better MET *tier* — **still from our table, never a number the model invents.** That tightens the estimate without crossing the "AI never emits the number" line.

**Recommendation:** keep growing Tier 1 with batches of named entries (cheap, high-trust, cited). Add the AI-classification-picks-the-tier bridge as a later polish.

---

## 3. Foods & meals with accurate readings

This is where "can the AI just find it?" matters most — and where the honest answer is **no, not on its own.**

### Why AI alone can't do food numbers
The on-device model has no internet and weak world knowledge. Ask it for the macros of "chicken tikka masala" and it will produce *plausible-looking but unverified* numbers — the worst failure mode for a tracker, because they look right. Apple itself positions the model for "summarization, extraction, classification," **not** facts ([Apple ML Research](https://machinelearning.apple.com/research/introducing-apple-foundation-models)).

### The accurate path: a real database + AI as the parser
Today `FoodParser` matches user text against the hand-built `CommonFoods.all` (~dozens of foods, sourced from USDA). It's offline and trustworthy but small — anything not in the list is "unrecognized."

**Option A — keep growing `CommonFoods` by hand.** Cheap, fully offline, but coverage is the bottleneck; users will out-type it.

**Option B — bundle USDA FoodData Central (recommended).** USDA FDC is the authority the app *already cites*. It's **public domain (CC0)**, **downloadable in bulk** (JSON/CSV), and covers **300k+ foods** across Foundation, SR Legacy, Branded, and Survey datasets ([download page](https://fdc.nal.usda.gov/download-datasets/), [API guide](https://fdc.nal.usda.gov/api-guide/)). We can:
   1. Take the **SR Legacy + Foundation** subsets (whole foods, the relevant ones — Branded is 400k+ commercial barcodes, probably more than we want to ship), prune to the fields we use (kcal, protein, carbs, fat, fiber), and bundle a compact SQLite/JSON in the app. Offline, no backend (respects the locked "no backend" rule), authoritative numbers.
   2. `FoodParser` queries this DB instead of (or in addition to) the hand list.

**Option C — USDA FDC API (online enrichment).** Free with an API key, but it's a network call — conflicts with the offline-first / no-backend stance. Best as an *optional* "look it up online" fallback for misses, behind a setting, never the primary path.

### Where AI genuinely helps food logging (safely)
The model is great at the *parsing* layer that `FoodParser` does with string rules today:
- **Extraction:** "two eggs, a slice of sourdough and a flat white" → `[{egg, 2}, {sourdough bread, 1 slice}, {flat white, 1}]` — units, quantities, and item splitting, far more robustly than the current separator/quantity-word heuristics.
- **Normalization/synonyms:** map "brekkie burrito" → "breakfast burrito" so the DB lookup hits.
- **Tool calling:** FoundationModels supports **tool calling** — we can give the model a `lookupFood(name)` tool that hits our bundled USDA DB, so the flow is *AI parses + calls our DB tool → DB returns the numbers → AI assembles the structured result.* The AI orchestrates; the DB is the source of truth ([WWDC25 tool calling](https://developer.apple.com/videos/play/wwdc2025/286/)).

**Recommendation:** Bundle a pruned USDA FDC dataset (Option B) as the number source, and use FoundationModels as a smarter parser/normalizer in front of it (with the existing `FoodParser` string matcher as the offline/older-OS fallback, since FoundationModels is iOS 26+ only).

---

## 4. Direct answer: "Can the Apple OS AI research/search whatever the user types?"

**Short answer: it can *understand* anything the user types, but it cannot *look anything up* — it has no internet and isn't a knowledge base.** ([Apple ML Research](https://machinelearning.apple.com/research/introducing-apple-foundation-models); the docs are explicit that it is "not suitable for world knowledge.")

So the realistic, safe division of labour:

| Task | On-device AI? | How |
|---|---|---|
| Split & quantify a free-text meal | ✅ Yes | extraction → structured items |
| Know the calories of that meal | ❌ No | look up each item in USDA DB (AI may *call* the DB via tool calling) |
| Describe an unknown exercise's muscles/benefits | ✅ Yes (already shipped) | descriptive generation, no numbers |
| Pick a MET for an unknown exercise | ⚠️ Indirectly | AI *classifies* it; we map the class → a compendium MET |
| Invent a MET or macro number | ❌ Never | deterministic table/DB only |
| Work offline / older iOS | ❌ FoundationModels is iOS 26+ | always keep the deterministic fallback path |

This is the same guardrail the codebase already documents — we're just extending it to food.

---

## 5. Recommended roadmap

1. **Activity sessions in Train (basketball, skating, sport, etc.)** — MET catalog + log sheet. Highest value, fully accurate, low effort, no AI dependency. _Start here._
2. **Batch-expand the curated exercise library** — reverse plank & other holds, lateral raise, dumbbell fly, more arm/dumbbell isolation entries. Cheap, cited, deterministic.
3. **Bundle a pruned USDA FoodData Central dataset** and point `FoodParser` at it — the big accuracy/coverage unlock for meals, still offline.
4. **AI as parser/normalizer (FoundationModels) in front of the food DB**, with tool calling to the bundled DB; keep the string matcher as the offline/iOS-17 fallback.
5. **AI classify-to-MET-tier** for unknown exercises — last polish.

Everything above keeps the project's locked constraints: offline-first, no backend, deterministic numbers, AI descriptive-only, graceful degradation below iOS 26.

---

## 6. Live sessions (real-time basketball / pilates timer) — feasibility & design

**Question:** can a live, timed session keep running if the user leaves the app (e.g. to change Spotify) or even closes it — and notify them when their planned time is up?

**Finding:** iOS **suspends backgrounded apps** — an app cannot keep a timer ticking or run code in the background unless it holds a navigation/audio/location entitlement (which we should NOT claim for a workout timer; it risks App Store rejection). [Apple Dev Forums](https://developer.apple.com/forums/thread/711194). But a live session does **not need** the app to keep running. The robust pattern:

1. **Anchor to a start timestamp.** Persist `startDate` the instant the session begins. Elapsed time is always `Date.now − startDate`, recomputed whenever the screen is visible (via `TimelineView`). When the user comes back from Spotify — or even relaunches after iOS killed the app — the elapsed time is still correct and the session **resumes seamlessly**. Continuity is true *by construction*, with no background execution. This also makes the calorie number **more accurate** than a user-estimated duration (the whole point of your request).
2. **Local notification at the planned end.** Schedule a `UNUserNotificationCenter` notification for `startDate + expectedMinutes`. It fires even while the app is suspended or force-quit — that's the "you hit 30 min, still going?" alert. Reschedule on adjust, cancel on finish. _Crash-trap rule:_ request notification permission only on an explicit Start tap (never `.onAppear`), mirroring the documented HealthKit lesson; if denied, the session still works, just silently.
3. **Live Activity (Lock Screen / Dynamic Island) — Phase 2.** A `Text(timerInterval:)` in a Live Activity counts on the **system side** without the app running, so the live timer would show on the Lock Screen while the user is in another app — the premium version of "it keeps going." This needs a separate **Widget Extension target** + `project.yml` + `NSSupportsLiveActivities` + on-device verification, so it's deferred; the timestamp + notification core already delivers the functional guarantee. [Meet ActivityKit (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10184/), [Live Activities guide](https://newly.app/articles/ios-live-activities).

**Data/UX shape (being built):** a `LiveSessionState` (startDate, activity, expectedMinutes) persisted to UserDefaults for resume; a completed `ActivitySessionModel` (additive `SchemaV5`, same safe path as `WaterEntryModel`); calories = `MET × live bodyweight × actual elapsed`; a calm full-screen timer with a `ProgressRing` toward the planned time, a gentle over-time state, and "End"/"+5 min" actions; entry from the Train tab (Build) and Today (Circuit). Everything links to the profile's live weight + the metric/imperial setting.

## Sources
- Apple — [Introducing Apple's On-Device and Server Foundation Models](https://machinelearning.apple.com/research/introducing-apple-foundation-models)
- Apple — [Meet the Foundation Models framework (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/286/) · [Foundation Models docs](https://developer.apple.com/documentation/FoundationModels)
- Ainsworth BE et al. — [2011 Compendium of Physical Activities](https://pacompendium.com/sports/) (MET values) · [PubMed](https://pubmed.ncbi.nlm.nih.gov/21681120/)
- USDA — [FoodData Central downloadable datasets](https://fdc.nal.usda.gov/download-datasets/) (CC0 public domain) · [API guide](https://fdc.nal.usda.gov/api-guide/)
