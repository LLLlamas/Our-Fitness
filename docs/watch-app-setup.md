# Watch app setup (Reminders companion — Apple Watch)

The Reminders tab now has a **watchOS companion app** (`OurFitnessWatch`): a thin
client with no local SwiftData store that mirrors reminders synced over
`WatchConnectivity` from the phone (`Services/WatchSyncService.swift`). You can
check a reminder off, snooze it, or just glance at what's due, right from the
wrist.

This works in code already, but **shipping it to TestFlight / the App Store
needs a few one-time manual steps** because the watch app is a *second* signed
binary embedded in the app, and our signing pipeline currently provisions only
the main app (plus the widget extension — see
[docs/live-activity-setup.md](live-activity-setup.md), the exact template this
doc follows). Do all of the following before cutting a TestFlight build that
includes the watch app.

> The notification-mirroring path is **already live and needs none of this**:
> `Services/ReminderNotificationService.swift` posts a local notification with
> action buttons ("Watered"/"Done" + "Snooze 1 day") that Apple Watch mirrors
> automatically to a paired watch with **zero watch app installed** — that's
> standard `UNNotificationCategory` behavior, not something this companion app
> provides. The steps below are only for the separate, richer companion **app**
> (browsing all reminders, watch-side thumbnails, etc.).

---

## What the code added (for reference)

| Piece | Location |
|---|---|
| Phone-side sync driver | `Services/WatchSyncService.swift` |
| Wire format shared by phone + watch | `Shared/ReminderSyncPayload.swift` |
| Photo/thumbnail downscale (shared) | `Services/ImageDownscale.swift` |
| Watch app entry point (`@main`) | `OurFitnessWatch/OurFitnessWatchApp.swift` |
| Watch-side in-memory store (no SwiftData) | `OurFitnessWatch/WatchReminderStore.swift` |
| Watch list / detail UI | `OurFitnessWatch/ReminderListView.swift` + `ReminderDetailView.swift` |
| Watch target + embedding | `project.yml` (`OurFitnessWatch` target, `dependencies: embed: true` on the app) |

Bundle ids:
- App: `com.ourfitness.app`
- Watch app: **`com.ourfitness.app.watchkitapp`** (must be a child of the app id)

The watch target compiles `OurFitness/Domain/PlantCatalog.swift`,
`OurFitness/Domain/ReminderSchedule.swift`, and `Shared/ReminderSyncPayload.swift`
directly as extra sources rather than pulling in the whole `Domain/` folder —
the same pattern `OurFitnessTests` uses to compile `OurFitness/Domain` directly
without linking the app target.

---

## Step 1 — Register the watch App ID

1. developer.apple.com → **Certificates, Identifiers & Profiles → Identifiers → +**.
2. Type **App IDs → App**.
3. Bundle ID: **explicit** → `com.ourfitness.app.watchkitapp`.
4. Capabilities: **none** required for `WatchConnectivity` — it needs no
   managed capability or entitlement, same as the widget's ActivityKit. Do not
   enable HealthKit / Background Delivery on the watch app id; it doesn't use
   them and it only complicates the profile.
5. Register.

You do **not** create a new app record in App Store Connect — the watch app
ships inside the existing `com.ourfitness.app` app. This is just an App ID for
signing.

---

## Step 2 — Generate the watch app's App Store provisioning profile

Mirror exactly what we already do for the main app and the widget (CLAUDE.md →
"TestFlight signing"; `docs/live-activity-setup.md` Step 2):

1. developer.apple.com → **Profiles → +**.
2. Type: **App Store** (distribution).
3. App ID: `com.ourfitness.app.watchkitapp`.
4. Certificate: the **same Apple Distribution certificate** the app and widget
   use (the one stored in the `Our-Fitness-Certs` match repo). Do not create a
   new cert — cert slots are limited (CLAUDE.md).
5. Name it **`OurFitnessWatch AppStore`** — this string must match
   `PROVISIONING_PROFILE_SPECIFIER` for the `OurFitnessWatch` target in
   `project.yml`. If you choose a different name, update `project.yml` to match.
6. Download the `.mobileprovision`.

> ⚠️ The watch profile, the widget profile, and the app profile must all be
> signed with the **same distribution certificate**, or the embedded binaries
> and the host app won't form a valid signed bundle and App Store upload fails.

---

## Step 3 — Add the profile secret (CI wiring is already in place)

