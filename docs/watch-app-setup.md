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
4. Capabilities: **HealthKit** (and nothing else).
   > ⚠️ **This changed.** Through 2026-08-08 this step read "Capabilities:
   > **none**", because the watch app only did `WatchConnectivity`, which needs
   > no managed capability. On-wrist workout tracking
   > (`OurFitnessWatch/WatchWorkoutSession.swift` — `HKWorkoutSession` +
   > `HKLiveWorkoutBuilder`) changed that: the watch now reads heart rate and
   > active energy from its own sensors and writes the finished `HKWorkout` so
   > Activity rings get credit.
   >
   > Do **not** also enable Background Delivery. The phone owns background
   > health sync; the watch reads only while a session is running, and
   > `WKBackgroundModes: workout-processing` in `OurFitnessWatch/Info.plist` is
   > what keeps that alive with the wrist down.
   >
   > **Enabling this invalidates any existing watch profile** — you must
   > regenerate it (Step 2) and refresh `APPSTORE_WATCH_PROFILE_BASE64`, or the
   > next TestFlight upload fails. This is a capability change, not a renewal.
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

## Step 3 — Add the profile secret ✅ done 2026-08-05

`APPSTORE_WATCH_PROFILE_BASE64` is set (profile `OurFitnessWatch AppStore`,
expires 2027-04-18). Steps below kept for the next renewal.

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

## Troubleshooting — "doesn't include signing certificate"

**Symptom:**

```
error: Provisioning profile "OurFitnessWatch AppStore" doesn't include signing
certificate "Apple Distribution: Lorenzo Llamas (…)". (in target 'OurFitnessWatch')
```

**What it actually means.** Not that the profile is missing a certificate — that
it has the *wrong* one. If the account holds two Apple Distribution certificates,
they share a display name, so the error names a certificate that looks identical
to the one in the profile and nothing appears wrong.

**The account holds two, and they are only distinguishable by validity window:**

| | Created | Expires | |
|---|---|---|---|
| `Apple Distribution: Lorenzo Llamas (GYFN949Q5E)` | 26 May 2026 | **26 May 2027** | ✅ the one `match` syncs — **select this** |
| `Apple Distribution: Lorenzo Llamas (GYFN949Q5E)` | 16 Apr 2026 | 16 Apr 2027 | ❌ the one baked into the broken watch profile |

The May cert is serial `1F98B39BE713BA620D2867145D06A549`, SHA-1
`7C0CB6761519C5DF28DD11C1BC2A7606DA03B0BD` — read off the regenerated watch
profile on 8 Aug 2026. The April cert is serial
`2483D19F61554E85A19423900C1611DC`, SHA-1
`73EE5409E44B2B73CF2A3B53EA707387554B8C74`. If a profile embeds that SHA-1, it is
the stale one. Source for the May dates: the `Installed Certificate` table
fastlane prints in the `Refresh signing assets in match` / `Ship to TestFlight`
workflow steps.

⚠️ Do **not** revoke the April certificate to "clean up" — other assets may be
signed against it, and revoking is the one action here that can break something
that currently works. Only change which certificate the profile points at.

**How to confirm which is which.** `scripts/verify-profile-certs.sh` runs in
`testflight.yml` right after the profiles are installed and prints each profile's
embedded certificate serial and SHA-1 alongside the keychain's identity. To
inspect a profile by hand:

```sh
security cms -D -i OurFitnessWatch_AppStore.mobileprovision > /tmp/p.plist
python3 -c "import plistlib;open('/tmp/c.der','wb').write(plistlib.load(open('/tmp/p.plist','rb'))['DeveloperCertificates'][0])"
openssl x509 -inform DER -in /tmp/c.der -noout -subject -serial -fingerprint -sha1
```

**Diagnostic shortcut.** If the app and widget targets archive fine and only the
watch target fails, the watch profile is the stale one — the other two already
embed the certificate `match` syncs.

**Fix.**

1. Dispatch TestFlight once with **`refresh_signing` unticked**. Ticked, `match`
   is permitted to rotate the distribution certificate, which would invalidate
   all three manual profiles at once and burn a limited cert slot. Every failed
   run from Aug 4–8 2026 had it ticked; it was never the fix.
2. Note the certificate `match` installs (the workflow log prints it, and the
   verify step prints its SHA-1).
3. Regenerate `OurFitnessWatch AppStore` in the portal against **that** cert —
   Step 2 above, being deliberate at step 4 about which certificate is selected.
