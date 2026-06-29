# Bottom Nav Bar — Implementation Notes

This is a deceptively simple bar. Most of what makes it look polished isn't custom code — it's stock SwiftUI `TabView` + SF Symbols + a single tinted accent color from the theme system. There's almost no styling code to copy because there's almost no styling code in the first place.

Source: [OurFitness/App/RootView.swift](OurFitness/App/RootView.swift) lines 8–29 (the `Tab` enum) and lines 82–108 (the `appShell` builder).

---

## What's actually on screen

```
┌──────────────────────────────────────────┐
│           [tab content area]             │
│                                          │
├──────────────────────────────────────────┤
│   ☀️         🍴          🏋️         📈     │  ← SF Symbols, monochrome
│  Today    Library     Train    Progress  │  ← short verb-noun labels
└──────────────────────────────────────────┘
```

Selected tab: icon + label render in **theme accent color** (warm orange on Build, sage green on Circuit). Unselected tabs: system gray (handled automatically by `TabView`). Background: system default — a translucent material layer that automatically adapts to light/dark mode and content scrolling underneath. We don't draw any of that ourselves.

A faint haptic tick fires on tab change via `.sensoryFeedback(.selection, trigger: tab)`.

---

## The whole implementation

There are exactly two pieces.

### 1. The `Tab` enum (one source of truth per tab)

```swift
private enum Tab: String, CaseIterable, Identifiable {
    case today, nutrition, workouts, progress
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today:     return "Today"
        case .nutrition: return "Library"
        case .workouts:  return "Train"
        case .progress:  return "Progress"
        }
    }

    var icon: String {
        switch self {
        case .today:     return "sun.max"
        case .nutrition: return "fork.knife"
        case .workouts:  return "dumbbell"
        case .progress:  return "chart.line.uptrend.xyaxis"
        }
    }
}
```

Each case owns its label string and its SF Symbol name. Adding a new tab is two lines (a new case + two switch arms) plus one new `.tabItem` block below.

### 2. The `TabView` wiring

```swift
TabView(selection: $tab) {
    TodayView(profile: profile, health: health)
        .tag(Tab.today)
        .tabItem { Label(Tab.today.label, systemImage: Tab.today.icon) }

    NutritionView(profile: profile)
        .tag(Tab.nutrition)
        .tabItem { Label(Tab.nutrition.label, systemImage: Tab.nutrition.icon) }

    WorkoutsView(profile: profile)
        .tag(Tab.workouts)
        .tabItem { Label(Tab.workouts.label, systemImage: Tab.workouts.icon) }

    ProgressTabView(profile: profile)
        .tag(Tab.progress)
        .tabItem { Label(Tab.progress.label, systemImage: Tab.progress.icon) }
}
.tint(Theme.for(profile.mode).accent)
.sensoryFeedback(.selection, trigger: tab)
```

That's it. No `UITabBarAppearance` proxy, no custom shapes, no `safeAreaInset` overlay, no `ZStack` floating bar. SwiftUI's native `TabView` plus three modifiers:

- `selection: $tab` — drives which screen is active from `@State private var tab: Tab = .today`
- `.tint(...)` — selected-item color
- `.sensoryFeedback(.selection, trigger: tab)` — the haptic tick on switch

---

## How easy is it to customize?

### Icons (very easy)

