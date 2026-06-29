# Encouragement System — Design Plan

> Status: Partially implemented. `EncouragementEngine`, `EncouragementMessage`, `ToastCenter` hooks, and `ProjectionBar` exist; notification scheduling and the larger sheet system remain future work.

---

## Overview

A layered encouragement system across three surfaces:
1. **In-app toasts** — ephemeral, fire-and-forget (extends existing ToastCenter)
2. **Encouragement sheets** — medium-detent info panels with science context, triggered by tapping milestone chips or info buttons
3. **Local push notifications** — scheduled UNUserNotificationCenter notifications (morning routine, post-log, weekly summary, stall nudge)

Two complete message banks: one for **Build** (mass, hypertrophy, basketball fueling) and one for **Reset** (cardiometabolic markers, parenting movement, BP/LDL/insulin). Messages are scientifically specific — not generic "great job!" but "14 more pull-up sets this week locks in the 14% frequency advantage."

---

## New Files

```
Domain/
  EncouragementEngine.swift         ← pure Swift, no SwiftUI/SwiftData
  EncouragementMessage.swift        ← value types: EncouragementMessage, Trigger, Tone
Services/
  NotificationService.swift         ← UNUserNotificationCenter wrapper
Components/
  MilestoneChip.swift               ← inline chip (sits below exercise card or step ring)
  EncouragementSheet.swift          ← medium-detent science panel
  ProjectionBar.swift               ← "X more → Y kcal / threshold" inline strip
Features/Settings/
  NotificationSettingsView.swift    ← per-category toggles (inside existing SettingsView)
```

Existing files modified (no new files for these):
- `Services/ToastCenter.swift` — add 8 new toast constructors
- `Features/Workouts/WorkoutsView.swift` — fire post-set encouragement toast + ProjectionBar
- `Features/Today/StepsCardioCard.swift` — fire milestone toasts (5 levels), add ProjectionBar
- `Features/Today/TodayView.swift` — fire "almost there" macros toast; weekly summary banner
- `Features/Settings/SettingsView.swift` — add NotificationSettingsView link
- `App/OurFitnessApp.swift` — request notification permission on first launch (after profile created)

---

## Architecture Constraints (CLAUDE.md compliance)

- `Domain/EncouragementEngine.swift` — pure Swift only, no SwiftUI/SwiftData
- `Services/NotificationService.swift` — calls `UNUserNotificationCenter` only from explicit user-initiated flow (Settings) or from `.task` on the post-profile-creation screen — never from `.onAppear` on main views
- All `@Query` stays predicate-scoped (no client-side filter)
- Push permission requested once, post-profile creation (mirrors HealthKit pattern)
- No 6th button variant added
- Sheet background via `.presentationBackground(theme.bg)`

---

## Domain Layer — EncouragementEngine

### Types

```swift
// Domain/EncouragementMessage.swift

enum EncouragementTone {
    case celebrate      // milestone hit: "Crushed it."
    case impressed      // outlier performance: "That's elite."
    case approaching    // within 85–99% of goal: "Almost there."
    case nudge          // slacking / gap in logs: "Let's pick it back up."
    case scienceTip     // post-activity science context
    case projection     // "X more → Y outcome"
}

enum EncouragementTrigger {
    // Steps
    case stepMilestone(steps: Int)
    case stepGoalApproaching(pct: Double)   // 85%+ of daily goal
    case stepGoalHit
    case stepStreakMilestone(weeks: Int)    // 1, 5, 10, 26, 52
    // Workouts
    case setLogged(exercise: String, totalSetsThisWeek: Int, muscle: String)
    case weeklyVolumeThreshold(muscle: String, sets: Int)  // crossed MEV or MAV
    case progressiveOverloadOpportunity(exercise: String)  // 3 sessions at same weight RPE ≤8
    case deloadRecommended(weeksSinceDeload: Int)
    // Nutrition
    case macroGoalApproaching(macro: String, pct: Double)
    case macroGoalHit(macro: String)
    case proteinMissing(gRemaining: Int)    // end of day protein gap
    case fiberGoalHit
    case sodiumWarning(mg: Int)
    case addedSugarWarning(g: Int)
    // Circuit-specific
    case pilatesMilestone(sessions: Int)
    case pilatesStreakMilestone(weeks: Int)
    case markerImproved(kind: HealthMarkerKind, delta: Double)
    case markerStall(kind: HealthMarkerKind, weeks: Int)
    // General
    case weeklyStreak(weeks: Int)
    case logGap(days: Int)                  // haven't logged in N days
    case weightTrend(lbPerWeek: Double, mode: Mode)
}

struct EncouragementMessage {
    let headline: String           // short, bold (≤50 chars)
    let detail: String             // 1–2 sentences
    let scienceLine: String?       // citation-grade fact (shown in sheet, optional in toast)
    let tone: EncouragementTone
    let sfSymbol: String
    let callToAction: String?      // e.g. "Log a set", "Add water"
}
```

