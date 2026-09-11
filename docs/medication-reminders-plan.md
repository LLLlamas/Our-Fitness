# OurFitness — Medication Reminders & Logging Feature Plan

> **Status: shipped** on `feature/reminders-plants` (September 2026). The rest of
> this document is the original spec, kept for the reasoning behind the design —
> where it and the code disagree, the code and [CLAUDE.md](../CLAUDE.md) win.
>
> Shipped: the Medication category first in the list, add/edit a medication with a
> recommended dosage, one-tap logging of the dose actually taken with its
> timestamp, history grouped by day, the recent-timing pattern, and the opt-in
> pattern notification. Built on the existing reminder group/reminder/event
> entities rather than a parallel `Medication`/`MedicationLog` pair — see §8,
> which asked for exactly that.
>
> **Shipped after the original spec** (and superseding parts of it, noted inline):
> user-set dose times, several per medication (`ReminderDTO.scheduledMinutesOfDay`),
> each firing as its own **daily repeating** notification; every logged dose read
> back against the closest set time ("12 min after 8:00 AM"); an all-medications
> history screen (`MedicationHistorySheet`); an in-app banner naming a medication
> the day has called for and that hasn't been logged; and no photo on a
> medication. See §12, §14, §15, §21 and §30 for what each replaced.
>
> Deliberately not shipped: multiple *inferred* dose slots per day (a medication
> with no set times still infers one time from the log), PRN/as-needed status,
> editing an existing log, archive-vs-delete as separate actions, and a privacy
> mode that hides the medication name in the notification.
>
> **§12 and §16 are binding, not advisory.** The notification may only ever say a
> dose has not been *logged*. The app cannot distinguish a dose taken but not
> logged from one deliberately skipped from one a clinician changed.

## Purpose

Expand the existing **Reminders** feature in OurFitness beyond plant-watering routines so it can also support **simple medication logging, history, pattern visibility, and opt-in reminder notifications**.

The existing Reminders work appears to live on a branch named something like:

`reminders-plants`

The implementation agent should **confirm the exact branch name before making changes**, then continue from that branch rather than rebuilding the Reminders feature from scratch.

---

# 1. Product Goals

The feature should make it extremely easy for a user to:

1. See **Medication** reminders before all other reminder categories.
2. Add and manage medications.
3. Store:
   - Medication name
   - Recommended dosage
   - Dosage actually taken
4. Log a medication as taken with as few taps as possible.
5. Record the **exact date and time** the medication was logged/taken.
6. View a medication's history by day and time.
7. Compare today's medication activity with previous days.
8. Observe whether a consistent medication routine is forming.
9. Optionally receive a notification when:
   - the user normally logs a medication around a certain time,
   - they logged it around that time on a previous day,
   - but they have not logged it yet today.

The app should treat this as a **logging/reminder tool**, not as a source of medical instructions.

---

# 2. Reminder Category Organization

Update the Reminders screen so reminder categories are explicitly ordered.

## Required category order

1. **Medication**
2. **Plants**
3. Any future categories afterward

Do not rely on alphabetical sorting.

Use a fixed category ordering rule, for example:

```ts
const REMINDER_CATEGORY_ORDER = [
  'medication',
  'plants',
];
```

Future categories can be appended after these.

## Reminders screen concept

```text
Reminders

MEDICATION
--------------------------------
Vitamin D
Recommended: 1 tablet
Last logged: Today, 8:12 AM
[ Log Taken ]

Prescription A
Recommended: 10 mg
Last logged: Yesterday, 9:04 PM
[ Log Taken ]

[ + Add Medication ]


PLANTS
--------------------------------
Monstera
Last watered: 3 days ago
[ Watered ]

Snake Plant
Last watered: 8 days ago
[ Watered ]

[ + Add Plant ]
```

Medication should always remain the first visible section.

---

# 3. Medication UX

## 3.1 Add Medication

Create an **Add Medication** form.

Minimum fields:

