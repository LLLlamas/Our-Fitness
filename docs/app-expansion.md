# App Expansion — From TestFlight Circle to App Store

> Status: **Phase 1 implemented** (single profile per install, at-will mode switching,
> per-profile `@Query` isolation). Phases 2 (iCloud/CloudKit sync) and 3 (store polish)
> are still planned. Captures the decisions and the work needed to take Our-Fitness from
> a shared-device TestFlight build to a per-user App Store release. Companion to
> [CLAUDE.md](CLAUDE.md).

---

## Context — why this exists

Our-Fitness started as a personal/household app for a small TestFlight circle, built
around a **shared-device** model: several profiles live in one store, and a "Whose
device is this?" avatar switcher (`Components/ProfileSwitcher.swift`) flips which one
the shell renders. There is no auth because "both households trust each other."

For the App Store the unit changes: **one person, one device (per Apple ID), their data
following them across their own devices.** This doc plans that shift.

### Decisions (locked with the user)

| Question | Decision |
|---|---|
| Per-user data model | **iCloud per-person** — SwiftData + CloudKit *private* database. Data syncs across that person's own devices. A backend is allowed if a feature needs one, but nothing here requires one, so we don't add one. |
| Mode switching | **Changeable at will, with a confirm step.** Switching Build↔Circuit recomputes targets and shows a confirmation sheet first. All logs are kept. |
| Profiles per install | **One profile per install.** Drop the multi-profile switcher. The device is one person. |

### The good news — most of this already exists

The app is already substantially per-profile. The audit found:

- Every log model already carries an owner key: `WorkoutSetModel.userId`,
  `FoodLogEntryModel.userId`, `BodyMetricModel.userId`, `HealthMarkerModel.userId`,
  `StepCountModel.userId`, `PilatesSessionModel.profileId`, `CardioSessionModel.profileId`,
  and custom `ExerciseModel.profileId` (see `Data/PersistenceModels.swift`).
- Repositories filter by that key (`Data/Repositories/Repositories.swift` — `listFoodLog`,
  `listBody`, `listMarkers`, `listSteps`, `exercises(forProfile:)`, etc.).
- Per-profile goals live in `AppStorage` keyed by profile id (`stepsGoal.<uuid>`,
  `stepsWeeklyDays.<uuid>`, `pilatesWeeklyGoal.<uuid>`).
- Macro targets are stored per-profile in `ProfileModel.targetsJSON` and computed by
  `Domain/Targets.compute(mode:vitals:)`.

So the work is **narrower than a rewrite**: fix two data-isolation leaks, make mode
mutable, collapse to one profile, then layer CloudKit sync and store-submission polish
on top.

---

## Phase 1 — Single profile + mode switching + isolation fixes

*Ships real value immediately. No CloudKit yet. Schema change is folded into Phase 2.*

### 1A. Collapse to one profile per install

Remove the shared-device switcher; keep first-launch creation.

- **`App/RootView.swift`**
  - `header(for:)` (lines 141–167): replace the `ProfileSwitcher(...)` avatar with a
    plain, non-switching avatar that opens Settings (or just keep the gear button).
    Drop `onSelect` / `onAddProfile`.
  - Remove the `showCreateProfile` add-profile `.sheet` (lines 116–125) and the
    `@State showCreateProfile`.
  - `active` (lines 47–52) stays — with one profile it resolves to `profiles.first`.
    Keep `activeProfileId` `AppStorage` so existing installs keep their selection.
- **`Components/ProfileSwitcher.swift`**: delete, or repurpose into a static
  `ProfileAvatar` button (no sheet, no "Whose device is this?" copy).
- **`Features/Onboarding/ProfileCreationView.swift`**: unchanged — still the
  first-launch flow. The `onCreate` callback in `RootView` (lines 70–77) still sets
  `activeProfileIdString`.

> Note: this does **not** delete the multi-profile *capability* in the data layer
> (userId/profileId scoping stays). It just removes the UI for hosting multiple people.
> That keeps the door open and makes the CloudKit migration cleaner.

### 1B. Make mode changeable at will (recompute + confirm)

Today mode is chosen once in `ProfileCreationView` and shown read-only in Settings
(`Features/Settings/SettingsView.swift:42` → `labeled("Mode", profile.mode.displayName)`).
There is no update path, though `ProfileModel.apply(_:)` already writes `modeRaw` +
`targetsJSON`.