4. Re-encode into `APPSTORE_WATCH_PROFILE_BASE64` — Step 3 above.

Resolved 2026-08-08: the profile was regenerated against the May-2027 cert
(expires 2027/05/25) and the secret re-encoded. The archive then built and
signed cleanly.

---

## Troubleshooting — "Missing Info.plist value ... CFBundleIconName"

**Symptom** — the archive builds and signs, then `altool` rejects the upload:

```
Missing Info.plist value. A value for the Info.plist key 'CFBundleIconName' is
missing in the bundle 'com.ourfitness.app.watchkitapp'. (90713)
```

**Cause.** The watch app had no asset catalog of its own. It cannot borrow
`OurFitness/Assets.xcassets` — a watchOS app icon must be declared with
`"platform": "watchos"` in the appiconset's `Contents.json`, and the app's is
`"ios"`. With no `AppIcon` for the watch, `actool` writes no `CFBundleIcons`
into the watch `Info.plist`, and the failure only surfaces at upload time,
after a full ~10-minute archive.

**Fix** (already in the repo): `OurFitnessWatch/Assets.xcassets` with a single
1024×1024 `AppIcon.appiconset`, listed under the target's `resources:` in
`project.yml`, plus `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in its
`settings.base`. **Both halves are required** — the resource entry alone does
not make `actool` emit the key.

**Verifying locally** — build for a generic device, not a simulator; simulator
builds omit icon keys and will mislead you:

```sh
xcodebuild -project OurFitness.xcodeproj -scheme OurFitnessWatch \
  -configuration Debug -destination 'generic/platform=watchOS' \
  -derivedDataPath /tmp/dd build
plutil -convert xml1 -o - /tmp/dd/Build/Products/Debug-watchos/OurFitnessWatch.app/Info.plist \
  | grep -A 5 CFBundleIcons
```

Expect `CFBundleIcons → CFBundlePrimaryIcon → CFBundleIconName = AppIcon` —
the same shape the main app ships, which `altool` accepts. There is no
top-level `CFBundleIconName` key in either bundle despite the error's wording.

> While fixing this, the **main app's** `AppIcon.appiconset/Contents.json` was
> found to declare a 1024×1024 slot with no `filename`. Shipped builds were
> unaffected — `scripts/generate-icon.sh` rewrites that file with the
> `filename` on every CI run — but *local* builds got no app icon. The
> committed file now matches what the script writes, so the two agree.
>
> Note that `generate-icon.sh` covers the **iOS app only**. The watch icon is a
> real committed asset with no generator backstop; if it is ever deleted, the
> upload fails with 90713 again rather than falling back to a placeholder.

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
  synced envelope (`WatchSyncStore`) until connectivity resumes — it does
  not independently track state. Wrist actions taken offline are not lost:
  `transferUserInfo` queues them and the phone applies them on reconnect.
- **One envelope, not a key per feature.** `updateApplicationContext` REPLACES
  the whole context dictionary, so two features each pushing their own key
  would silently clobber each other. Everything the watch needs travels in a
  single `WatchSnapshotEnvelope` (`Shared/WatchSyncPayload.swift`), built in one
  pass by `WatchSyncService.pushSnapshot`. Do not add a second context key.
- **The watch computes almost nothing.** Today's numbers, meal shortcut macros
  and per-exercise counts all arrive pre-computed, because resolving them on
  the wrist would drag `Models.swift` + `ExerciseInfo.swift` + `CommonFoods.swift`
  into the watch target. When the watch logs something it sends an id and the
  phone re-resolves the real values — a stale snapshot must never be able to
  write wrong macros. The watch compiles only five dependency-free Domain files;
  `CalorieEstimator.swift` was split (see `Domain/ExerciseCalories.swift`) to
  keep it that way.
- **No APNs; one background mode.** Sync still relies purely on
  `WatchConnectivity`'s own transfer queuing. The only background mode is
  `WKBackgroundModes: workout-processing`, required for `HKWorkoutSession` to
  survive a wrist-down — there are still no `UIBackgroundModes` entries.
- **HealthKit crash traps apply on the watch too** (CLAUDE.md, "caused SIGABRT
  in build 37"): `requestAuthorization` raises an *uncatchable* `NSException`,
  so it is called only from the explicit Start-workout tap, never from
  `.task`/`.onAppear`. Quantity types only in the read/write sets.
- **watchOS deployment target:** watchOS 10.0 (`project.yml` →
  `OurFitnessWatch` target). Keep in sync with whatever the Apple Watch
  hardware support matrix requires at release time.
