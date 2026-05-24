# Nutrition Plan — Research & Spec

**Purpose:** Handoff document for an agent building the nutrition module of a fitness tracking app. This consolidates the nutrition logic, data model, food library, design direction, and integration notes so the next agent can scaffold the feature without re-deriving any of it.

**Status:** Research complete. Ready for implementation.

---

## 1. Product Concept

A nutrition companion that lives alongside the fitness/basketball tracking side of the app. Users set a goal — and that goal **changes** what the app suggests, how it computes targets, and how it nudges intake throughout the day. Suggestions are personalized to user-declared food preferences (a "foods I like" list) and constraints (allergies, dietary restrictions, budget).

Core differentiation: this is not a generic calorie counter. It works *with* picky eaters, allergy-restricted users, and people who don't have a strong appetite — by leaning on calorie-dense liquids, frequency-based eating, and foods the user already likes.

### Primary use cases

1. **Underweight / hardgainer** trying to eat enough → emphasize liquid calories, frequency anchors, calorie multipliers
2. **Athlete maintaining** with performance goals → balance macros around training windows, post-workout protein
3. **Weight loss** with satiety priority → flip the logic: emphasize volume foods, lean proteins, fiber
4. **Picky eater / allergy-restricted** → strict food allow-list, never suggest excluded items

### Non-goals (initial version)

- Medical nutrition therapy (diabetes, kidney disease, etc.)
- Eating disorder support features
- Restaurant scanning / barcode lookup (v2)
- Social/sharing features

---

## 2. Goal-Driven Logic

The user's selected goal is the primary input that bends every other calculation and suggestion.

### Goal types

| Goal | Calorie strategy | Protein g/lb | Suggestion bias |
|---|---|---|---|
| Gain lean mass | TDEE + 400–600 | 1.0 | Calorie-dense, liquid-friendly, frequent anchors |
| Maintain + perform | TDEE | 0.8–1.0 | Balanced macros, training-window timing |
| Eat consistently | TDEE (or +200 if underweight) | 0.7–0.8 | Frequency over volume, "easy wins" |
| Lose fat | TDEE − 300–500 | 1.0–1.2 | High volume, high fiber, lean proteins |
| Sport performance | TDEE + activity bonus | 0.9 | Carb timing around sessions |

### Calorie calculation

Use Mifflin-St Jeor for BMR, then multiply by activity factor:

```
BMR (male)   = 10 × kg + 6.25 × cm − 5 × age + 5
BMR (female) = 10 × kg + 6.25 × cm − 5 × age − 161

Activity multipliers:
  Sedentary       1.2
  Light (1–2x/wk) 1.375
  Moderate (3–5x) 1.55
  Active (6–7x)   1.725
  Very active     1.9

TDEE = BMR × activity multiplier
Daily target = TDEE + goal adjustment
```

### Macro split (default, overridable per goal)

- **Protein:** g/lb × bodyweight (see table above)
- **Fat:** 25–30% of calories
- **Carbs:** remainder

For sport-performance goal, push carbs higher (45–55% of cals) and fat lower.

### Hunger / appetite override

A user-declared "low appetite" flag should change suggestion ranking:
- Boost smoothies, shakes, chocolate milk, calorie-multiplied versions of meals
- Surface "drink your calories" suggestions first
- Suggest more eating anchors (5+ instead of 3 meals)
- Add calorie-multiplier nudges ("add a tbsp of olive oil to that rice — +120 cal, no extra volume")

---

## 3. Personalization Inputs

Required at onboarding:

- Height, weight, age, sex
- Activity level (or pull from fitness side of app)
- Goal (one of the types above)
- **Food preferences:** allow-list of liked foods (free-form tags or pick from library)
- **Allergies / restrictions:** strict deny-list (nuts, dairy, gluten, shellfish, etc.) — these *override everything*
- Optional: budget cap per week, low-appetite flag

The food preferences list is the most important non-obvious input. The app should treat this as the source of truth for suggestions — never suggest a food not on the user's list (unless they explicitly ask for "expand my horizons" mode).

### Allergy handling (critical)

- Deny-list is strict. Every suggested meal must be checked against it.
- Tag every food in the library with an `allergens: []` array.
- Hide, do not just filter — the user should never see a suggestion they can't eat.
- Display a persistent banner confirming active restrictions so users trust the app.

---

## 4. Food & Meal Library

The library is the engine. Each item has macros, cost estimate, cook complexity, and tags for filtering.

### Schema

