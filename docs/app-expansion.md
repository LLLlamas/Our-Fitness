# App Expansion — Phase 2/3 roadmap (iCloud sync, App Store polish)

> Status: **Plan.** Phase 1 shipped and is no longer described here: one profile per
> install, goal changeable at will (originally Build/Circuit modes, merged Oct 2026 into
> one app with a per-user goal), and per-profile `@Query` isolation (hard rule 3 in
> [CLAUDE.md](../CLAUDE.md)). Phases 2 (iCloud/CloudKit sync) and 3 (store polish) are still
> planned. [CLAUDE.md](../CLAUDE.md) is authoritative; the Phase 1 design text was removed
> and is recoverable with `git show ff15fa5:docs/app-expansion.md`.

## Decisions (locked with the user)

- **Per-user data model:** iCloud per-person — SwiftData + CloudKit *private* database; data syncs across that person's own devices. A backend is allowed if a feature needs one, but nothing here requires it.
- **Profiles per install:** one. The device is one person.

The app is already per-profile: every log model carries an owner key and repositories filter by it (`Data/PersistenceModels.swift`, `Data/Repositories/`), so CloudKit work is schema and entitlement work, not a rewrite.

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

- **Next unshipped schema** in `Data/Schema.swift`: determine its version when implementing this phase; the current local store uses **SchemaV7**, not the original plan’s V3/V4. Never reuse a shipped version.
  Register the CloudKit-compatible model set and update `AppSchema.current`.
  The live container opens `OurFitness.store` without a staged migration plan.
  Design and test a data-preserving migration before changing its configuration;
  this roadmap does not authorize a fresh-store cutover or loss of existing logs.
  See `Data/ModelContainer+App.swift` for the historical store change.
- **`Data/ModelContainer+App.swift`**: switch the live `ModelConfiguration` to a CloudKit
  configuration — `ModelConfiguration(..., cloudKitDatabase: .private("iCloud.com.ourfitness.app"))`.
  Keep `makeInMemory()` (tests/previews) on a local-only config.
- **Entitlements & capabilities** (follow [ci.md](ci.md) signing rules —
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

---

## Phase 3 — App Store submission polish

- **Delete-all-my-data** in Settings (cascade-delete every model row scoped to the
  profile id, plus the per-profile `AppStorage` keys, then route back to
  `ProfileCreationView`). Satisfies App Review 5.1.1(v) data-deletion expectations even
  without accounts.
- **Profile edit** flow (name / vitals / activity). Editing vitals must recompute
  targets via `Targets.compute` (reuse the goal-switch confirm sheet pattern in Settings). `ProfileModel.apply`
  already supports the write.
- **Privacy**: HealthKit usage strings already in `Info.plist`. Fill App Store Connect
  **privacy nutrition labels** (Health & Fitness data, stored on-device + iCloud, not
  shared). No third-party SDKs, no tracking → straightforward.
- **No Sign in with Apple needed**: iCloud private DB is keyed to the user's Apple ID by
  the system; there is no app-level account, so the SiwA requirement doesn't trigger.
- **Marketing surface**: app name, subtitle, screenshots of the single light palette,
  App Store description framing the two goals (Build muscle / Lose weight). *(Originally
  planned as Build warm-dark + Circuit warm-light screenshots; modes are gone.)*
- **`ITSAppUsesNonExemptEncryption`** declared (see [ci.md](ci.md)).


---

## Verification

**Phase 2**
- Two simulators/devices signed into the **same** iCloud account: create data on A,
  confirm it appears on B within sync latency. Confirm a *different* Apple ID sees none of
  it (private DB isolation).
- Confirm steps for one day don't double-count after both devices sync.
- Cold-launch with airplane mode → data still readable from local mirror.
- Test sync on two physical devices before merging; this is the risky PR.

**Phase 3**
- Delete-all-my-data wipes every surface (Today, Meals, Progress, Workouts) and returns
  to onboarding. Profile edit recomputes targets. TestFlight build installs and HealthKit
  + iCloud entitlements resolve.

## Open considerations

- **Migrating existing TestFlight data** into the CloudKit store: clean cutover (simplest,
  acceptable for the tiny circle) vs. a one-time custom migration. Decide before Phase 2.
  (Section "Work" above already forbids losing existing logs without a tested migration.)
- **`hasBackfilled.steps`** is a single global `AppStorage` key holding a comma-separated
  set of profile ids (`TodayView`). Fine for one profile.
- **`ExerciseModel.profileId` is optional** (legacy V1 rows decode `nil`, filtered out).
  Fold a normalization into the next schema migration if any old rows could linger.
