# Our-Fitness (iOS)

Native SwiftUI app for two specific humans (Build / Reset modes). Local SwiftData persistence. Apple Health integration for steps + weight. Ships to TestFlight from GitHub Actions — **no Mac required.**

See [CLAUDE.md](CLAUDE.md) for architecture and the two-mode philosophy. This README is the operations manual.

---

## The Mac-less workflow

You don't have Xcode. You have Windows, GitHub Actions, and App Store Connect. So the loop is:

1. Push code from Windows
2. **`compile.yml`** runs on every push (2–5 min) → tells you if Swift compiles + tests pass
3. When you want it on your phone → trigger **`testflight.yml`** manually or push a `v*` tag
4. Fastlane on the macOS runner builds, signs, uploads → TestFlight delivers to your iPhone

Iterate fast on `compile.yml`. Only burn TestFlight on builds you actually want to install.

---

## One-time setup (do this once, on the web — no Mac needed)

### 1. Apple Developer Portal — register the App ID

→ https://developer.apple.com/account/resources/identifiers/list

- **+** → **App IDs** → **App**
- Bundle ID (Explicit): `com.ourfitness.app`
- Capabilities — enable **HealthKit**
- Save

### 2. App Store Connect — create the app

→ https://appstoreconnect.apple.com/apps

- **+** → **New App**
- Platform: iOS
- Bundle ID: `com.ourfitness.app` (should appear from step 1)
- SKU: `ourfitness-ios` (or anything unique)
- Save

### 3. App Store Connect — create the API key

→ https://appstoreconnect.apple.com/access/integrations/api/team

- **Generate API Key** under **Team Keys**
- Name: `Our-Fitness CI`
- Access: **App Manager** (required so the key can create distribution certificates and provisioning profiles)
- Click **Generate**
- **Download the .p8 file** — you only get one chance. Keep it safe.
- Note the **Key ID** (10 chars, on the same row as the key)
- Note the **Issuer ID** (UUID at the top of the page)

### 4. Find your Team ID

→ https://developer.apple.com/account → **Membership Details** → **Team ID** (10 chars like `ABCD123456`).

---

## GitHub secrets

→ Repo Settings → **Secrets and variables** → **Actions** → **New repository secret**

Add all five:

| Secret | Source | Notes |
|---|---|---|
| `APPLE_TEAM_ID` | Step 4 above | 10-char alphanumeric |
| `APP_STORE_CONNECT_API_KEY_ID` | Step 3 above | 10-char alphanumeric |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Step 3 above | UUID format |
| `APP_STORE_CONNECT_API_KEY_P8` | Step 3 — open the `.p8` in Notepad, copy ALL of it including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines | Preserve newlines as-is when pasting |
| `KEYCHAIN_PASSWORD` | Make up anything random (e.g. `openssl rand -hex 16` if you have Git Bash) | Used to lock the temporary keychain on the CI runner |

That's it. No `.p12`, no provisioning profile uploads — fastlane creates and refreshes those via the API key on every run.

---

## Daily loop

```bash
# On Windows, work normally:
git add .
git commit -m "feat: add weekly planner skeleton"
git push origin main
```

Within ~3 minutes the **Compile + Test** workflow finishes. If it fails, the run page shows the Swift errors with file + line. Patch, push, repeat.

---

## Ship to TestFlight

Two ways:

### Option A — Manual trigger
- GitHub → **Actions** → **TestFlight** workflow → **Run workflow**
- Optional: fill in a changelog (visible to testers in the TestFlight app)
- Click **Run workflow**

### Option B — Tag push
```bash
git tag v0.1.4
git push --tags
```

Either way, the workflow:
1. Runs unit tests (fails the build if any test fails)
2. Asks the API key for a distribution cert (creates one if needed)
3. Asks the API key for a provisioning profile named **"OurFitness AppStore"** (creates one if needed)
4. Bumps `CFBundleVersion` to the GitHub run number
5. Archives + exports IPA
6. Uploads via fastlane `pilot`