```ts
type Food = {
  id: string;
  name: string;
  category: 'smoothie' | 'breakfast' | 'main' | 'snack' | 'drink' | 'side';
  recipe: string;              // plain-language prep
  servings: number;
  per_serving: {
    calories: number;
    protein_g: number;
    carbs_g: number;
    fat_g: number;
    fiber_g?: number;
  };
  cost_usd: number;            // per serving, US grocery average
  cost_tier: 'low' | 'mid' | 'high';
  prep_minutes: number;
  cook_complexity: 'none' | 'easy' | 'medium' | 'hard';
  allergens: string[];         // ['dairy', 'gluten', 'eggs', 'soy', ...]
  ingredients: string[];       // for grocery list generation
  tags: string[];              // ['high-protein', 'liquid', 'post-workout', 'cheap', ...]
  appetite_friendly: boolean;  // good for low-appetite users
  goal_fit: string[];          // which goals this serves
};
```

### Categories to seed

1. **Smoothies & shakes** — the most important category for low-appetite & gain goals
2. **Breakfast / post-workout** — high-protein morning options
3. **Mains** — lunch & dinner
4. **Snacks & anchors** — between-meal calorie holders
5. **Sides** — modular additions to bump macros
6. **Calorie multipliers** — oils, honey, butter, oats, cheese (additive, not standalone)

### Seed library (built from research; expand as needed)

Below is the validated seed set used in the prototype. All are nut-free and use grocery items widely available in US urban areas. Costs are US averages, early 2026.

#### Smoothies

| Name | Cal | P | C | F | Cost | Notes |
|---|---|---|---|---|---|---|
| Anchor Smoothie | 720 | 38 | 110 | 9 | $2.10 | Milk + whey + banana + frozen berries + mango + honey + oats |
| Chocolate Mango Lift | 540 | 35 | 80 | 7 | $1.85 | Chocolate milk + whey + banana + mango |
| Mass Builder | 1050 | 60 | 145 | 14 | $3.20 | The "I didn't eat enough" emergency shake |
| Bedtime Casein-Style | 520 | 32 | 75 | 8 | $1.60 | Slow-digesting, thicker |
| Tropical Recovery | 480 | 28 | 92 | 3 | $2.40 | OJ-based, best 60min post-workout |

#### Breakfast / post-workout

| Name | Cal | P | C | F | Cost |
|---|---|---|---|---|---|
| Spam, Egg & Rice | 780 | 40 | 65 | 38 | $2.20 |
| Bagel Stack | 720 | 32 | 75 | 32 | $2.50 |
| Oatmeal Power Bowl | 640 | 32 | 105 | 11 | $1.40 |
| Pancake Stack + Eggs | 890 | 30 | 115 | 32 | $2.10 |
| Cereal Mega Bowl | 620 | 35 | 95 | 14 | $1.50 |
| Jelly Toast + Eggs | 580 | 22 | 78 | 22 | $1.30 |

#### Mains

| Name | Cal | P | C | F | Cost |
|---|---|---|---|---|---|
| Chicken Katsu Rice Bowl | 780 | 45 | 85 | 28 | $3.80 |
| Spam Fried Rice | 820 | 32 | 92 | 36 | $2.40 |
| Salmon + Rice + Broccoli | 680 | 42 | 55 | 32 | $5.20 |
| Brisket Rice Bowl | 820 | 38 | 75 | 38 | $4.50 |
| Penne Vodka Plate | 740 | 22 | 110 | 24 | $2.80 |
| Ravioli Bowl | 650 | 26 | 88 | 22 | $3.20 |
| Burger + Fries | 920 | 40 | 78 | 48 | $3.60 |
| Chicken Nugget Combo | 780 | 32 | 72 | 38 | $3.10 |
| Cup Noodles Upgrade | 580 | 22 | 65 | 24 | $1.80 |
| Fried Rice + Plantains | 760 | 14 | 125 | 22 | $2.50 |
| Pizza Night | 950 | 38 | 110 | 38 | $5.00 |

#### Snacks

| Name | Cal | P | C | F | Cost |
|---|---|---|---|---|---|
| Popcorn + Chocolate Milk | 480 | 14 | 70 | 14 | $1.20 |
| Sunflower Seed Pack | 270 | 9 | 8 | 24 | $1.00 |
| Banana + Honey + Crackers | 380 | 5 | 78 | 7 | $0.80 |
| Donut + Chocolate Milk | 510 | 12 | 75 | 20 | $2.20 |
| Bagel + Jelly | 450 | 10 | 88 | 8 | $1.40 |
| Berry Bowl + Whey Milk | 320 | 28 | 35 | 7 | $2.10 |
| Hush Puppies + Honey | 440 | 8 | 62 | 18 | $1.60 |
| Fried Pickle / Plantain Plate | 380 | 4 | 48 | 18 | $1.50 |