- **`Data/Repositories/Repositories.swift`** — add:
  ```
  static func updateMode(_ ctx, profileId: UUID, to newMode: Mode) -> ProfileDTO?
  ```
  Fetch the `ProfileModel`, rebuild `Targets.ProfileVitals` from its stored vitals,
  recompute `Targets.compute(mode: newMode, vitals:)`, write `modeRaw` + `targetsJSON` +
  `updatedAt`, `save()`. If `newMode == .circuit`, call the existing **idempotent**
  `seedCircuitExercises(ctx, profileId:)` (lines 63–83).
- **`Features/Settings/SettingsView.swift`** — turn the "Mode" row into a tappable
  control that presents a **confirmation sheet** (`.presentationDetents([.medium])`,
  per CLAUDE.md ⓘ-sheet rule). The sheet:
  - Names the new mode and its personality (reuse `modeBlurb` copy).
  - Shows a **before → after targets preview** by calling `Targets.compute` for both
    modes (calories, protein, steps shift).
  - Confirm button calls `Repos.updateMode`, fires a toast (CLAUDE.md mutation rule)
    and `Haptics.success()`.
- **`App/RootView.swift`**: no change needed — theme already follows `profile.mode`
  via `.themed(profile.mode)` / `Theme.for(profile.mode)`, and `.onChange(of: profile.mode)`
  (lines 126–129) already bounces off the Train tab when Circuit hides it.

Logs are mode-agnostic and untouched. Seeded Circuit exercises are left in place if the
user switches back to Build (idempotent, harmless).

### 1C. Fix the two data-isolation leaks

Two views fetch **all** rows globally with a predicate-less `@Query`, then filter in
memory. Correct today only because there's effectively one profile — fragile, and wrong
the moment CloudKit merges data. Convert both to predicate-scoped queries with an
`init(profile:)`, matching the pattern already used in `TodayView` (lines 33–42),
`NutritionView` (lines 20–28), and `PilatesCard` (lines 32–38).

- **`Features/Progress/ProgressView.swift`** (~lines 13–29): `bodyModels`, `markerModels`,
  `stepModels` → `@Query` with `#Predicate { $0.userId == uid }`.
- **`Features/Workouts/WorkoutsView.swift`** (~lines 25–40): `exerciseModels` →
  `#Predicate { $0.profileId == uid }`; `setModels` → `#Predicate { $0.userId == uid }`.

---

## Phase 2 — iCloud sync (SwiftData + CloudKit private DB)

This is the largest lift because **CloudKit imposes hard schema constraints** that the
current models violate.

### CloudKit constraints to satisfy

1. **No `@Attribute(.unique)`** — CloudKit does not support unique constraints.
   `ProfileModel.id` is `@Attribute(.unique)` (`PersistenceModels.swift:14`). Must drop
   `.unique` (keep `id` as a normal indexed UUID; enforce uniqueness in app logic).
2. **Every attribute must be optional or have a default.** Audit all `@Model` classes for
   non-optional, non-defaulted stored properties — notably the required `userId`/`profileId`
   UUIDs and the various `*Raw` strings. Give each a default or make optional.
3. **Relationships must be optional and have inverses.** (Current models use loose UUID
   keys, not SwiftData relationships, so this is mostly about not regressing.)

### Work

- **New schema: `SchemaV4`** in `Data/Schema.swift` (never edit a shipped schema —
  CLAUDE.md rule). Register the same model set with the CloudKit-compatible changes above.
  Bump `AppSchema.current`. Because the live store currently opens V3 from a fresh URL
  with **no migration plan**, moving to CloudKit also means a fresh CloudKit-backed store;
  write a `.custom` migration stage (lightweight stages proved fragile here — see
  `ModelContainer+App.swift` header) or accept a clean cutover, depending on whether any
  TestFlight data must survive.
- **`Data/ModelContainer+App.swift`**: switch the live `ModelConfiguration` to a CloudKit
  configuration — `ModelConfiguration(..., cloudKitDatabase: .private("iCloud.com.ourfitness.app"))`.
  Keep `makeInMemory()` (tests/previews) on a local-only config.