Change one string in the `icon:` switch. The icon is an SF Symbol name (Apple's free icon library — `sun.max`, `fork.knife`, `dumbbell`, etc.). Open the SF Symbols app on macOS to browse the ~6000 available glyphs, find a name, paste it in. They auto-tint, auto-scale for accessibility, and render correctly in light + dark mode without any extra work.

If you want **custom artwork instead of SF Symbols** (e.g. a llama silhouette), it's still one line — swap:

```swift
.tabItem { Label(Tab.today.label, systemImage: Tab.today.icon) }
```

for:

```swift
.tabItem { Label { Text(Tab.today.label) } icon: { Image("llama-icon-today") } }
```

…where `"llama-icon-today"` is an image set in `Assets.xcassets`. Include a template-rendered version so it picks up `.tint()` automatically (Asset Catalog → image → "Render As" → "Template Image"). Otherwise the image renders as full-color and `.tint()` is ignored.

Provide @1x / @2x / @3x slots in the asset catalog (or a single SVG marked "Preserves Vector Data") so it stays crisp on every device.

### Selected-tab color (one line)

```swift
.tint(Theme.for(profile.mode).accent)
```

`.tint(...)` is the single knob. Whatever `Color` you pass becomes the selected icon + label color. In Our-Fitness this comes from the per-mode theme system ([Services/Theme.swift](OurFitness/Services/Theme.swift)) — warm orange `(1.0, 0.42, 0.21)` on Build, sage green `(0.50, 0.63, 0.45)` on Circuit. To swap colors at runtime, change the value passed to `.tint()` and SwiftUI re-renders.

For Llamas-Cookbook you'd most likely hard-code a single accent — say cookbook-red — and just write:

```swift
.tint(Color("CookbookRed"))   // resolved from Assets.xcassets
```

or inline:

```swift
.tint(Color(red: 0.78, green: 0.27, blue: 0.20))
```

### Label text (one line per tab)

Edit the `label:` switch in the `Tab` enum. We deliberately use short verb-noun labels (Today/Library/Train/Progress) instead of generic nouns — feels more like a call to action and fits better at small dynamic-type sizes.

### Unselected tab color (a bit harder, but optional)

SwiftUI's `TabView` doesn't expose an unselected-tint modifier directly. If the default system gray isn't what you want, you have two options:

1. **`UITabBarAppearance` proxy** at app launch (in `OurFitnessApp.init`). Lets you set `stackedLayoutAppearance.normal.iconColor`, `selected.iconColor`, fonts, etc. Per-mode dynamic switching is awkward because `UITabBarAppearance` is global UIKit state, not SwiftUI-reactive.

2. **Custom tab bar overlay** — build your own `HStack` of buttons inside a `safeAreaInset(edge: .bottom)`, and hide the system bar with `.toolbar(.hidden, for: .tabBar)`. Gives total control over colors, materials, animation. But you give up: automatic accessibility behaviors, system-level transitions, edge-bleed materials. Not worth it unless you've outgrown stock styling.

For most apps option 1 is plenty.

### Bar background (rarely worth customizing)

Stock TabView uses a translucent material backdrop that's already what most apps want — it blurs whatever content scrolls under it, automatically adjusts for light/dark, automatically adjusts for content scroll position (sometimes goes fully transparent at top of a scroll view). Changing it is `UITabBarAppearance.configureWithOpaqueBackground()` + `.backgroundColor = ...`. We don't touch it in Our-Fitness.

### Haptic feedback (one line, very easy to add/remove)

```swift
.sensoryFeedback(.selection, trigger: tab)
```

Available values: `.selection`, `.impact`, `.success`, `.warning`, `.error`. Tied to any `Equatable` state via `trigger:`. Available iOS 17+.

---

## Porting checklist for Llamas-Cookbook

1. **Replicate the enum pattern.** One source of truth — `case` per tab, `label`/`icon` switches. Don't sprinkle hardcoded strings across `.tabItem` calls.
2. **Pick your icons.**
   - Path of least resistance: pure SF Symbols. Browse in the SF Symbols app, drop names into the `icon:` switch.
   - Branded path: custom `Image("…")` assets in `Assets.xcassets`, set to **Template Image** render mode so `.tint()` works.
3. **Pick your accent color.** If single-themed, hardcode `Color(...)` once in `.tint()`. If multi-themed (light/dark variants or seasonal swaps), put it in a `Theme` struct like Our-Fitness does and read `.tint(theme.accent)`.
4. **Add `.sensoryFeedback(.selection, trigger: tab)`** if you want the satisfying tick on switch. Iterate on which haptic feels right for cooking app vibes.
5. **Don't custom-build the bar unless you've proven the stock one isn't enough.** Material backdrop, accessibility, auto-layout for Dynamic Type, swipe-edge gestures — all free with `TabView`. Re-implementing them is multi-day work.

---

## What's deliberately NOT here

- No badge counts on icons (no notifications yet — Non-goal v1 per [CLAUDE.md](CLAUDE.md))
- No center "log" floating action button — we use a `PressableCard` inside Today instead, no overlay button needed
- No animated tab-switch transitions beyond the system default
- No tab reordering, no overflow "More" tab — four tabs is the cap, fits comfortably without crowding

If Llamas-Cookbook needs any of those, they're additive — none would require restructuring the base.