### EncouragementEngine API

```swift
// Domain/EncouragementEngine.swift

enum EncouragementEngine {
    static func message(
        for trigger: EncouragementTrigger,
        mode: Mode,
        profile: ProfileDTO,
        now: Date = Date()
    ) -> EncouragementMessage

    // Projection strings (inline, not sheet)
    static func repProjection(
        exercise: String,
        repsLogged: Int,
        bodyWeightLb: Double,
        mode: Mode
    ) -> String?     // nil if no meaningful projection

    static func stepProjection(
        stepsToday: Int,
        goalSteps: Int,
        bodyWeightLb: Double
    ) -> String?
}
```

All math re-uses existing `CalorieEstimator` and `ExerciseInfo`. No new math layer needed.

---

## Message Banks

### Build Mode — Full Copy (with science)

#### Step Milestones
| Steps | Tone | Headline | Detail | Science Line |
|-------|------|----------|--------|--------------|
| 3,000 | celebrate | "Moving." | "You've hit the baseline. Momentum starts here." | "Every 1,000 steps cuts all-cause mortality risk by ~12%. (Saint-Maurice, JAMA 2020)" |
| 5,000 | celebrate | "Good pace." | "Halfway there on steps. Your muscles are already benefiting from the walk." | nil |
| 8,000 | celebrate | "8k. That's serious." | "8k steps/day is associated with 51% lower all-cause mortality vs. 4k. You're in that zone." | "Saint-Maurice 2020, JAMA." |
| 10,000 | celebrate | "Daily goal done." | "Full step goal complete. That's the cardiometabolic sweet spot, hit consistently." | nil |

#### Workout Milestones (Build Mode)
| Trigger | Tone | Headline | Detail | Science Line |
|---------|------|----------|--------|--------------|
| setLogged, totalSetsThisWeek ≥ 4 for muscle | scienceTip | "MEV unlocked." | "You've hit the minimum effective volume for [muscle]. Growth mode is on." | "MEV for trained lifters: 4–8 sets/muscle/week. (RP Strength)" |
| setLogged, totalSetsThisWeek ≥ 10 | celebrate | "10 sets this week. Serious." | "You're into the hypertrophy sweet spot for [muscle]. Keep the frequency up." | "12–20 sets/muscle/week = MAV. Frequency matters: spread > 3 sessions/week adds 14% more growth. (Sports Medicine, 2020)" |
| weeklyVolumeThreshold crossed MAV | impressed | "MAV territory." | "[Muscle] is getting real stimulus. Stay consistent and you'll see size in 8–12 weeks." | nil |
| progressiveOverloadOpportunity | scienceTip | "Time to add weight." | "You've hit this weight 3 times at RPE ≤8. Add 2.5 lbs (upper) or 5 lbs (lower) next session." | "Progressive overload rule: complete all reps RPE ≤8 = increase load. (RPE.training)" |
| deloadRecommended (≥6 weeks) | nudge | "Deload week?" | "You've trained hard for [N] weeks. Cutting volume in half for a week lets you come back stronger." | "Deload every 4–8 weeks: cut sets 40–50%, keep weight. (NSCA)" |