- Medication name — required
- Recommended dosage — required or strongly encouraged
- Reminder enabled — optional
- Pattern reminder enabled — optional

Recommended dosage should be user-entered.

Examples:

- `10 mg`
- `1 tablet`
- `2 capsules`
- `5 mL`
- `2 puffs`

Do not assume every medication uses mg.

### Optional future-ready fields

These do not all need to ship in v1, but the model should not block them later:

- Dosage amount
- Dosage unit
- Instructions
- Notes
- Medication color/icon
- Active/inactive
- Start date
- End date
- Fixed schedule
- Multiple doses per day
- As-needed / PRN status

---

# 4. Medication Card

Each medication should have a compact card optimized for fast logging.

Suggested contents:

```text
Vitamin D

Recommended: 1 tablet
Last logged: Today • 8:12 AM

[ Log Taken ]       [ History ]
```

If no dose has ever been logged:

```text
Vitamin D

Recommended: 1 tablet
No doses logged yet

[ Log Taken ]
```

Optional future visual status:

- Logged today
- Due around usual time
- No activity today
- Reminder disabled

Avoid language such as **"missed dose"** unless the application has an explicit prescribed schedule. A missing app log does not necessarily mean the user failed to take the medication.

---

# 5. Quick Medication Logging

The main interaction should be extremely fast.

## Recommended flow

User taps:

`Log Taken`

Open a small bottom sheet/modal:

```text
Log Vitamin D

Recommended dosage:
1 tablet

Dosage taken:
[ 1 ] [ tablet ▼ ]

Time:
[ Now ▼ ]

[ Save Log ]
```

### Defaults

- Time defaults to **now**
- Dosage taken may be prefilled using the medication's configured recommended dosage
- User must still confirm/save the log
- User can edit the actual dosage before saving

This allows:

- recommended dosage = `2 tablets`
- dosage taken = `1 tablet`

without overwriting the medication's recommended dosage.

## After save

Immediately:

1. Add the medication log.
2. Refresh the medication card.
3. Update history.
4. Recompute relevant pattern reminder notifications.
5. Show a brief success state such as:

`Logged at 8:12 AM`

---

# 6. Data Model

Prefer separating a **Medication** from individual **MedicationLog** entries.

Do not store medication history as one mutable field on the medication itself.

## Medication

Example TypeScript-style model:

```ts
type Medication = {
  id: string;
  name: string;

  recommendedDosage: {
    amount?: number;
    unit?: string;
    displayText: string;
  };

  isActive: boolean;

  reminderSettings?: {
    enabled: boolean;

    // Pattern-based reminder derived from prior logs.
    patternReminderEnabled?: boolean;

    // Delay after the expected/usual time before notifying.
    gracePeriodMinutes?: number;
  };

  createdAt: string;
  updatedAt: string;
};
```

The `displayText` field keeps the dosage flexible for entries such as:

- `1 tablet`
- `10 mg`
- `5 mL`
- `2 puffs`

If the current codebase already has a reusable reminder model, adapt this structure to it instead of creating unnecessary duplicate abstractions.

---

## MedicationLog

```ts
type MedicationLog = {
  id: string;
  medicationId: string;

  dosageTaken: {
    amount?: number;
    unit?: string;
    displayText: string;
  };

  takenAt: string;

  // Useful for debugging and future analytics.
  source?: 'manual' | 'notification';

  createdAt: string;
};
```

Important distinction:

```text
Medication.recommendedDosage
```

is the configured recommendation/instruction entered by the user.

```text
MedicationLog.dosageTaken
```

is what the user says they actually took during that specific event.

---

# 7. Suggested Storage Shape

If the application uses local storage:

```text
medications
medicationLogs
```

If it uses a database:

```text
medications
medication_logs
```

Suggested relationship:

```text
Medication 1 ---- many MedicationLogs
```

Index logs by:

- medicationId
- takenAt

This will make daily history and timeline queries much easier.

---

# 8. Migration / Backward Compatibility

The existing plant-reminder feature must continue working.