The repo side is done: `fastlane/Fastfile` declares
`WATCH_BUNDLE_ID`/`WATCH_PROFILE_NAME`, `install_appstore_profile` installs the
watch profile from `APPSTORE_WATCH_PROFILE_BASE64`, the `beta` export map lists
all three binaries, and `testflight.yml` validates the secret up front (a
missing secret fails the run in seconds with a pointer here, instead of after a
five-minute archive — that fast-fail replaced the "No profile matching
'OurFitnessWatch AppStore'" archive error from the first watch-enabled run).

The only remaining step: **add the secret** with the base64 of the profile from
Step 2:

```bash
gh secret set APPSTORE_WATCH_PROFILE_BASE64 < <(base64 -i OurFitnessWatch_AppStore.mobileprovision)
```

(or paste `base64 -i … | pbcopy` output into a new repository secret in the
GitHub UI).

---

## Step 4 — Confirm the archive embeds the watch app

App Store upload rejects an archive whose embedded watch app is mis-signed or
missing. After a `beta` run, before upload, the `.xcarchive` should contain:

```
OurFitness.app/Watch/OurFitnessWatch.app
```

and that `.app` must be code-signed with the `OurFitnessWatch AppStore`
profile. A good sanity check in CI (optional, mirrors the app's and widget's
entitlement dumps):

```bash
codesign -dvvv --entitlements - \
  "$ARCHIVE/Products/Applications/OurFitness.app/Watch/OurFitnessWatch.app"
```

If the watch app is absent, the embed dependency in `project.yml` didn't take —
re-run `xcodegen generate` and confirm the `OurFitnessWatch` target shows up
under the app's **Frameworks, Libraries, and Embedded Content** / a "Embed Watch
Content" build phase.

---

## Step 5 — Test on a device or paired simulator

Testing `WatchConnectivity` sync requires a **paired** watch — either a real
Apple Watch paired to the test iPhone, or a watchOS Simulator paired to the
iOS Simulator:

1. Xcode → **Window → Devices and Simulators**, or simply run the app on an
   iPhone Simulator that already has a paired watchOS Simulator (the Watch app
   on the paired iPhone simulator lists it — an unpaired iPhone Simulator has
   no watch target to install to).
2. Build/install `OurFitness` to the iPhone (device or simulator); the embedded
   `OurFitnessWatch` app installs to the paired watch automatically.
3. Add or edit a plant reminder on the phone (Reminders tab) → confirm the
   phone-to-watch snapshot (`WatchSyncService.updateApplicationContext`) shows
   up in the watch app's reminder list.
4. Mark a reminder done or snooze it **from the watch** → confirm the
   watch-to-phone action (`transferUserInfo`) lands back on the phone (the
   reminder's due date / event log updates in the Reminders tab).
5. Add a reminder photo on the phone → confirm the thumbnail
   (`transferFile`) appears on the watch detail view.
6. Force-quit the phone app and repeat step 3/4 — `WatchConnectivity`'s
   background transfer APIs should still deliver once the phone app relaunches
   or wakes in the background.

> Live Activities-style "does it render on the simulator" caveats don't apply
> here — `WatchConnectivity` works on paired simulators, unlike ActivityKit's
> Lock Screen/Dynamic Island UI, which needs a real device
> (`docs/live-activity-setup.md`).

---

## Notes / gotchas

- **Notification mirroring vs. this companion app are separate features.** A
  paired Apple Watch already shows reminder notifications with actionable
  buttons today, with no watch app installed — that's `UNNotificationCategory`
  mirroring from `Services/ReminderNotificationService.swift`, not
  `WatchConnectivity`. This doc only covers the richer companion **app**
  (browsing reminders, thumbnails, etc.) added by the `OurFitnessWatch` target.
- **Thin client, no local persistence:** the watch app has no SwiftData store.
  If the watch and phone are unpaired/out of range, the watch shows the last
  synced snapshot (`WatchReminderStore`) until connectivity resumes — it does
  not independently track state.
- **No push / background modes added:** sync relies on `WatchConnectivity`'s
  own transfer queuing (`updateApplicationContext`, `transferUserInfo`,
  `transferFile`); no APNs, no `UIBackgroundModes` entries were added for this.
- **watchOS deployment target:** watchOS 10.0 (`project.yml` →
  `OurFitnessWatch` target). Keep in sync with whatever the Apple Watch
  hardware support matrix requires at release time.
