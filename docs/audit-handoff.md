# Audit remediation handoff — 2026-09-14

## Current state: verified milestone authorized for commit, push and TestFlight

The user approved the three-agent audit and continuing remediation. The user
explicitly requires checkpoints before usage exhaustion so another agent can
resume safely. All three child agents hit usage limits; root integrated their
edits and completed the validation below. No agents remain working. The user subsequently authorized committing and pushing
the current milestone and shipping it to TestFlight. Release dispatch/status is
recorded below as it becomes available. No schema migration or user-data deletion
was performed.

Read CLAUDE.md, this checkpoint, and current git status/diff before continuing.
Do not restart the audit or treat earlier failing test logs as current results.

## Preserve pre-existing user work

At audit start CLAUDE.md, MoveCard.swift, TodayView.swift and WatchSyncService.swift
were already modified. StepsCard.swift was already staged for deletion. These
changes were preserved, with remediation layered into shared files. Do not
revert these changes. The user authorized shipping the integrated current state,
including the existing Today/Move consolidation. Other current changes are
remediation. The release commit includes this documented combined milestone.

## Implemented

- Repository mutations now return Bool or optional DTO success. Feature callers
  gate success feedback; reminder services gate rescheduling/removal feedback.
  RepositoryWrite explicitly saves, rolls back failures, re-fetches affected
  existing rows, and posts save/error notifications. Root presents a generic
  save-error alert without logging sensitive values. Natural-language meal input
  remains open if saving fails. Profile creation/Circuit seeds and reminder
  creation/initial watering event now share commit boundaries.
- Phone and watch finish through LiveSessionCompletionService. A stale runner
  cannot finish or adjust a replacement. Durable history checks prevent duplicate
  completion after save-before-clear interruption. Recovery state is cleared only
  after a successful write. System notification/Live Activity cleanup is injected
  out of hostless lifecycle tests.
- Successful saves, live-session changes and defaults changes coalesce watch
  snapshots. No snapshot work is scheduled without a paired installed companion.
  Rejected/failed wrist actions also schedule reconciliation of optimistic state.
  Water preserves the original action timestamp. Known activities resolve name
  and MET on the phone; Other intensity, plan and date inputs are validated.
- Snapshot reads now fetch 30 days of food and today's water/steps. Historical
  shortcut resolution and full medication history remain available. Move reloads
  its HealthKit readings on pull-to-refresh and foregrounding.
- Phone/watch privacy manifests declare UserDefaults reason CA92.1. They are
  wired into project.yml and present in built products, including embedded watch.
- GitHub Actions revisions are pinned; compile/TestFlight permissions are explicit
  and checkout credentials are not persisted. Release secrets are scoped to
  consuming steps. Existing manual signing/match and tag-only test policy remain.
- README, agent guides, setup/signing/watch docs and historical status labels were
  reconciled. docs/privacy-security.md records actual data flows and limitations.
  AGENTS.md and CLAUDE.md require usage checkpoints and same-commit milestone docs.

## Verified

- Final local iOS Simulator build: PASS (iPhone 17, Xcode 26.6, signing disabled).
- Full suite: 389 Domain/shared-payload tests + 10 persistence/session tests =
  399 passing, zero failures. A final watch-availability guard was subsequently
  build-verified; it does not change the tested persistence/Domain behavior.
- bash scripts/validate-ci-invariants.sh: PASS.
- git diff --check: PASS.
- Workflow YAML parsed; Fastfile Ruby syntax checked; manifest plist lint passed.
- Manifest presence confirmed in Debug-iphonesimulator/OurFitness.app and its
  embedded Watch/OurFitnessWatch.app, plus the watch simulator product.
- Five-year fixture: 10,950 food rows versus 180 bounded rows with identical
  current totals/affinity. Warm in-memory diagnostic roughly 142ms versus 3.2ms
  in one run; this is NOT a physical-device performance guarantee.

Logs are /tmp/ourfitness-remediation-build.log, /tmp/ourfitness-remediation-tests.log,
and /tmp/ourfitness-remediation-invariants.log. They are optional diagnostics;
this file is the durable status record. Regenerate the gitignored Xcode project
from project.yml when appropriate; new source files are already included locally.

The new OurFitnessPersistenceTests target is separate and hostless, directly
compiling Domain/persistence/repository and selected session services. Do not add
an app host or @testable import. During development, rollback initially left a
retained SwiftData model value stale until fetched; re-fetching affected models
fixed that and the dedicated regression passes. Real notification services
cannot run in a hostless test bundle; cleanup is injected for tests.

## Next actions and remaining limits

1. Complete the authorized release, verify workflow outcome, and record the commit
   and run URL here. Next implementation scope is in docs/next-audit-scope.md.
2. Medication privacy choice is pending in a user-input question: require unlock
   and hide names by default, require unlock with names, or preserve behavior
   with optional settings. No behavior change has been made. Don't claim an
   unanswered question was approval. Physical locked/unlocked phone and mirrored
   watch notification checks remain necessary.
3. Implement/review a coordinated erase-data design and explicit retention policy
   covering current/legacy stores, preferences, notification/Live Activity state,
   and paired-watch caches. This is not implemented. Do not delete actual user
   data as part of development/testing. Explain HealthKit/backup boundaries.
4. Generate/review Gemfile.lock using supported Ruby 3.3, then verify dependency
   installation. Only system Ruby 2.6 was found locally. No runtime was installed.
   Other tool/transitive dependency pinning remains deliberate follow-up work.
5. Verify a production archive/privacy report, App Store privacy answers, repository
   protections and physical-device storage/backup behavior. Source review does
   not establish those external settings. No public release was attempted.
6. Phone/watch interactive checks: both finish orders, offline queued actions,
   replacement while phone runner is open, failed-save UI/retry, live goals and
   Health refresh. Current integration tests cover repository/session operations,
   not actual WatchConnectivity delivery or every SwiftUI sheet dismissal path.
   Failed watch storage writes reconcile the snapshot but have no durable retry
   outbox; transport queuing alone does not guarantee a failed save is retried.
7. Further performance work should measure Meals/Progress rendering and all-history
   reminder snapshot aggregation on real multi-year stores before restructuring.
   Do not truncate full history/streaks or rewrite large views merely for size.
8. Keep real released-store fixtures before any future structural schema change;
   old schema enums reference mutable current models and are not archival fixtures.

## Usage interruption protocol

At each meaningful checkpoint and before usage exhaustion, update this file with
completed/incomplete edits, actual checks, active agents, next steps and pending
choices. Finish or clearly mark an in-progress mutation before another begins.
Never label unbuilt/untested changes complete. Do not rely on conversation history,
agent memory, or /tmp scripts as the only handoff. Resume from this state.
