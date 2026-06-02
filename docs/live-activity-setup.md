# Live Activity setup (Live Sessions — Lock Screen + Dynamic Island)

The Live Sessions feature now drives an ActivityKit **Live Activity**: while a
session is running, a timer shows on the Lock Screen and in the Dynamic Island
even when the app is backgrounded (e.g. you switch to Spotify). The timer counts
on the **system** side via `Text(timerInterval:)`, anchored to the same
`startDate` the app already persists — the app does not have to be awake.

This works in code already, but **shipping it to TestFlight / the App Store
needs a few one-time manual steps** because a widget extension is a *second*
signed binary embedded in the app, and our signing pipeline currently provisions
only the main app. Do all of the following before cutting a TestFlight build.

> ActivityKit itself needs **no special capability and no entitlement** — neither
> the app nor the widget. The only app-side requirement (`NSSupportsLiveActivities`
> in `OurFitness/Info.plist`) is already committed. The work below is purely about
> getting the **widget extension's own bundle id signed and embedded** correctly.

---

## What the code added (for reference)

| Piece | Location |
|---|---|
| Shared attributes (app + widget) | `Shared/LiveSessionAttributes.swift` |
| App-side start/update/end driver | `OurFitness/Services/LiveSessionActivityController.swift` |
| Widget bundle entry point (`@main`) | `OurFitnessWidgets/OurFitnessWidgetsBundle.swift` |
| Live Activity UI (Lock Screen + Dynamic Island) | `OurFitnessWidgets/LiveSessionLiveActivity.swift` |
| Widget extension `Info.plist` (`NSExtension`) | `OurFitnessWidgets/Info.plist` |
| App `NSSupportsLiveActivities = YES` | `OurFitness/Info.plist` |
| Widget target + embedding | `project.yml` (`OurFitnessWidgets` target, `dependencies: embed: true` on the app) |

Bundle ids:
- App: `com.ourfitness.app`
- Widget extension: **`com.ourfitness.app.widgets`** (must be a child of the app id)

---

## Step 1 — Register the widget App ID

1. developer.apple.com → **Certificates, Identifiers & Profiles → Identifiers → +**.
2. Type **App IDs → App**.
3. Bundle ID: **explicit** → `com.ourfitness.app.widgets`.
4. Capabilities: **none**. ActivityKit needs no capability. Do **not** enable
   HealthKit / Background Delivery on the widget — it has no use for them and
   enabling them only complicates the profile.
5. Register.

You do **not** create a new app record in App Store Connect — the widget ships
inside the existing `com.ourfitness.app` app. This is just an App ID for signing.

---

## Step 2 — Generate the widget's App Store provisioning profile

