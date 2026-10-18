# Removed: Reminders (plants, generic reminders, medication)

**Status: removed from the phone and watch apps (October 2026).** The app is now
fitness + food + progress + encouragement only. Meal-logging push reminders
(`Services/MealReminderService.swift`, `Domain/MealLogPattern.swift`) are food
features and stay.

**Recovering the feature:** the last commit with the full feature in the tree is
`d284700` ("Strength card (estimated max per lift) and tape-measure trackers…").
Recover from git history at/after `d284700` (the pre-removal working tree also
had a few uncommitted doc edits; code was identical to `d284700`). Use
`git show d284700:<path>` or `git checkout d284700 -- <path>`.

## What was removed

- **Plants** — watering reminders with a ~26-species catalog
  (`Domain/PlantCatalog.swift`), light level, pot size, photo, care notes.
- **Generic reminders** — custom groups, "every N days" intervals (1–365),
  due/overdue lists, snooze (`Domain/ReminderSchedule.swift`, `IntervalPicker`).
- **Medication tracking** — the first category on the Reminders tab: recommended
  dosage, user-set daily dose times, one-tap dose logging, history by day,
  all-medications history sheet, in-app "dose not logged" banner, notification
  copy (`Domain/MedicationPattern.swift`, `Domain/MedicationHistory.swift`,
  `LogMedicationSheet`, `MedicationHistorySheet`, `MedicationDueBanner`).
- Phone UI: the whole `Features/Reminders/` folder and the Reminders tab in
  `App/RootView.swift`; Settings "Reminders (medication, plants & more)" toggle
  and "Reminder time" picker.
- Services: `Services/ReminderNotificationService.swift` (scheduling, lock-screen
  action buttons, reconcile) and `Services/ImageDownscale.swift` (only the
  reminder photo step and watch thumbnails used it).
- Repos CRUD: `addReminder`/`updateReminder`/`deleteReminder`/`logReminderDone`/
  `snoozeReminder`/`addReminderGroup`/`deleteReminderGroup`/`ensurePlantsGroup`/
  `ensureMedicationGroup` and the list/read helpers. `Repos.createProfile` no
  longer creates the two built-in groups (starter-movement seeding and the single
  commit boundary are unchanged); `Seeder` no longer backfills them.
- Watch: `ReminderSnapshot`, every reminder/medication field of
  `WatchSnapshotEnvelope`, the reminder `WatchAction` cases, photo thumbnail
  transfer, and the watch Reminders tab. Decoding stays tolerant: an older phone
  that still sends a `reminders` array is ignored, not an error.

**Why:** scope. The app is positioned as fitness + food + progress +
encouragement; plant care and medication logging pulled it toward a general
reminders app, carried the most safety-sensitive wording rules in the product,
and added a tab, a notification service, and a large watch surface.

## One-time cleanup on launch

`Services/AppNotificationDelegate.swift` → `RetiredReminderCleanup.runOnce()`
(called from `OurFitnessApp.init`, gated by UserDefaults key
`retiredReminders.notificationCleanup.v1`) removes every pending and delivered
local notification whose identifier starts with `reminder.` and clears the
registered notification categories (the plant / custom / medication action
buttons). Without it, already-scheduled repeating medication alarms
(`reminder.<uuid>#<minute>`) would keep firing after the update with nothing to
open. Meal-reminder notifications (`mealLog.*`) are not touched.

## What is deliberately kept (so existing installs keep their data)

- `ReminderGroupModel` / `ReminderModel` / `ReminderEventModel` in
  `Data/PersistenceModels.swift`, in `SchemaV7` (`Data/Schema.swift`).
- `ReminderGroupDTO` / `ReminderDTO` / `ReminderEventDTO` in `Domain/Models.swift`.
- `Domain/RetiredReminderSupport.swift`: `PlantLightLevel` (persisted as
  `ReminderModel.lightRaw`) and a stub `MedicationPattern.normalizedTimes`
  (called by `ReminderDTO.init`). Delete this file in the same change that
  removes the DTOs/models.
- Nothing reads or writes these tables any more. No persisted raw value and no
  schema version was changed.

## Leftover DB tables

The three tables remain in the store: `ReminderGroupModel`, `ReminderModel`,
`ReminderEventModel`. Plant photo blobs (`ReminderModel.photoData`, up to ~1024 px
JPEG) and medication rows stay on disk. We would need to actually delete them when:

