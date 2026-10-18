# Map: UI components

Shared components and services used across tabs: buttons, rings, info sheets, goal picker, haptics, toasts, freshness, muscle names.

> Rows describe current code. **Update the matching row in the same commit as the code it describes** — a stale row is worse than none. Index of all maps: [../../CLAUDE.md](../../CLAUDE.md) → "Find it fast".

## Design rules (full)

CLAUDE.md keeps the short version; this is the original text, moved verbatim.

- **One palette for everyone:** warm light, sage/terracotta — `Theme.standard` in `Services/Theme.swift`, the `\.theme` environment default (no per-view theme application). `Info.plist` `UIUserInterfaceStyle = Light`; `AccentColor` / `LaunchBackground` in the asset catalog and the widget's Live Activity palette (`OurFitnessWidgets/LiveSessionLiveActivity.swift`) mirror it — keep them equal when retuning
- **"cal" not "kcal"** in all UI strings
- Every interaction: state change + spring animation + haptic + (wins) toast

| Surface | Shape |
|---|---|
| `Card`, `PressableCard`, `MacroQuadGrid` cells | `RoundedRectangle(cornerRadius: 16, style: .continuous)` |
| Inline card borders | `RoundedRectangle(cornerRadius: 12, style: .continuous)` |
| Primary / secondary buttons | `cornerRadius: 10` |
| Pill buttons | `cornerRadius: 20` |
| `ProgressBar` | `Capsule()` track, fill `cornerRadius: 3` |

- Sheet backgrounds: `.presentationBackground(theme.bg)` not `.background(theme.bg.ignoresSafeArea())`
- ⓘ buttons: `.sheet` with `.presentationDetents([.medium])`, never `.popover`
- Numeric keyboards: `ToolbarItemGroup(placement: .keyboard)` with Done button

## Components and services

| Goal | File(s) |
|---|---|
| **UI / Components** | |
| Button variants (5 total) | `Components/TactileButtonStyle.swift` — never add a 6th. Decorative layers (`GlareSweep`) stay `.accessibilityHidden` — the off-screen glare once inflated every primary button's accessibility frame, so VoiceOver boxes and UI-test taps landed beside the button. Primary labels render uppercased (`textCase`), so UI tests match labels case-insensitively |
| Circular progress | `Components/ProgressRing.swift` — never inline `Circle().trim` |
| ⓘ info-sheet chrome | `Components/InfoSheet.swift` → `InfoSheetScaffold(title:subtitle:titleSize:dragIndicator:detents:)` (`detents` defaults to `[.medium, .large]`; pass `[.large]` for a sheet long enough that medium reads as truncated — Nutrition goals does) + `InfoSection`, `InfoBody`, `InfoFootnote`, `InfoRow(label:detail:emphasis:)`, `InfoCalcRow(label:detail:labelWraps:)`, `InfoMetricRow`, `InfoHeroStat`, `Bullet(_:marker:)`. Carries chrome only — all copy/numbers/citations stay at the call site. Never re-roll a private `infoSection`/`calcRow`/`bullet` helper |
| Goal-picker wheel sheet | `Components/GoalPickerSheet.swift` → `GoalPickerSheet(title:subtitle:wheels:wheelVerticalPadding:resetLabel:detents:onReset:onSave:)`; `[Wheel]` so steps can show a second days/week wheel. Fires the Save success haptic itself |
| Progress-fill replay (sweep from 0 on appear) | `Components/VisibilityReveal.swift` → `.revealOnAppear($reveal)` — resets to 0 on scroll-out, springs to full on re-entry. Used by `ProgressBar` + `MacroQuadGrid` (`pct * reveal`) |
| Haptics | `Services/Haptics.swift` |
| Toast | `Services/ToastCenter.swift` + `Components/ToastView.swift` — `show(_:for:)` for a `Toast`, `show(_:accent:for:)` for an `EncouragementMessage` (every encouragement wrapper is a one-liner over it). `show` fires the outcome haptic itself: never call `Haptics.*` right before it |
| Scroll haptics | `Services/Haptics.swift` → `.scrollHapticTicks()` on top-level tab `ScrollView`s |
| Freshness timestamp | `Domain/Freshness.swift` → `label(for:now:staleAfter:)` |
| Plain-English muscle names | `Domain/ExerciseInfo.swift` → `plainName(forMuscle:)` / `muscleGlossary` |
