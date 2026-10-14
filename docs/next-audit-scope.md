# Next audit scope — prepared 2026-09-14

Start with CLAUDE.md and audit-handoff.md. This is a scoped backlog, not a claim
that the remaining privacy features are implemented. Finish verifying the active
TestFlight release before starting another shipping milestone.

## Milestone 2: privacy controls and retention

- Resolve the pending medication-notification preference: authentication for
  "Log taken" and generic versus named text. Preserve existing behavior until
  the user answers. Keep the binding medication safety wording rules.
- Design one explicit erase-local-data flow with a reviewable confirmation.
  Inventory current and legacy stores, profile defaults, AI/service caches,
  pending/delivered notifications, live sessions/activities, watch envelope and
  thumbnails. Define an offline-watch tombstone so old queued actions cannot
  recreate erased data. Never erase real user data to test the feature.
- Clarify that app deletion does not remove original HealthKit data or backups.
  Verify OS storage protection/backup behavior on physical devices before making
  public privacy claims. Keep privacy-security.md and user-facing copy aligned.
- Acceptance: locked/unlocked medication actions; preview on/off; mirrored watch;
  erase with connected/offline watch; relaunch without resurrection; user cancel
  leaves data untouched. Use disposable fixtures.

## Independent release maintenance

- Resolve and review Gemfile.lock with Ruby 3.3 (CI version), then verify install.
  Avoid resolving against the locally available Ruby 2.6 or rotating signing.
- Review repository branch protection and App Store privacy answers read-only.
  Inspect production archive manifests/privacy report when available.
- No signing redesign, schema raw-value rename, or automatic cert refresh.

## Milestone 3: measured performance and delivery resilience

- Benchmark Meals/Progress and reminder aggregation with realistic multi-year
  persisted fixtures on device. Snapshot food/water/steps are already bounded.
- Preserve uncapped medication history, streak semantics and historical shortcuts.
- Design durable watch action acknowledgement/retry and stable action IDs before
  promising exactly-once delivery under storage failure. Reconciliation exists;
  persistent retry does not. Include profile/erase generation boundaries.
- Extract large view sections only when the measured change benefits from it.

## Usage budget discipline

Work one bounded change at a time; keep a buildable checkpoint. Before usage
exhaustion, record actual results, unverified edits, exact next command/task,
release state and unanswered decisions in audit-handoff.md. Update related docs
in each milestone commit. Do not start a broad refactor near exhaustion.