#### Pull-up Specific (Build Mode)
| Reps this week | Headline | Detail |
|----------------|----------|--------|
| 1st set logged | "Lats engaged." | "Pull-ups are the gold standard for lat width. Overgrip (palms away) hits lats hardest; undergrip (chin-ups) peaks biceps." |
| ≥3 sets/week | "Frequency building." | "Spreading pull-up sets across sessions shows 14% better lat growth than doing the same volume in one day." |
| ≥6 sets/week | "MEV for lats." | "You've hit minimum effective volume for lat hypertrophy. Visible width changes show up 8–12 weeks of consistent effort." |

#### "Wow/Impressive" (Build Mode) — Outlier Performance
| Trigger | Headline | Detail |
|---------|----------|--------|
| PR on a major lift | "New personal best." | "That's not a number — that's adaptation. Your nervous system recruited more motor units. Keep chasing it." |
| 5th consecutive week hitting volume | "5 weeks of consistency." | "Consistency is the actual variable. You're building the compounding effect right now." |
| Volume 30%+ above last week | "Big week." | "High-volume weeks drive hypertrophy. Recover well — protein timing matters more tonight." |

#### Nutrition Projections (Build Mode)
| Trigger | Projection Copy |
|---------|----------------|
| 20g protein short, evening | "20g protein gap. A Greek yogurt (17g) + handful of almonds closes it tonight." |
| Calorie goal approaching (90%) | "90 cal left to hit your Build target. Don't skip it — you need the surplus to build." |
| Protein goal hit | "Protein locked. Every gram above your target has diminishing returns — quality matters more now." |
| Fiber low (<15g by evening) | "Fiber's low today. One apple + tablespoon chia = ~7g. Fiber improves insulin sensitivity, supporting your surplus." |

---

### Reset Mode — Full Copy (with science)

#### Step Milestones (Reset Mode)
| Steps | Tone | Headline | Detail | Science Line |
|-------|------|----------|--------|--------------|
| 3,000 | celebrate | "3k. Starting." | "You're moving. Each 1,000 steps is a measurable cardiometabolic win." | "1,000 steps/day → 0.49 mmHg lower systolic BP. (PMC 2021)" |
| 5,000 | celebrate | "Halfway to 10k." | "5k steps reduces fasting glucose. You're already improving insulin sensitivity just by walking." | "10-min stair walking → 23 mg/dL glucose reduction. (ScienceDirect)" |
| 8,000 | impressed | "8k. The research sweet spot." | "51% lower all-cause mortality vs 4k. You've crossed a scientifically meaningful threshold." | "Saint-Maurice, JAMA 2020. Saint-Maurice 2020 also found no clear plateau — keep going." |
| 10,000 | celebrate | "10k done." | "Daily step goal complete. This is the primary lever for BP, insulin sensitivity, and LDL in Reset mode. You hit it." | nil |

#### Pilates (Reset Mode)
| Sessions | Tone | Headline | Detail | Science Line |
|----------|------|----------|--------|--------------|
| 1st session | scienceTip | "Pilates for real." | "Core stability and blood pressure benefits begin accumulating from your very first session. Consistency compounds it." | "Pilates: −4.76 mmHg systolic, −3.43 mmHg diastolic vs. controls. (J Human Hypertension, 2024)" |
| 3rd session (weekly goal hit) | celebrate | "3 sessions. Weekly goal hit." | "You hit the pilates streak threshold. Core muscle thickness measurably increases in 6–8 weeks at this pace." | "MDPI 2025: significant transverse abdominis + internal oblique thickness increase after 8 weeks." |
| Streak milestone (4 weeks) | celebrate | "4 weeks of pilates." | "At this point your core contraction timing has improved — your spine is stabilizing movements it couldn't before." | nil |
| Streak milestone (8 weeks) | impressed | "8 weeks. That's real change." | "Research shows 8 weeks of consistent pilates produces measurable core strength + spine stability. You've done the work." | "Journals.sagepub.com core training study, 2021." |