### Calorie multipliers (additive)

These are cheap, dense, and can be tacked onto any meal to bump calories without adding bulk:

- Olive oil — 1 tbsp = 120 cal, ~$0.12
- Honey — 1 tbsp = 60 cal, ~$0.10
- Butter — 1 tbsp = 100 cal, ~$0.10
- Oats — ½ cup dry = 150 cal, ~$0.08
- Whey scoop — 25 g protein, ~$0.50
- Whole milk swap — +60 cal/cup vs skim

App should surface these as "boost this meal" suggestions when the user is under target.

---

## 5. Daily Structure & Suggestion Logic

### The 5-anchor model (for low appetite / gain goals)

Default to 5 eating slots per day rather than 3 meals:

1. **Pre-workout** — light carbs, easy on stomach (banana + milk)
2. **Post-workout** — the heaviest, most protein-forward meal (this is the magic window)
3. **Lunch** — warm, filling, moderate
4. **Mid-afternoon anchor** — easy snack or shake, never skip
5. **Dinner** — flexible, often what the user "wants"

For 3-meal users (typical appetite), collapse to breakfast/lunch/dinner with optional snacks.

### Suggestion algorithm (sketch)

```
function suggestMeal(user, slot, remainingMacros) {
  candidates = library
    .filter(f => !f.allergens.some(a => user.restrictions.includes(a)))
    .filter(f => f.ingredients.every(i => user.foodPreferences.includes(i)))
    .filter(f => f.category matches slot)
    .filter(f => f.goal_fit.includes(user.goal));

  if (user.lowAppetite) {
    candidates = candidates.filter(f => f.appetite_friendly);
  }

  if (user.budgetTight) {
    candidates = candidates.filter(f => f.cost_tier !== 'high');
  }

  // Score by macro fit to remaining targets
  return candidates
    .map(f => ({ ...f, score: macroFitScore(f, remainingMacros) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, 5);
}
```

`macroFitScore` rewards meals whose macro ratios match what the user still needs to hit for the day — e.g. if they're behind on protein but at carb target, surface higher-protein options.

### Post-workout window

If the fitness side of the app logs a workout, surface a post-workout suggestion within 60 minutes. Prioritize:
- 20–40g protein
- 40–80g carbs
- Liquid form if low-appetite user

---

## 6. Tracking & Progress

### Daily log

Standard food log: user adds entries from library or custom. Track per-day rollups of cal/p/c/f and visualize against targets.

### Progress signals

- **Bars turn green at 95–105% of target.** Red over 110%.
- **Weekly weight trend** is the primary success metric for gain/loss goals — not daily.
- **Adherence streak** — how many days in a row the user hit at least 80% of calorie target. This rewards consistency over perfection.

### Auto-adjustment

After 14 days, if weight trend ≠ goal direction at expected rate:

- Gain goal stalled → suggest +200 cal/day (one extra smoothie scoop + honey tbsp)
- Loss goal stalled → suggest −150 cal/day (drop one calorie multiplier)
- Gain too fast → drop oil multipliers
- Loss too fast → add back complex carbs

Surface these as suggested adjustments, not automatic changes. User confirms.

---

## 7. Grocery List Generation

A weekly grocery list can be auto-generated from selected meals.

```
function generateGroceryList(plannedMeals) {
  ingredients = plannedMeals.flatMap(m => m.ingredients);
  // dedupe, sum quantities, categorize
  return groupBy(ingredients, ingredient.category);
}
```

Group output by store section (Proteins / Carbs / Dairy / Produce / Pantry / Snacks). Show running cost total. Pull pricing from a regional average table; let user override with their own price if desired.

---

## 8. Design Direction

### Typography

**Use `Fraunces` (serif) as the primary typeface across the app.** Pair with a single mono accent font (`JetBrains Mono`) only for numerical readouts (calories, macros, prices) and small labels.

Avoid mono-heavy, terminal-style aesthetics. The previous prototype leaned too "robotic" — the new direction is editorial, warm, human. Think food magazine, not dashboard.

- **Display:** Fraunces, weight 600–800, opsz variable (use larger optical size for big headlines)
- **Body:** Fraunces, weight 400, comfortable line-height (1.6)
- **Numbers / labels:** JetBrains Mono in small sizes only, for stat readouts where alignment matters