- **(a) Privacy.** Medication names, doses and dose history are health data that
  the user can no longer see or erase. That conflicts with the erase-local-data
  and privacy-controls work in `docs/next-audit-scope.md`. This is the most
  likely trigger: do it before shipping any "erase my data" control or a
  privacy-policy claim of "you can delete everything".
- **(b) iCloud sync** (`docs/app-expansion.md`). It would sync invisible data.
- **(c) Schema migrations.** Every future migration carries the three entities.
- **(d) Storage.** Plant photo blobs take space.

Removal requires a `Schema.swift` version bump (V8 without the three models)
plus a migration stage that drops the entities. Note the existing rule in
`Data/ModelContainer+App.swift`: do not use `NSLightweightMigrationStage` (it threw
an uncatchable Obj-C exception in builds 26/27); prove the in-place upgrade on a
simulator with real V7 data before shipping. Then also delete the DTOs, the
`Reminder*Model` classes, and `Domain/RetiredReminderSupport.swift`.

## Medication design notes (kept for a future return)

Full original spec: [medication-reminders-plan.md](medication-reminders-plan.md)
(marked RETIRED; its §12 and §16 safety wording was binding).

- **Set times vs inferred pattern.** A medication could have user-set dose times
  (`ReminderDTO.scheduledMinutesOfDay`, several per day) or none. Set times each
  became one repeating daily `UNCalendarNotificationTrigger(hour, minute,
  repeats: true)` (id `reminder.<uuid>#<minute>`): no fire instant, no grace, no
  re-arm. Never convert set times back to one-shots; a one-shot is only re-armed
  when the app runs, so a nudge ignored without opening the app was the last one
  that medication ever produced. The trade: a repeating alarm can't skip a day, so
  it fires whether or not a dose was logged (suppression lived in the in-app
  banner). With no set times, the *inferred* path scheduled a one-shot at the
  median time of day of the earliest dose per day over 7 days (today excluded) plus
  a 30-minute grace, re-armed on launch/foreground; 1 day of history was enough to
  schedule, 2 before the UI claimed a routine.
- **Nearest-dose timing.** A logged dose was read against the closest set time,
  with distance wrapping midnight (an 11 pm dose logged at 00:20 is 80 min late,
  not 22 hr early; 8:14 PM reads against the 8 PM dose). Copy: "12 min after 8:00
  AM", or "On time" inside a tolerance. No set times meant render nothing.
- **Recommended vs taken dosage.** `ReminderDTO.dosage` was the configured
  recommendation; `ReminderEventDTO.dosageTaken` was what was actually taken, per
  event. Logging never wrote back to `dosage`. A one-tap log with no amount (lock
  screen, watch, quick button) resolved to the recommendation.
- **Safety wording (binding).** Notifications and banners may only say a dose has
  not been *logged*: never "take X now", never "missed", never an amount, never
  a replacement/extra dose, never infer an amount from missed logs. The app can't
  tell taken-but-unlogged from skipped from clinician-changed. Pattern
  notifications were opt-in per medication (default off); permission was
  requested only after enabling that, never on first open. In-app disclaimer: the
  app helps track what you log and does not replace instructions from a doctor,
  pharmacist or label. Medication was excluded from Due/overdue lists on every
  surface (including the watch) because its `intervalDays` was a placeholder and
  "overdue" would be a missed-dose claim.
- **No photo for medication.** A plant is identified by looking at it, a
  medication by name + dosage; an empty camera circle only invites a dead tap.
  `photoData` on older rows stayed on disk, unread.
- **Group-kind identification.** "Is this a medication?" was answered by the
  reminder's *group* (`ReminderGroupKind.medication`), not the DTO; there was
  deliberately no `ReminderDTO.isMedication`. Built-in groups: Medication (sort
  rank 0), Plants (1), custom (2); only custom groups were deletable.
- **Banner counts, not matches.** The "dose not logged" banner compared the
  count of set times reached today with today's logs (matching a log to a specific
  dose isn't knowable). "Today" had to come from the ticking `now`, never from a
  `startOfDay` baked into a long-lived `@Query` predicate.
- **History** was uncapped on purpose (a record that stops at N rows reads as
  "that's all there was") and a single projection shared by the all-medications
  sheet and the per-medication detail so the two could not disagree.