#### Blood Pressure Marker Improvements
| Trigger | Tone | Headline | Detail |
|---------|------|----------|--------|
| markerImproved systolic >3 mmHg | celebrate | "BP moving in the right direction." | "A drop of [N] mmHg systolic is clinically meaningful. Aerobic exercise achieves 5–8 mmHg reduction in hypertensive individuals over weeks." |
| markerImproved diastolic >2 mmHg | celebrate | "Diastolic down." | "Diastolic improvement signals reduced vascular resistance. Keep the steps and pilates consistent." |
| markerStall BP >6 weeks | nudge | "BP's been steady. Let's push it." | "Walking 13,500+ steps/day in a 12-week study produced −10 mmHg systolic reduction. Your step goal is the lever here." |

#### Parenting Exercises (Circuit Mode)
| Exercise | Rep milestone | Headline | Detail |
|----------|---------------|----------|--------|
| Lifted Baby | 10 reps | "10 reps with your littlest weight." | "[N] cal burned. More importantly: functional posterior chain strength that makes daily carrying easier and safer." |
| Lifted Stroller | 5 reps | "Stroller lifted [N] times." | "Functional overhead load — shoulder stability, core, lats. It all transfers to your daily carry patterns." |
| Carried Baby | 5 min | "[N] minutes of carry." | "Loaded carry is one of the best functional strength patterns. MET ~4.5 means you burned [X] cal while doing the most important job." |

#### Stall Nudges (Circuit Mode)
| Stall type | Nudge Headline | Detail |
|-----------|----------------|--------|
| No step log 2+ days | "Steps paused?" | "You're mid-streak. Even 5 minutes of walking restores the cardiometabolic signal — especially post-meal." |
| No pilates 7+ days | "Pilates gap." | "Core stability gains begin reverting after 7–10 days without stimulus. One session today stops the slide." |
| LDL stall 6+ weeks | "LDL hasn't moved." | "Aerobic exercise + fiber targeting (30–45g/day with 7–12g soluble) is the evidence-based combo for LDL reduction. Which is lower for you right now?" |
| Weight stall Circuit (2+ weeks) | "Weight's flat." | "Flat weight on Circuit usually means cardio needs a bump. Add 1,000 steps or a 20-min cardio session — or trim 150 cal from dinner." |

#### "Wow/Impressive" (Circuit Mode)
| Trigger | Headline | Detail |
|---------|----------|--------|
| 7-day step streak >9k average | "Elite walking week." | "A week averaging 9k+ steps is associated with the lowest mortality risk bracket in large cohort data. That's not small." |
| Both pilates + step goal same day | "Double win today." | "Steps + pilates in the same day is compounding cardiometabolic benefit — aerobic + stability + resistance in one day." |
| Resting HR drops new low | "Heart rate at a new low." | "Lower resting HR = stronger cardiac output per beat. Your heart is adapting. [N] bpm is [athlete/fit/good] range." |
| LDL drop >10 points | "LDL down [N] points." | "That's a clinically meaningful lipid shift. Consistent aerobic exercise + fiber is doing exactly what the research says it should." |

---

## Projection Strings (Inline, under cards)

These appear as small capsule chips below the exercise card or step ring, not as sheets.

### Step Projections
```
"{N} more steps → approx. {X} cal burned (total {Y} cal today)"
"{N} more steps = one full mile. Your {BP/insulin} marker improves with every mile."
"You're {N} steps from 10k. That's {X} cal and today's primary cardiometabolic goal done."
```

### Workout Projections (Build Mode)
```
"{N} more pull-up sets this week hits MEV for lats. Growth signal activates."
"{N} more sets of squads reaches 10 sets — hypertrophy sweet spot for quads/glutes."
"Adding 2.5 lbs today (RPE was ≤8 last session) follows the progressive overload rule."
"{N} more reps → approx. {X} cal burned this session. Total so far: {Y} cal."
"After {N} weeks at this volume, visible lat/quad/chest changes become measurable."
```

### Nutrition Projections
```
"{N}g protein left. A chicken breast (~53g) covers it plus adds leucine threshold for MPS."
"{N}g fiber short. Chia seeds (1 tbsp = 5g) or an apple (4g) + oats (4g) = done."
"You're {N} cal from your Build surplus. Don't leave gains on the table tonight."
```

### Calorie Burn Projections (Circuit — steps)
```
"Walk {N} more minutes at this pace → {X} cal. Total walk burn today: {Y} cal."
"10 min of post-dinner walking cuts blood glucose ~23 mg/dL. ({N} steps to goal)"
```