The next implementation agent should inspect:

- current Reminder type
- persistence layer
- plant reminder model
- notification service
- navigation structure
- Reminders screen
- existing date/time utilities

Avoid a rewrite if the existing Reminders architecture can be extended.

If the current reminder objects use a generic category:

```ts
type ReminderCategory =
  | 'medication'
  | 'plants';
```

If they do not, introduce category support carefully and migrate existing plant reminders to:

```ts
category: 'plants'
```

Any persistence migration must preserve existing user plant data.

---

# 9. Medication History

Each medication needs a dedicated history view.

Example:

```text
Vitamin D
Recommended: 1 tablet

TODAY
8:12 AM     1 tablet

YESTERDAY
8:05 AM     1 tablet

MONDAY
8:19 AM     1 tablet

SUNDAY
9:02 AM     1 tablet
```

The user should be able to quickly answer:

- Did I log this today?
- What time did I log it?
- What dosage did I log?
- What time did I usually log it over the last few days?

---

# 10. History Comparison View

A simple comparison is more useful than complicated analytics in v1.

## Suggested v1 design

```text
Recent Pattern

Today       8:12 AM
Yesterday   8:05 AM
Mon         8:19 AM
Sun         9:02 AM
```

Optional summary:

```text
Typical recent time: ~8:15 AM
```

Use language such as:

- `Typical recent time`
- `Usually logged around`
- `Recent pattern`

Avoid calling an inferred time the user's prescribed medication schedule.

---

# 11. Pattern / Schedule Calculation

The user's logging history can be used to identify an approximate routine.

## V1 algorithm

For each medication:

1. Fetch recent logs.
2. Group them by local calendar day.
3. Look at the most recent several days, e.g. 7 days.
4. Compute the time-of-day pattern for that medication.
5. Use the recent pattern only if enough consistent history exists.

Possible first-pass rule:

```text
Need at least 2-3 recent days of logs
before showing "Usually logged around X".
```

A simple median time can be more resistant to outliers than an average.

Example:

```text
Mon 8:04 AM
Tue 8:16 AM
Wed 11:42 AM
Thu 8:09 AM

Median is still around the normal morning period.
```

---

# 12. Notification Behavior

The notification system must be **opt-in per medication**.

## Core requested behavior

If the user logged Medication X yesterday around 8:00 AM, but has not logged it today around that time, OurFitness can remind them.

However, the app should frame the notification as a **logging reminder**, not a direct medical instruction.

### Good notification wording

```text
Medication reminder

You usually log Vitamin D around this time.
No log has been recorded yet today.
```

Or:

```text
Vitamin D hasn't been logged yet today.
Yesterday it was logged around 8:05 AM.
```

**Approved third form — a medication with a SET time** (shipped; `buildRequest`'s
`.medication` branch emits this whenever `scheduledMinutesOfDay` is non-empty):

```text
Medication reminder

Vitamin D is set for 8:00 AM. Tap to log this dose.
```

Why this is still compliant, and why the wording is exactly this: it names a time
the **user themselves entered** and invites a **log**. It does not assert that a
dose is due — which a daily repeating alarm could not know anyway, since it fires
whether or not anything was logged. "Tap to log this dose" is an instruction to
record, never to take.

The title is always the generic `"Medication reminder"`, and no body ever
contains a dosage — that is what satisfies §24's rule against notification
previews exposing dosage information.

### Avoid

```text
Take Vitamin D now.
```

or:

```text
You missed your medication.
```

The app cannot know whether the user actually took a dose but forgot to log it, intentionally skipped it, had their schedule changed, or was instructed differently by a clinician.

---

# 13. Pattern Reminder Logic

## Simplest reliable v1

When a medication log is saved:

1. Look at yesterday's log for the same medication.
2. Determine the corresponding local time today/tomorrow.
3. Schedule a notification for the expected time + grace period.
4. If the user logs the medication before that notification fires:
   - cancel the pending notification.
5. After the new log:
   - schedule the next applicable reminder.