Mirror exactly what we already do for the main app (CLAUDE.md → "TestFlight
signing"). Because the widget has no managed capabilities, a `match`-generated
profile would actually be fine here — but to keep the pipeline uniform with the
app's manually-generated-profile flow, generate it by hand:

1. developer.apple.com → **Profiles → +**.
2. Type: **App Store** (distribution).
3. App ID: `com.ourfitness.app.widgets`.
4. Certificate: the **same Apple Distribution certificate** the app uses (the one
   stored in the `Our-Fitness-Certs` match repo). Do not create a new cert — cert
   slots are limited (CLAUDE.md).
5. Name it **`OurFitnessWidgets AppStore`** — this string must match
   `PROVISIONING_PROFILE_SPECIFIER` for the `OurFitnessWidgets` target in
   `project.yml`. If you choose a different name, update `project.yml` to match.
6. Download the `.mobileprovision`.

> ⚠️ The widget profile and the app profile must be signed with the **same
> distribution certificate**, or the embedded extension and the host app won't
> form a valid signed bundle and App Store upload fails.

---

## Step 3 — Wire the widget profile into CI signing

Today the Fastfile (`fastlane/Fastfile`) installs **one** profile from the
`APPSTORE_PROFILE_BASE64` secret and exports with a provisioning map that lists
**only the app**:

```ruby
export_options: {
  provisioningProfiles: {
    BUNDLE_ID => PROFILE_NAME,            # com.ourfitness.app → "OurFitness AppStore"
  },
}
```

`xcodebuild -exportArchive` requires a profile entry for **every** embedded
signed binary, including the widget extension. With the widget added, the export
will fail unless you also:

1. **Add a second secret** with the base64 of the widget profile, e.g.
   `APPSTORE_WIDGET_PROFILE_BASE64`.
   - `base64 -i OurFitnessWidgets_AppStore.mobileprovision | pbcopy` → paste into a
     new GitHub repository secret.
2. **Install it in CI** alongside the app profile. The existing
   `install_appstore_profile` lane installs one profile; either generalize it to
   loop over both base64 secrets, or add a second install step for the widget
   secret. (It indexes by the UUID inside the profile, so installing two profiles
   into `~/Library/MobileDevice/Provisioning Profiles` is fine.)
3. **Add the widget to the export map** in the `beta` lane's `build_app`:

   ```ruby
   provisioningProfiles: {
     "com.ourfitness.app"         => "OurFitness AppStore",
     "com.ourfitness.app.widgets" => "OurFitnessWidgets AppStore",
   },
   ```

4. Optionally extend the `match` sync if you decide to manage the widget cert/
   profile through match instead of the manual secret — but the manual route
   above matches the app's existing pattern and avoids match's managed-capability
   limitations.

> These Fastfile edits were intentionally **not** committed with the feature code:
> adding the export-map entry before the secret/profile exist would break the
> *current* app-only TestFlight build. Make the Fastfile change in the same commit
> where you add the widget profile secret.

---

## Step 4 — Confirm the archive embeds the widget

App Store upload rejects an archive whose embedded extension is mis-signed or
missing. After a `beta` run, before upload, the `.xcarchive` should contain:

```
OurFitness.app/PlugIns/OurFitnessWidgets.appex
```

and that `.appex` must be code-signed with the `OurFitnessWidgets AppStore`
profile. A good sanity check in CI (optional, mirrors the app's entitlement
dump):

```bash
codesign -dvvv --entitlements - \
  "$ARCHIVE/Products/Applications/OurFitness.app/PlugIns/OurFitnessWidgets.appex"
```

If the `.appex` is absent, the embed dependency in `project.yml` didn't take —
re-run `xcodegen generate` and confirm the `OurFitnessWidgets` target shows up
under the app's **Frameworks, Libraries, and Embedded Content** / a "Embed App
Extensions" build phase.

---

## Step 5 — Test on a device

Live Activities **do not** appear in the iOS Simulator reliably; test on a real
device (iOS 16.2+; our deployment target is iOS 17, so any supported device
works).

1. Build to a device (or install the TestFlight build).
2. Settings → check **Live Activities** is ON for Our-Fitness (and globally under
   Face ID & Passcode / Live Activities). The feature fails soft if it's off —
   the session still runs, there's just no Lock Screen timer.
3. Start a Live Session (Train tab or Today → Live session card).
4. Background the app (Home, or open another app like Spotify).
5. **Lock Screen:** confirm a banner with the activity name, icon, and a counting
   `mm:ss` timer.
6. **Dynamic Island** (iPhone 14 Pro and later): confirm the compact icon + timer;
   long-press to see the expanded view.
7. Tap **+5 min / −5 min** in the runner → the "plan" text in the activity updates.
8. Tap **End session** → the Live Activity disappears immediately.
9. Force-quit the app mid-session → the Lock Screen timer keeps counting (it's
   system-driven), and reopening the app still resumes the runner.

---

## Notes / gotchas

- **Simulator:** Dynamic Island / Live Activity rendering on the Simulator is
  flaky. Trust the device.
- **No background modes:** we did **not** add any `UIBackgroundModes` for this.
  Live Activities don't need them; the system advances the `Text(timerInterval:)`
  timer on its own.
- **No ActivityKit push:** this is a purely local Live Activity (no remote
  push-token updates), so no APNs / push entitlement is involved.
- **Theme:** the widget can't read the app's `theme` environment, so the Live
  Activity uses a small static palette (`OurFitnessWidgets/LiveSessionLiveActivity.swift`
  → `LSPalette`). Adjust there if you want it tuned per mode (would require
  passing a color hint through `LiveSessionAttributes`).
- **iOS version SDK:** the ActivityKit API surface (`Activity.request`,
  `ActivityConfiguration`, `DynamicIsland`) compiles only against a recent SDK.
  Build on the same Xcode 26 / iOS 26 SDK the rest of the app uses.