---

## Push Notification Schedule

All scheduled via `UNUserNotificationCenter`. No remote push. All categories user-toggleable in Settings.

| Category | Time | Condition | Example |
|----------|------|-----------|---------|
| Morning routine | 7:30 AM | Every day | "Good morning. 10k steps today is your #1 cardiovascular lever." (Circuit) / "Good morning. Hit protein before noon and you've front-loaded your MPS window." (Build) |
| Midday check-in | 12:00 PM | Steps < 3k by noon | "Steps are low. A 10-min post-lunch walk drops blood glucose 23 mg/dL and adds ~1,200 steps." |
| Protein reminder | 2:00 PM | Protein < 40% of daily target by 2 PM | "You're behind on protein. Front-load before dinner to hit your target without cramming at night." |
| Evening summary | 8:30 PM | Daily | "[N] steps, [X] cal logged. [Streak message if applicable]." |
| Step nudge | 6:00 PM | Steps < 70% of goal | "{N} steps so far. A 20-min walk after dinner would bring you to goal and improve tonight's insulin response." |
| Weekly summary | Sunday 7:00 PM | Weekly | "This week: [avg steps] avg steps, [N] workouts, [streak] week streak. [Weight/marker trend one-liner]." |
| Milestone | Immediate (on unlock) | After logging | "You hit [milestone]. [Science one-liner]." |
| Stall nudge | 9:00 AM | No log in 2+ days | "Two days without a log. Start small — one set or 500 steps. The streak is worth protecting." |

### Push Notification Infrastructure (NotificationService.swift)

```swift
// Services/NotificationService.swift

actor NotificationService {
    static let shared = NotificationService()

    func requestPermission() async -> Bool
    func isAuthorized() async -> Bool
    func schedule(_ notification: ScheduledNotification) async
    func cancelCategory(_ category: NotificationCategory) async
    func cancelAll() async
}

struct ScheduledNotification {
    let id: String
    let title: String
    let body: String
    let trigger: UNNotificationTrigger    // UNCalendarNotificationTrigger or UNTimeIntervalNotificationTrigger
    let category: NotificationCategory
}

enum NotificationCategory: String, CaseIterable {
    case morningRoutine
    case middayCheckIn
    case proteinReminder
    case eveningSummary
    case stepNudge
    case weeklySummary
    case milestone
    case stallNudge
}
```

Permission requested once: after profile creation in the onboarding flow. Same explicit-user-action pattern as HealthKit (never from `.task`/`.onAppear`).

---

## UI Components

### 1. MilestoneChip (inline, below cards)

A capsule that appears transiently below the relevant card when a milestone is hit. Tappable to open EncouragementSheet.

```swift
// Components/MilestoneChip.swift
// Capsule, themed tint, SF symbol + headline, tap → sheet
// Shown for ~8s then fades. If sheet opened, persists until dismissed.
```

Placement:
- Below `StepsCardioCard` (step milestones, streak milestones)
- Below each exercise card in WorkoutsView (volume milestones)
- Below `PilatesCard` (session + streak milestones)
- Below `MacroQuadGrid` (macro goal hits)

### 2. EncouragementSheet (medium-detent, themed background)

```swift
// Components/EncouragementSheet.swift
// .sheet with .presentationDetents([.medium])
// .presentationBackground(theme.bg)
// Shows: headline (large), detail paragraph, optional science line (small, secondary color),
//        optional call-to-action button (TactileButtonStyle.primary)
```

Triggered by tapping MilestoneChip or from within ToastView (via existing ⓘ button pattern).

### 3. ProjectionBar (inline strip)

```swift
// Components/ProjectionBar.swift
// Small horizontal strip with icon + text
// Sits BELOW action button (e.g. "Log Set") in workout cards
// Hidden when projection string is nil
// No tap target — informational only
// Uses .caption font, theme.accent2 color
```

Example rendering:
```
🔥  6 more sets this week → lat MEV unlocked
📊  12 more reps → ~14 cal burned today (total 287 cal)
```

---

## Settings — Notification Controls