Example:

```text
Yesterday logged: 8:05 AM
Grace period: 30 minutes

Today's reminder:
8:35 AM
```

If today's medication is logged at 8:10 AM:

```text
Cancel 8:35 AM notification.
```

---

# 14. Better Pattern Reminder Logic

After v1 is stable, use several days rather than yesterday alone.

Example:

```text
Last 5 logs:
8:05
8:13
8:09
8:20
8:07

Usual time:
~8:10 AM

Reminder:
8:40 AM if no matching log exists today
```

Recommended priority:

```text
P0: yesterday-based reminder
P1: recent-history median
P2: multiple daily dose slots
```

## Status — what shipped, and the rung the ladder didn't anticipate

P0 and P1 both shipped as one thing: the recent-history median *is* the
yesterday-based reminder when there's a single day of history (the degenerate
median). `MedicationPattern.typicalMinuteOfDay` + `nextFireDate`.

Above both sits a rung this ladder never contemplated — a time the user simply
**states**. It needs no history at all, so it works on day one, and it is not a
guess the app has to defend.

The two are scheduled in deliberately different ways, and the difference matters
more than the timing does:

| | Inferred time | Set times |
|---|---|---|
| Source | median of the log | typed by the user |
| Trigger | one-shot at time + 30 min grace | **daily repeating**, at the exact minute |
| Grace | 30 min | none — they picked the minute |
| Re-armed by | the app running | nobody; iOS repeats it forever |
| Suppressed by a log that day | yes | no |

The one-shot form has a failure mode that is easy to miss and bad in exactly the
wrong direction: it is re-armed only by `reschedule`/`reconcile`, both of which
need the app to run. A nudge ignored *without opening the app* was therefore the
last one that medication ever produced — silence from then on, for precisely the
person least likely to notice. Repeating triggers exist to remove that class of
bug rather than patch it, which is why set times do not go through `nextFireDate`
at all.

---

# 15. Multiple Doses in One Day

The data model should support multiple logs per medication per day even if the first UI is optimized for once-daily routines.

Do not enforce:

```text
one medication = one log per day
```

A user may need to log:

```text
8:00 AM
2:00 PM
8:00 PM
```

For v1 notifications, it is acceptable to keep the pattern-reminder behavior simple and document multiple daily schedule inference as a later enhancement.

## Status — shipped

**Storage always allowed this and still does.** `ReminderEventDTO` is append-only;
`MedicationHistory.byDay` renders every dose of a day earliest-first, and
`MedicationLogDay.doseCount` vs `medicationCount` keeps "three doses" distinct
from "three medications".

**Scheduling now allows it too.** `ReminderDTO.scheduledMinutesOfDay` is a *list*.
A medication taken at 8:00 AM, 2:00 PM and 8:00 PM holds three, each one its own
daily repeating notification under its own identifier
(`reminder.<uuid>#<minute>`). Add and remove them in `DoseTimesEditor`, shared by
the add form and the detail sheet.

Reading a dose back against the right time is by **nearest set time**
(`MedicationPattern.nearestTime`), wrapping around midnight — so a log at 8:14 PM
reads against the 8:00 PM dose, not the morning one, and an 11 PM medication
logged at 12:20 AM is 80 minutes late rather than 22 hours early.

What is still *not* inferred: a medication with **no** set times infers a single
time from its log, as before. Inferring several slots from behaviour remains
future work — but it is now the only part of this section that is.

---

# 16. Notification Safety Rules

Recommended safeguards:

1. Pattern notifications are disabled by default until the user enables them.
2. The notification says a medication has **not been logged**, not that it has not been taken.
3. Never recommend taking an extra or replacement dose.
4. Never infer dose amount from missed logs.
5. Do not automatically modify recommended dosage.
6. ~~If a log exists near the expected time window, suppress the notification.~~
   **Superseded.** This applies only to the *inferred* path, and more broadly than
   written: `MedicationPattern.hasLogToday` means **any** log on the local
   calendar day suppresses that day's nudge and rolls it to tomorrow.
   A medication with **set times** suppresses nothing — each set time is a daily
   repeating alarm that fires regardless, which is the deliberate trade for it
   never going silent (see §14). Suppression for those lives in the UI instead:
   the in-app banner clears once the day's logs match the times reached.
