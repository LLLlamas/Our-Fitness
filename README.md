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
- Access: **App Manager** (required for TestFlight upload and the one-time signing refresh)
- Click **Generate**
- **Download the .p8 file** — you only get one chance. Keep it safe.
- Note the **Key ID** (10 chars, on the same row as the key)
- Note the **Issuer ID** (UUID at the top of the page)

### 4. Find your Team ID

→ https://developer.apple.com/account → **Membership Details** → **Team ID** (10 chars like `ABCD123456`).

### 5. GitHub - create the encrypted signing repo for fastlane match

Create a private GitHub repo just for signing assets, for example `Our-Fitness-Signing`. This repo stores the Apple Distribution certificate private key and provisioning profile encrypted by fastlane `match`; it should stay private and separate from the app repo.

Create a fine-scoped GitHub token limited to that repo with **Contents: read and write**. Then create the Basic auth value for CI:

```powershell
[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("YOUR_GITHUB_USERNAME:YOUR_TOKEN"))
```

Keep the output ready for the `MATCH_GIT_BASIC_AUTHORIZATION` secret below.

---

## GitHub secrets

→ Repo Settings → **Secrets and variables** → **Actions** → **New repository secret**

Add all eight:

| Secret | Source | Notes |
|---|---|---|
| `APPLE_TEAM_ID` | Step 4 above | 10-char alphanumeric |
| `APP_STORE_CONNECT_API_KEY_ID` | Step 3 above | 10-char alphanumeric |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Step 3 above | UUID format |
| `APP_STORE_CONNECT_API_KEY_P8` | Step 3 — open the `.p8` in Notepad, copy ALL of it including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines | Preserve newlines as-is when pasting |
| `KEYCHAIN_PASSWORD` | Make up anything random (e.g. `openssl rand -hex 16` if you have Git Bash) | Used to lock the temporary keychain on the CI runner |
| `MATCH_GIT_URL` | Step 5 signing repo URL | Example: `https://github.com/YOUR_ORG/Our-Fitness-Signing.git` |
| `MATCH_PASSWORD` | Make up a long random passphrase | Encrypts/decrypts the signing repo contents |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Step 5 PowerShell output | Base64 `github-user:token`; token needs access to the private signing repo |

Optional repository variable:

| Variable | Default | Notes |
|---|---|---|
| `MATCH_GIT_BRANCH` | `main` | Only set this if the signing repo uses a different branch |
| `MATCH_GIT_FULL_NAME` | `Our-Fitness CI` | Git commit author for match signing repo updates |
| `MATCH_GIT_USER_EMAIL` | `ci@ourfitness.local` | Git commit email for match signing repo updates |

No manual `.p12` export is needed. The first signing refresh seeds the encrypted match repo; normal TestFlight runs only sync those existing signing assets into the temporary CI keychain.

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
- Leave **refresh_signing** unchecked for normal releases. Check it only when bootstrapping or intentionally rotating signing assets.
- Click **Run workflow**

### Option B — Tag push
```bash
git tag v0.1.4
git push --tags
```

Either way, the workflow:
1. Runs unit tests (fails the build if any test fails)
2. Syncs the Apple Distribution certificate and **"OurFitness AppStore"** provisioning profile from encrypted fastlane match storage
4. Bumps `CFBundleVersion` to the GitHub run number
5. Archives + exports IPA
6. Uploads via fastlane `pilot`

Within ~10 minutes the build appears in TestFlight. App Store Connect emails the testers (configure those once at App Store Connect → TestFlight → Internal Testing).

### One-time signing refresh

If the match repo is empty, or if signing assets were intentionally rotated:

1. Confirm the private match repo and the three `MATCH_*` secrets are set.
2. In Apple Developer → **Certificates**, revoke stale unused **Apple Distribution** certificates until at least one slot is free.
3. Run the **TestFlight** workflow manually with **refresh_signing** checked.
4. Future TestFlight runs should leave **refresh_signing** unchecked so CI is read-only and cannot consume another certificate slot.

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
| `Missing required GitHub secrets: ...` | One of the required Apple or match secrets isn't set | Add it under Repo Settings → Secrets |
| `Could not create another Distribution certificate, reached the maximum number` | CI tried to create/refresh signing assets but the Apple team has no Distribution certificate slots left | Revoke stale unused Apple Distribution certificates, then run TestFlight once with **refresh_signing** checked |
| `match ... readonly` / `No code signing identity found` | The match repo has not been seeded yet, or CI cannot read it | Check `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION`, then run the one-time signing refresh |
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