Inside `SettingsView.swift`, a new `"Notifications"` row opens `NotificationSettingsView`. One toggle per `NotificationCategory`. Prefs stored in `@AppStorage("notif.<category>.<profileId>")`.

```
Notifications
  ✅ Morning routine                7:30 AM
  ✅ Midday check-in               12:00 PM (step-conditional)
  ✅ Protein reminder               2:00 PM (if behind target)
  ✅ Evening summary                8:30 PM
  ✅ Step nudge                     6:00 PM (if behind goal)
  ✅ Weekly summary                 Sundays 7:00 PM
  ✅ Milestone alerts               Immediately after logging
  ✅ Streak nudges                  If gap ≥ 2 days
```

---

## Trigger Wiring (where in existing views)

| Existing file | New trigger site | What fires |
|---------------|-----------------|------------|
| `StepsCardioCard` | `onChange(of: todaysSteps)` (already exists) | Step milestone MilestoneChip + Toast |
| `WorkoutsView` — after set logged | after `Repos.logSet()` success | ProjectionBar update + optional MilestoneChip (volume threshold) |
| `TodayView` — MacroQuadGrid | `onChange(of: dailyTotals.calories)` when ≥ 90% goal | "Almost there" approaching toast |
| `TodayView` — MacroQuadGrid | `onChange(of: dailyTotals.proteinG)` when ≥ 100% goal | "Protein locked" win toast |
| `PilatesCard` | after `Repos.logPilatesSession()` | Pilates milestone + MilestoneChip |
| `NutritionView` — food log | after `Repos.logFood()` when protein gap > 20g and time > 8 PM | Evening protein nudge toast |
| `ProgressTabView` | after marker logged via marker detail sheet | Marker improvement or stall message |
| `OurFitnessApp.swift` — post profile creation | after `Repos.createProfile()` succeeds | `NotificationService.requestPermission()` — single call, never repeated |

---

## Stall Detection Logic (Domain)

```swift
// In EncouragementEngine

static func detectStalls(
    steps: [StepCountDTO],
    sets: [WorkoutSetDTO],
    pilates: [PilatesSessionDTO],
    markers: [HealthMarkerDTO],
    now: Date
) -> [EncouragementTrigger]
```

Stall thresholds:
- **Steps gap**: no `StepCountDTO` with `steps > 500` for 2+ days → `logGap(.steps, 2)`
- **Workout gap**: no `WorkoutSetDTO` in 5+ days (Build) or 7+ days (Reset) → `logGap(.workout, N)`
- **Pilates gap**: Reset mode, no `PilatesSessionDTO` in 7+ days → `logGap(.pilates, 7)`
- **BP/LDL stall**: same-kind markers over last 6 weeks show delta < 5% → `markerStall(kind, weeks)`
- **Weight stall**: Reset mode, 14-day weight trend < 0.1 lb/week → `weightTrend(0.0, .circuit)` → `TrendAdjustment.addCardio` copy

Called from:
1. Background task (UNBackgroundTaskScheduler, minimal) — triggers stall push notification
2. TodayView `.task` — surfaces a stall Banner at top of Today if stall detected since last check

---

## Phased Implementation

### Phase 1 — Toast + Projection (no push, no new UI components)
- `Domain/EncouragementMessage.swift` + `Domain/EncouragementEngine.swift` (pure, testable)
- 8 new toast constructors in `ToastCenter.swift`
- Wire toasts in `WorkoutsView`, `TodayView`, `PilatesCard`, `StepsCardioCard`
- `ProjectionBar.swift` component
- Wire ProjectionBar below exercise log button in `WorkoutsView`
- Wire step projection in `StepsCardioCard`
- Unit-test `EncouragementEngine` in `OurFitnessTests` (pinned `now`)

### Phase 2 — MilestoneChip + EncouragementSheet
- `Components/MilestoneChip.swift`
- `Components/EncouragementSheet.swift`
- Wire chip appearances to volume/streak milestones in WorkoutsView + StepsCardioCard + PilatesCard
- Wire sheet trigger from chip tap