7. When the app opens, reconcile/cancel stale pending notifications.
8. Recompute notifications if:
   - medication is edited,
   - medication is archived,
   - reminder is disabled,
   - medication log is added/deleted/edited.
9. Handle timezone changes and daylight-saving time using local-time-aware utilities.

Suggested small in-app note:

```text
OurFitness helps you track what you log. It does not replace medication
instructions from your doctor, pharmacist, or medication label.
```

---

# 17. Notification Permission Flow

Do not request notification permission immediately when the user first opens Reminders.

Better flow:

1. User adds medication.
2. User enables:
   `Remind me if I haven't logged this around my usual time`
3. Then request OS notification permission.
4. If permission is denied:
   - keep medication logging functional,
   - display a non-blocking explanation,
   - allow the user to open system settings later.

---

# 18. Suggested Screens / Components

Adapt names to the existing project structure.

```text
RemindersScreen
├── MedicationSection
│   ├── MedicationCard
│   ├── AddMedicationButton
│   └── EmptyMedicationState
│
└── PlantsSection
    └── existing plant UI
```

Medication-specific views:

```text
AddMedicationScreen / Modal
EditMedicationScreen / Modal
LogMedicationSheet
MedicationHistoryScreen
MedicationHistoryRow
MedicationPatternSummary
```

Services/hooks:

```text
useMedications
useMedicationLogs
useMedicationHistory
useMedicationPattern

medicationService
medicationLogService
medicationReminderService
notificationService
```

Reuse existing hooks/services where the current branch already has equivalents.

---

# 19. Suggested Domain Helpers

```ts
getMedicationLogsForDay(...)
getLatestMedicationLog(...)
getRecentMedicationPattern(...)
getTypicalMedicationTime(...)
hasMedicationBeenLoggedNearTime(...)
scheduleMedicationPatternReminder(...)
cancelMedicationReminder(...)
reconcileMedicationNotifications(...)
```

Keep date/time calculations out of UI components.

---

# 20. Navigation

Likely routes:

```text
Reminders
  -> Add Medication
  -> Medication Details / History
  -> Edit Medication
```

The Reminders landing page should remain a single place for both:

- medication routines
- plant routines

Do not create a totally separate top-level app feature unless the existing architecture makes that clearly preferable.

---

# 21. Medication Details Screen

Potential layout:

```text
Vitamin D

Recommended dosage
1 tablet

Reminder
Usually logged around 8:10 AM
Pattern reminder: ON

Today
8:12 AM — 1 tablet

Recent history
Yesterday  8:05 AM — 1 tablet
Mon        8:19 AM — 1 tablet
Sun        9:02 AM — 1 tablet

[ Log Taken ]
[ Edit Medication ]
```

---

# 22. Empty States

## No medications

```text
MEDICATION

Keep medication logs organized in one place.

[ + Add Medication ]
```

## Medication exists but no history

```text
No doses logged yet.

Tap "Log Taken" when you want to record a dose.
```

## No stable pattern yet

```text
Keep logging this medication to see your recent timing pattern.
```

---

# 23. Editing / Deleting Logs

History should eventually support fixing accidental entries.

Recommended v1 or near-v1:

- edit dosage taken
- edit taken time
- delete accidental log

Any edit/delete should recalculate:

- recent pattern
- today status
- pending notifications

---

# 24. Privacy

Medication data is sensitive personal information.

Implementation agent should determine whether OurFitness currently stores reminder data:

- only on device,
- in iCloud / device backup,
- or in a remote backend.

Recommended principles:

- store the minimum information required,
- do not send medication names/dosages to analytics,
- do not include medication data in crash breadcrumbs unless sanitized,
- avoid notification previews exposing unnecessary dosage information,
- use existing secure storage/database practices in the app.

