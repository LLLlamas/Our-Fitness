# Next audit scope — prepared 2026-09-14, revised 2026-11-21

Start with CLAUDE.md. This is a scoped backlog, not a claim that the remaining
privacy features are implemented.

## Milestone 2: privacy controls and retention

- Medication and reminders were removed (see [removed-reminders.md](removed-reminders.md)).
  The erase-local-data flow must also delete the retired
  `ReminderGroupModel` / `ReminderModel` / `ReminderEventModel` rows (medication
  names, doses and history are still on disk), which needs a schema version bump
  and migration stage.
- Design one explicit erase-local-data flow with a reviewable confirmation.
  Inventory current and legacy stores, profile defaults, AI/service caches,
  pending/delivered notifications, live sessions/activities, watch envelope and
  thumbnails. Add the per-profile `weeklyRepsNote.<uuid>` UserDefaults key (weekly-reps
  toast gate) and the one-time `backfill.fixedLoadWeights.v1` flag to the inventory. Define an offline-watch tombstone so old queued actions cannot
  recreate erased data. Never erase real user data to test the feature.
- Clarify that app deletion does not remove original HealthKit data or backups.
  Verify OS storage protection/backup behavior on physical devices before making
  public privacy claims. Keep privacy-security.md and user-facing copy aligned.
- Acceptance: erase with connected/offline watch; relaunch without resurrection; user cancel
  leaves data untouched. Use disposable fixtures.

## Independent release maintenance

- Resolve and review Gemfile.lock with Ruby 3.3 (CI version), then verify install.
  Avoid resolving against the locally available Ruby 2.6 or rotating signing.
- Review repository branch protection and App Store privacy answers read-only.
  Inspect production archive manifests/privacy report when available.
- No signing redesign, schema raw-value rename, or automatic cert refresh.

## Milestone 3: measured performance and delivery resilience

- Benchmark Meals/Progress (including the full-history rep fetches, `Repos.setHistory(limit: 100_000)` and `Repos.weeklyReps`) with realistic multi-year
  persisted fixtures on device. Snapshot food/water/steps are already bounded.
- Preserve streak semantics and historical shortcuts.
- Design durable watch action acknowledgement/retry and stable action IDs before
  promising exactly-once delivery under storage failure. Reconciliation exists;
  persistent retry does not. Include profile/erase generation boundaries.
- Extract large view sections only when the measured change benefits from it.

## Unverified from the 2026-11-20/21 Add food and Train work

Built and unit/persistence-tested on the iPhone 17 simulator only
([validation-log.md](validation-log.md), last three entries). Still open:

- Device and watch: haptics (`Haptics.tap()` on −1, `Haptics.bump()` on the
  counter's ±1), the keyboard Done toolbar on the hold and Edit Set fields, and
  the watch app against this build (unchanged, not run).
- Tapping a "Did you mean" pill (and the on-device AI rewrite timing).
- The Add food Recent box (min(280 pt, 35%)) with the keyboard up.
- Small width (iPhone SE) and large Dynamic Type: Train rows with −1/+1, the
  rep counter wheel between its buttons, the minute row with a double-digit
  Today value.
- −1 left open across local midnight: stays enabled until the card refreshes
  (the repo call then writes nothing). Known limitation, not fixed by decision;
  re-check if a fix is wanted.
- "Log hold" button hierarchy: an idea, not decided. With the timer open,
  "Log hold" (`.tactile(.primary)`, `theme.ok` fill) and "Start hold"
  (`.tactile(.primary)`) are both primary.

## Usage budget discipline

Work one bounded change at a time; keep a buildable checkpoint. Before usage
exhaustion, record actual results, unverified edits, exact next command/task,
release state and unanswered decisions in [validation-log.md](validation-log.md). Update related docs
in each milestone commit. Do not start a broad refactor near exhaustion.