Within ~10 minutes the build appears in TestFlight. App Store Connect emails the testers (configure those once at App Store Connect → TestFlight → Internal Testing).

---

## Installing the build on your iPhone

1. App Store Connect → **TestFlight** tab → **Internal Testing** group → add yourself + your second user as testers (Apple ID emails)
2. On the iPhone, install **TestFlight** from the App Store (one-time)
3. When the new build finishes processing, TestFlight emails you a link → tap **Install**

After the first install, every subsequent TestFlight upload appears automatically inside the TestFlight app.

---

## Replacing the placeholder app icon

The compile workflow generates a basic orange-on-black "OF" icon if none is present. To replace it:

- Make a flat 1024×1024 PNG (no alpha, no rounded corners — Apple rounds for you)
- Drop it at `OurFitness/Assets.xcassets/AppIcon.appiconset/icon.png`
- Commit. The generator script sees the existing file and skips.

If you want a real designed icon, swap in any 1024×1024 PNG and you're done.

---

## Common CI errors and what they mean

| Error | Why | Fix |
|---|---|---|
| `Missing required GitHub secrets: ...` | One of the 5 secrets isn't set | Add it under Repo Settings → Secrets |
| `Could not create new certificate. Limit reached` | You have 3 distribution certs already on the team | Apple Developer portal → Certificates → revoke an old one |
| `App ID with bundle id ... does not exist` | Step 1 was skipped | Go to Apple Developer → Identifiers and create it |
| `App not found on App Store Connect` | Step 2 was skipped | App Store Connect → My Apps → create the app record |
| `Could not find action 'app_store_connect_api_key'` | Fastlane version drift | Bump the `~> 2.225` pin in `Gemfile` to latest |
| `swift compiler error` in `compile.yml` | A real Swift bug | Open the run's "Build" step output — file + line are in the error message |
| `xcrun simctl: ... iPhone 15 not found` | macOS runner image upgraded | Change `device: "iPhone 15"` in `fastlane/Fastfile` and the destination in `compile.yml` to whatever's available (e.g. `iPhone 16`) |
| `HealthKit entitlement not allowed for this app` | App ID in step 1 doesn't have HealthKit enabled | Apple Developer → Identifiers → edit → tick HealthKit → save → re-run TestFlight workflow |

---

## What lives where

```
Our-Fitness/
├── OurFitness/                  # Source (see CLAUDE.md for full map)
├── OurFitnessTests/             # XCTest suites for the pure Domain layer
├── project.yml                  # XcodeGen — defines the Xcode project, generated in CI
├── fastlane/
│   ├── Fastfile                 # CI lanes: tests, compile, beta
│   └── Appfile                  # Bundle ID + Team ID wiring
├── Gemfile                      # Fastlane version pin
├── scripts/
│   └── generate-icon.sh         # Placeholder AppIcon generator (idempotent)
└── .github/workflows/
    ├── compile.yml              # On push/PR — build + test, no signing
    └── testflight.yml           # On manual / tag — sign + ship to TestFlight
```

The `.xcodeproj` is **deliberately gitignored** — it's regenerated from `project.yml` on every CI run. Don't try to commit it.

---

## Adding a Mac later

If you eventually get a Mac, nothing changes — the same workflows keep working. You'd just gain:
- Local `xcodegen generate && open OurFitness.xcodeproj` for live SwiftUI Previews
- Local `bundle exec fastlane ios tests` to run tests without pushing
- Real HealthKit testing (the simulator returns no health data)

Until then, you can still test most of the UI in CI by relying on Swift Previews indirectly — they don't render in CI, but the build will catch type/compile errors that previews would surface in Xcode.

---

## Foundation references

- [CLAUDE.md](CLAUDE.md) — the project's load-bearing doc; architecture, modes, where-to-touch
- [RepCheck.md](RepCheck.md) — friction-free logging UX ancestor
- [nutrition-plan-research.md](nutrition-plan-research.md) — Build nutrition spec
- [nutrition-plan.html](nutrition-plan.html) — visual reference (warm dark, editorial)