### Color palette

Warm, food-forward. Suggested:
- Background: cream / off-white (`#f7f3ec`) or warm dark (`#1a1614`) for dark mode
- Primary text: deep brown-black (`#1a1614`)
- Accent: warm orange (`#d97742`) or amber — evokes food, energy, appetite
- Secondary: muted green (`#7fb069`) for success / on-target
- Warning: rust red (`#c44536`) for over-target / allergy alert

Avoid: cold blues, slate grays, neon. This is about food and warmth.

### Layout

- Generous whitespace
- Editorial spacing — larger type, more breathing room than a typical dashboard
- Meal cards as the primary unit; treat them like a recipe book
- Use real food photography or warm illustrations if assets are available; avoid clipart

### Components needed

- Meal card (name, recipe, macros, cost tier, allergen tags, "log this" button)
- Daily ring/bars for cal/p/c/f progress
- Anchor schedule (timeline view of the day's 5 slots)
- Food preference picker (multi-select, tag-style)
- Allergy banner (persistent, dismissible per session)
- Weekly view (7 days, each with planned meals)
- Grocery list (categorized, with running total)
- Settings: goals, restrictions, budget cap

---

## 9. Data Model Summary

```ts
type User = {
  id: string;
  profile: {
    height_in: number;
    weight_lb: number;
    age: number;
    sex: 'male' | 'female';
    activity_level: 'sedentary' | 'light' | 'moderate' | 'active' | 'very_active';
  };
  goal: 'gain' | 'maintain' | 'consistency' | 'lose' | 'performance';
  food_preferences: string[];      // ingredient/food tags user likes
  restrictions: string[];          // allergens / forbidden items
  low_appetite: boolean;
  budget_weekly_usd?: number;
  computed_targets: {
    calories: number;
    protein_g: number;
    carbs_g: number;
    fat_g: number;
  };
};

type LogEntry = {
  id: string;
  user_id: string;
  date: string;                     // ISO date
  slot: 'pre' | 'post' | 'lunch' | 'snack' | 'dinner' | 'other';
  food_id?: string;                 // ref to library, or...
  custom_name?: string;             // ...free-form
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
};

type DailySummary = {
  user_id: string;
  date: string;
  totals: { calories, protein_g, carbs_g, fat_g };
  hit_targets: boolean;
  adherence_score: 0..1;
};
```

---

## 10. Integration with Fitness Side

The nutrition module should read from and write to the fitness side of the app:

- **Read workouts:** when a workout is logged, trigger a post-workout meal suggestion within the 60-minute window
- **Read activity level:** auto-update TDEE if the user's weekly training frequency changes
- **Write training-day calorie target:** push higher targets on heavy training days; lower on rest days (auto-cycling)
- **Shared user profile:** height, weight, age, sex are one source of truth

Suggested shared events:
- `workout.completed` → triggers post-workout suggestion
- `workout.scheduled` → triggers pre-workout reminder + meal
- `weight.logged` → recomputes TDEE & target

---

## 11. Build Priorities (suggested order)

1. **User onboarding flow** — profile, goal, preferences, restrictions
2. **Target calculation engine** — TDEE + macro split logic
3. **Food library + schema** — seed the data, build the model
4. **Suggestion algorithm** — filter + score + rank
5. **Daily log + progress UI** — the core daily experience
6. **Weekly planner** — drag-or-tap meals into days
7. **Grocery list generator** — derive from planner
8. **Fitness integration hooks** — workout-aware suggestions
9. **Auto-adjustment engine** — 14-day trend → calorie nudge

---

## 12. Things to Avoid

- **Generic suggestions** that ignore the user's food preferences ("here's a kale salad" for someone who said they don't eat greens)
- **Cold, clinical UI** — this is food, make it feel like food
- **Daily perfection framing** — emphasize weekly trends and adherence streaks instead of daily pass/fail
- **Hidden allergens** — every suggestion must be allergen-checked, every screen should confirm active restrictions
- **Calorie shaming** — the app supports users who *struggle to eat enough* just as much as those eating too much. Tone should never imply restriction is the default goal.

---

## 13. Open Questions for Next Agent

- Persistence layer? (local-only, Supabase, Firebase, custom backend?)
- Mobile-first or responsive web?
- Account system or anonymous local storage?
- Do we want meal photography? Source from a stock API or illustrate?
- Should the grocery list integrate with Instacart / AmazonFresh APIs?
- Do we want a "social" angle (share meal plans) or stay private?

---

**End of spec.** Hand to next agent for implementation.