### Phase 3 — Push Notifications
- `Services/NotificationService.swift`
- `Features/Settings/NotificationSettingsView.swift`
- Request permission in post-profile-creation screen
- Schedule morning/midday/evening/weekly notifications on profile creation
- Schedule dynamic notifications after stall detection
- Wire milestone notifications immediately post-log action

### Phase 4 — Stall Detection + Weekly Summary
- `EncouragementEngine.detectStalls()` 
- Weekly summary push (Sunday cron via UNCalendarNotification)
- Stall Banner in TodayView
- Progress tab "insight strip" — one sentence trend reading at top of ProgressTabView

---

## Science Reference — Key Numbers for Copy

These are embedded in the message banks above. Listed here as a quick lookup for copy verification:

| Claim | Source | Number |
|-------|--------|--------|
| Steps: mortality reduction per 1k steps | Saint-Maurice, JAMA 2020; Paluch 2021-22 meta | ~12% per 1,000 steps |
| Steps: 8k vs 4k all-cause mortality | Saint-Maurice 2020 | 51% lower |
| Steps: systolic BP per 1k steps | PMC 2021 | −0.49 mmHg systolic |
| Walk 13.5k/day × 12 wks: BP reduction | PMC 10455876 | −10.2 mmHg systolic |
| 10-min stair walk: glucose | ScienceDirect stair study | −23 mg/dL |
| Pilates: systolic BP | J Human Hypertension, 2024 meta | −4.76 mmHg |
| Pilates: diastolic BP | J Human Hypertension, 2024 meta | −3.43 mmHg |
| Pull-up frequency: lat thickness | Sports Medicine 2020 | +14% (3x/wk vs 1x) |
| Hypertrophy MEV | RP Strength; multiple meta-analyses | 4–8 sets/muscle/week |
| Hypertrophy MAV | RP Strength; Schoenfeld | 10–20 sets/muscle/week |
| Visible gains timeline | CyVigor; Muscle Engineered | 8–12 weeks |
| LDL reduction (aerobic, 12 wks) | PMC 2021 | ~5% |
| HDL increase (aerobic, 12 wks) | MDPI 2023 | ~4.6% |
| Triglyceride reduction (consistent) | PMC 2021 | 30–40% |
| Aerobic: chronic systolic BP reduction | JAHA 2022; PMC meta | −5–8 mmHg |
| Diabetes risk reduction (150 min/wk) | DPP; NEJM 2002 | 58% (lifestyle intervention) |
| Leucine threshold for MPS | Modern Med Life | 2.5–3g/meal |
| Optimal protein per meal | Macros Inc; Body Blueprint | 0.4–0.55 g/kg |
| Soluble fiber: LDL reduction | Nourished by Science | 5–11 pts per 5–10g/day |
| Modest deficit: muscle preservation | Bolt Pharmacy; PMC 11327213 | 300–500 kcal/day |
| Pilates core strength timeline | MDPI 2025; Sage 2021 | 6–8 weeks measurable |
| Deload frequency | LoadMuscle; Jacked | Every 4–8 weeks |

---

## Test Coverage (Domain only — hostless target)

```swift
// OurFitnessTests/EncouragementEngineTests.swift
// Pinned now: 2026-05-27T12:00:00Z (Wednesday mid-week)

func testStepMilestone3k_buildMode()
func testStepMilestone10k_circuitMode_differentCopy()
func testRepProjection_pullUps_bodyWeight180()
func testMEVThreshold_6sets_latsUnlocked()
func testMAVThreshold_12sets_impressed()
func testStallDetection_noSteps2Days()
func testMarkerImproved_systolicDrop5mmHg()
func testWeightTrend_circuitStall_addCardioNudge()
func testProgressiveOverloadOpportunity_sameWeightThreeSessions()
func testPilatesMilestoneWeek8_impressedTone()
```

---

## What This Doesn't Do

- No gamification (points, badges, leaderboards) — not the app's personality
- No social comparison — one profile per install
- No AI-generated copy at runtime — all strings pre-authored, consistent, science-backed
- No background HealthKit polling that could trigger the SIGABRT trap — stall detection reads from SwiftData (already synced)
- No 6th button variant

---

*Ready for Phase 1 implementation whenever you are.*