- **Entitlements & capabilities** (follow the CLAUDE.md / [[ios_signing_traps]] rules —
  do **not** add `info:`/`entitlements:` blocks to the target in `project.yml`; use
  `CODE_SIGN_ENTITLEMENTS` build setting only):
  - `OurFitness.entitlements`: add `com.apple.developer.icloud-container-identifiers`,
    `com.apple.developer.icloud-services` (CloudKit), and the container id.
  - `Info.plist`: add **Background Modes → Remote notifications** for sync push.
  - developer.apple.com App ID: enable **iCloud + CloudKit**; create the CloudKit
    container; regenerate the **manually-generated App Store profile** (`OurFitness AppStore`)
    so it carries the new entitlement, re-base64 → `APPSTORE_PROFILE_BASE64` secret.
- **HealthKit interaction**: each device still writes its own steps via
  `Repos.setSteps` (RootView `StepObserverKey` task). With CloudKit, the `setSteps`
  UPSERT (`Repositories.swift` — predicate on `userId && date`) naturally dedupes per day
  across devices. Verify no double-counting when two devices sync the same day.

> The `validate-ci-invariants.sh` guard and the `OurFitnessTests` hostless topology are
> unaffected (Domain stays pure). Don't import SwiftData/CloudKit into `Domain/`.

---

## Phase 3 — App Store submission polish

- **Delete-all-my-data** in Settings (cascade-delete every model row scoped to the
  profile id, plus the per-profile `AppStorage` keys, then route back to
  `ProfileCreationView`). Satisfies App Review 5.1.1(v) data-deletion expectations even
  without accounts.
- **Profile edit** flow (name / vitals / activity). Editing vitals must recompute
  targets via `Targets.compute` (reuse the Phase 1B confirm pattern). `ProfileModel.apply`
  already supports the write.
- **Privacy**: HealthKit usage strings already in `Info.plist`. Fill App Store Connect
  **privacy nutrition labels** (Health & Fitness data, stored on-device + iCloud, not
  shared). No third-party SDKs, no tracking → straightforward.
- **No Sign in with Apple needed**: iCloud private DB is keyed to the user's Apple ID by
  the system; there is no app-level account, so the SiwA requirement doesn't trigger.
- **Marketing surface**: app name, subtitle, screenshots for both Build (warm dark) and
  Circuit (warm light) palettes, App Store description framing the two modes.
- **`ITSAppUsesNonExemptEncryption`** declared (see [[ios_signing_traps]]).

---

## Suggested sequencing

1. **Phase 1** as one PR (single-profile + mode switching + isolation fixes) — shippable
   to the existing TestFlight circle immediately, no schema/entitlement churn.
2. **Phase 2** as a dedicated PR (SchemaV4 + CloudKit + entitlements) — the risky one;
   test sync on two physical devices before merging.
3. **Phase 3** alongside the first real App Store Connect submission.

---

## Verification

**Phase 1**
- Build: `fastlane compile` (or push → `compile.yml`). Domain tests: `fastlane tests`.
- Run on simulator (`/run`): first launch → create profile → confirm only that profile's
  data shows. In Settings, switch Build→Circuit: confirm the sheet previews the target
  change, theme flips light/dark, Train tab disappears, Circuit cards appear in Today, and
  targets on Today reflect the new mode. Switch back: Train returns.
- Regression: log food / a workout / body weight, switch mode, confirm logs persist.

**Phase 2**
- Two simulators/devices signed into the **same** iCloud account: create data on A,
  confirm it appears on B within sync latency. Confirm a *different* Apple ID sees none of
  it (private DB isolation).
- Confirm steps for one day don't double-count after both devices sync.
- Cold-launch with airplane mode → data still readable from local mirror.

**Phase 3**
- Delete-all-my-data wipes every surface (Today, Meals, Progress, Workouts) and returns
  to onboarding. Profile edit recomputes targets. TestFlight build installs and HealthKit
  + iCloud entitlements resolve (walk the CLAUDE.md "Missing entitlement" ladder if not).

---

## Open considerations

- **Migrating existing TestFlight data** into the CloudKit store: clean cutover (simplest,
  acceptable for the tiny circle) vs. a one-time custom migration. Decide before Phase 2.
- **`hasBackfilled.steps`** is a single global `AppStorage` key holding a comma-separated
  set of profile ids (`TodayView`). Functionally fine for one profile; consider making it
  per-profile during Phase 1C cleanup.
- **`ExerciseModel.profileId` is optional** (legacy V1 rows decode `nil`, filtered out).
  Fold a normalization into the SchemaV4 migration if any old rows could linger.