A notification can say:

```text
Medication reminder
You have a medication that hasn't been logged yet.
```

if the user prefers privacy-sensitive notifications.

A future setting could allow:

```text
Show medication name in notifications: ON/OFF
```

---

# 25. Accessibility / Ease of Use

Medication logging should prioritize:

- large tap targets
- readable dosage text
- one-handed use
- minimal typing after medication setup
- VoiceOver/screen-reader labels
- Dynamic Type / scalable text where applicable
- clear selected date/time
- clear confirmation after logging

Avoid tiny icon-only controls for critical medication actions.

---

# 26. Recommended Implementation Phases

## Phase 0 — Repository Reconnaissance

The implementation agent should first:

```bash
git fetch --all
git branch -a
```

Identify the existing reminder branch, likely similar to:

```text
reminders-plants
```

Then inspect:

- Reminders screen
- plant reminder model
- storage
- notification code
- navigation
- existing date/time helpers

Do not begin by replacing working plant-reminder code.

---

## Phase 1 — Category Structure

Deliver:

- Medication category
- Medication rendered first
- Plants still work
- explicit category ordering

Acceptance:

```text
Medication always appears above Plants.
```

---

## Phase 2 — Medication CRUD

Deliver:

- Add medication
- Edit medication
- Archive/delete medication
- name
- recommended dosage
- persistence

---

## Phase 3 — Medication Logging

Deliver:

- Log Taken button
- actual dosage taken
- timestamp
- quick logging modal/sheet
- latest-log display

---

## Phase 4 — History

Deliver:

- chronological history
- group logs by date
- display exact times
- display dosage taken
- today's log state
- previous-day comparison

---

## Phase 5 — Pattern Summary

Deliver:

- recent time comparison
- basic "usually logged around" calculation
- insufficient-history state
- timezone-safe handling

---

## Phase 6 — Notifications

Deliver:

- opt-in pattern reminder
- OS permission handling
- schedule notification
- cancel notification when relevant log exists
- recompute after log/edit/delete
- non-medical wording

---

## Phase 7 — QA / Polish

Deliver:

- persistence migration validation
- error states
- notification edge cases
- multiple logs/day support
- timezone / DST tests
- accessibility pass
- no regressions in Plants

---

# 27. Suggested MVP Scope

The first usable release should include:

- Medication category first
- Add/edit medication
- Medication name
- Recommended dosage
- Log dosage taken
- Automatically store date/time
- Medication history
- Today vs recent days
- Opt-in pattern reminder
- Notification cancellation after a matching log
- Existing plant reminders unaffected

Do **not** block MVP on:

- complex prescription schedules
- medication interaction checking
- pharmacy integrations
- OCR/label scanning
- Apple Health medication sync
- adherence scoring
- clinician dashboards
- advanced analytics

Those can be separate future features.

---

# 28. Acceptance Criteria

## Reminders organization

- [ ] Reminders screen contains Medication and Plants sections.
- [ ] Medication always renders first.
- [ ] Existing plant reminders still function.

## Medication setup

- [ ] User can create a medication.
- [ ] Medication name is stored.
- [ ] Recommended dosage is stored.
- [ ] Medication can be edited.
- [ ] Medication can be archived/deleted.

## Logging

- [ ] User can tap `Log Taken`.
- [ ] User can record actual dosage taken.
- [ ] Current time is the default.
- [ ] User can modify the time before saving.
- [ ] Saved log stores medication ID, dosage taken, and timestamp.
- [ ] Multiple logs for the same medication are allowed.

## History

- [ ] User can see medication history.
- [ ] History shows date.
- [ ] History shows time.
- [ ] History shows dosage taken.
- [ ] Most recent entries are easy to identify.
- [ ] User can compare recent days.

## Pattern

- [ ] UI can show recent logging times.
- [ ] Pattern language does not imply a medically prescribed schedule.
- [ ] Insufficient history is handled gracefully.

## Notifications

- [ ] Pattern reminders are opt-in.
- [ ] App requests notification permission only when relevant.
- [ ] App can schedule a reminder around the medication's recent logging pattern.
- [ ] Logging the medication cancels/suppresses the relevant reminder.
- [ ] Notification says the medication has not been **logged**, rather than claiming it was not taken.
- [ ] Editing/deleting a log causes notification state to be reconciled.

## Quality

- [ ] Timezone changes do not corrupt the displayed local history.
- [ ] Daylight-saving changes are handled correctly.
- [ ] Plant reminder data is not lost.
- [ ] Medication values are not sent to analytics without an explicit privacy decision.
- [ ] Core controls are accessible.

---

# 29. Important Test Cases

### Basic logging

```text
Create Medication A
Recommended dosage = 10 mg
Log 10 mg at 8:03 AM
History shows 10 mg / 8:03 AM
```

### Different actual dosage

```text
Recommended = 10 mg
Taken = 5 mg

History must show:
5 mg taken

Medication setup must remain:
10 mg recommended
```

### Yesterday-based reminder

```text
Yesterday:
Medication A logged at 8:05 AM

Today:
No log exists

Grace period:
30 min

Expected:
Reminder around 8:35 AM
```

### Reminder cancellation

```text
Pending reminder:
8:35 AM

User logs at:
8:10 AM

Expected:
8:35 AM reminder is cancelled/suppressed.
```

### Multiple logs

```text
8:00 AM
2:00 PM

Both should remain in history.
```

### Midnight edge case

```text
Log at 11:55 PM.
```

It must belong to the correct local calendar date.

### Timezone change

If the user travels, historical timestamps should remain coherent and notification scheduling should be recalculated using the application's chosen timezone strategy.

### Existing plant data

Upgrade from the current Reminders branch.

Expected:

```text
All existing plant reminders remain present and functional.
```

---

# 30. Future Enhancements

Potential later features:

- ~~fixed medication schedules~~ — **shipped** (`scheduledMinutesOfDay`)
- ~~multiple scheduled times per day~~ — **shipped**; several set times per
  medication, each a daily repeating alarm. Inferring several slots from the log
  is still future work
- PRN/as-needed mode
- snooze notification
- "log from notification" action
- weekly timing visualization
- adherence trend visualization
- medication archive
- privacy mode for notification text
- Apple Health medication integration, if appropriate
- exportable medication history
- shared caregiver view, only with deliberate privacy design

These should not complicate the first implementation.

---

# 31. Suggested First Agent Prompt

The following can be given to the implementation agent along with this file:

```text
Work in the existing OurFitness repository.

There is already a Reminders feature/branch for plant watering,
likely named something similar to `reminders-plants`.

First inspect the repo and identify the exact branch and current
Reminders architecture. Continue from that work rather than rebuilding it.

Implement the medication reminder/logging feature described in
OURFITNESS_MEDICATION_REMINDERS_PLAN.md.

Priorities:
1. Preserve all existing plant reminder behavior/data.
2. Add explicit reminder categories.
3. Always render Medication before Plants.
4. Add medication CRUD.
5. Add fast medication logging with recommended dosage vs dosage taken.
6. Store timestamped medication history.
7. Add recent-day timing comparison.
8. Add opt-in pattern-based local push notifications.
9. Phrase notifications as logging reminders, not medical instructions.
10. Add tests for date/time, persistence, category ordering, and
    notification cancellation/reconciliation.

Before changing architecture, inspect and reuse existing models,
components, persistence, and notification utilities whenever practical.

Keep the implementation incremental and commit logical phases separately.
```

---

# 32. Definition of Done

The feature is complete when a user can open **Reminders**, immediately see **Medication first**, add a medication, store its recommended dosage, quickly log the actual dose taken, see exactly when it was logged across recent days, understand their recent logging pattern, and optionally receive a safe notification when the expected logging window passes without a new log — while all existing plant-reminder functionality continues to work.
