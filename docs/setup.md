# Our-Fitness — Operations Manual

Local development, Apple signing, TestFlight releases, backup CI workflows, and day-to-day ops.

---

## Local development (primary workflow)

Local Xcode is the primary loop. The GitHub Actions workflows stay in the repo as a backup path (see [Daily loop](#daily-loop) and the CI TestFlight section below).

### Prereqs

- **Xcode 26.x** — stable, not beta (see `docs/ci-history.md`), signed into your Apple ID
- `brew install xcodegen`
- `bundle install` (fastlane, pinned in `Gemfile`)

### One-time simulator bootstrap

```bash
sudo xcodebuild -runFirstLaunch      # skipping this = exit 70 (see ci-history.md)
xcodebuild -downloadPlatform iOS     # download the iOS simulator runtime
xcrun simctl list devices available  # verify an iPhone 17 appears
```

### Generate the project

```bash
xcodegen generate
```

Re-run after **every** `project.yml` change or any pull that touches it. The `.xcodeproj` is gitignored — never commit it.

### Build + test

Open `OurFitness.xcodeproj` and ⌘R (run) / ⌘U (test). Or from the CLI — these mirror CI exactly, so local green ⇒ CI green:

```bash
xcodebuild -project OurFitness.xcodeproj -scheme OurFitness -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO ASSETCATALOG_COMPILER_SKIP_APP_STORE_DEPLOYMENT=YES build   # or `test`
```

or the fastlane equivalents:

```bash
bundle exec fastlane ios compile   # build only, no signing
bundle exec fastlane ios tests     # unit tests on the simulator
```

### Pre-push guardrail

```bash
bash scripts/validate-ci-invariants.sh
```

Run it **after** `xcodegen generate` — its TEST_HOST checks silently skip without a generated project.

### On-device testing

Run on a tethered iPhone directly from Xcode for anything the simulator can't do: HealthKit (the simulator returns no health data), Live Activities, and future CloudKit sync. Device builds use Xcode's automatic development signing — separate from match, which is App Store distribution only.

---

## Releasing to TestFlight locally

The Fastfile's release lanes run locally:

```bash
bundle exec fastlane ios install_appstore_profile   # installs the app + widget App Store profiles from the base64 env vars
bundle exec fastlane ios beta                       # match (readonly) → archive → upload to TestFlight
```

Required env vars (the Fastfile header lists them) — export in your shell or a gitignored `fastlane/.env`:

- `APPLE_TEAM_ID`
- `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`
- `KEYCHAIN_PASSWORD` (any random string; `beta` creates a temporary `ourfitness-ci.keychain-db` and makes it the default keychain for the run)
- `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION` (basic-auth optional if your local git already reaches the match repo)
- `APPSTORE_PROFILE_BASE64`, `APPSTORE_WIDGET_PROFILE_BASE64` (for `install_appstore_profile`)

**match stays READONLY** (the default) against the existing certs repo — never create new Apple Distribution certificates locally. Apple's cert slots are limited and a stray cert breaks signing everywhere (see "Persistent TestFlight signing — match" in `docs/ci-history.md`). `MATCH_READONLY=false` + the `sync_signing` lane are for intentional rotation only.

The GitHub Actions **`testflight.yml`** workflow (manual dispatch or a `v*` tag) remains as the backup release path — see [Ship to TestFlight via CI](#ship-to-testflight-via-ci-backup-path).

---

## One-time setup (do this once, on the web)

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

```bash
printf '%s' "YOUR_GITHUB_USERNAME:YOUR_TOKEN" | base64
```

Keep the output ready for the `MATCH_GIT_BASIC_AUTHORIZATION` secret below.

---

## GitHub secrets

→ Repo Settings → **Secrets and variables** → **Actions** → **New repository secret**

Add these signing and App Store secrets:

| Secret | Source | Notes |
|---|---|---|
| `APPLE_TEAM_ID` | Step 4 above | 10-char alphanumeric |
| `APP_STORE_CONNECT_API_KEY_ID` | Step 3 above | 10-char alphanumeric |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Step 3 above | UUID format |
| `APP_STORE_CONNECT_API_KEY_P8` | Step 3 — `cat` the `.p8` (or open it in TextEdit), copy ALL of it including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines | Preserve newlines as-is when pasting |
| `KEYCHAIN_PASSWORD` | Make up anything random (e.g. `openssl rand -hex 16`) | Used to lock the temporary keychain on the CI runner |
| `MATCH_GIT_URL` | Step 5 signing repo URL | Example: `https://github.com/YOUR_ORG/Our-Fitness-Signing.git` |
| `MATCH_PASSWORD` | Make up a long random passphrase | Encrypts/decrypts the signing repo contents |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Step 5 base64 output | Base64 `github-user:token`; token needs access to the private signing repo |
| `APPSTORE_PROFILE_BASE64` | Manual App Store provisioning profile for `com.ourfitness.app`, base64 encoded | Used by TestFlight export |
| `APPSTORE_WIDGET_PROFILE_BASE64` | Manual App Store provisioning profile for `com.ourfitness.app.widgets`, base64 encoded | Used by widget/TestFlight export |

Optional repository variables:

| Variable | Default | Notes |
|---|---|---|
| `MATCH_GIT_BRANCH` | `main` | Only set this if the signing repo uses a different branch |
| `MATCH_GIT_FULL_NAME` | `Our-Fitness CI` | Git commit author for match signing repo updates |
| `MATCH_GIT_USER_EMAIL` | `ci@ourfitness.local` | Git commit email for match signing repo updates |

No manual `.p12` export is needed. The first signing refresh seeds the encrypted match repo; normal TestFlight runs only sync those existing signing assets into the temporary CI keychain.

---

## Daily loop

```bash
xcodegen generate                        # if project.yml changed (or a pull touched it)
# build + test in Xcode (⌘R / ⌘U), or:
bundle exec fastlane ios tests
bash scripts/validate-ci-invariants.sh   # after xcodegen generate
git add . && git commit -m "feat: add weekly planner skeleton" && git push origin main
```

**`compile.yml`** still runs on every push as a backup gate (~3 min). If local and CI ever disagree, the run page shows the Swift errors with file + line.

---

## Ship to TestFlight via CI (backup path)

Prefer the local release above. When you want CI to do it, two ways:

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
2. Syncs the Apple Distribution certificate from encrypted fastlane match storage and installs the app/widget App Store provisioning profiles from the base64 secrets
3. Bumps `CFBundleVersion` to the GitHub run number
4. Archives + exports IPA
5. Uploads via fastlane `pilot`

Within ~10 minutes the build appears in TestFlight. App Store Connect emails the testers (configure those once at App Store Connect → TestFlight → Internal Testing).

### One-time signing refresh

If the match repo is empty, or if signing assets were intentionally rotated:

1. Confirm the private match repo and the three `MATCH_*` secrets are set.
2. In Apple Developer → **Certificates**, revoke stale unused **Apple Distribution** certificates until at least one slot is free.
3. Run the **TestFlight** workflow manually with **refresh_signing** checked.
4. Future TestFlight runs should leave **refresh_signing** unchecked so CI is read-only and cannot consume another certificate slot.

When **refresh_signing** is checked, the workflow runs `fastlane ios sync_signing` before project generation and tests. If Apple still has no free Distribution certificate slot, it fails there immediately; clean up Apple Developer certificates and re-run the same refresh.

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
| `xcrun simctl: ... iPhone 16 not found` (or similar) | macOS runner image upgraded; simulator device list changed | Change `device:` in `fastlane/Fastfile` and the `-destination name=` in `compile.yml` to a device present in the available destinations list printed in the error (e.g. `iPhone 17`) |
| `HealthKit entitlement not allowed for this app` | App ID in step 1 doesn't have HealthKit enabled | Apple Developer → Identifiers → edit → tick HealthKit → save → re-run TestFlight workflow |

---

## What lives where

```
Our-Fitness/
├── OurFitness/                  # Source (see CLAUDE.md for full map)
├── OurFitnessTests/             # XCTest suites for the pure Domain layer
├── project.yml                  # XcodeGen — defines the Xcode project, generated locally and in CI
├── fastlane/
│   ├── Fastfile                 # Lanes (local + CI): tests, compile, beta
│   └── Appfile                  # Bundle ID + Team ID wiring
├── Gemfile                      # Fastlane version pin
├── scripts/
│   └── generate-icon.sh         # Placeholder AppIcon generator (idempotent)
└── .github/workflows/
    ├── compile.yml              # On push/PR — build + test, no signing
    └── testflight.yml           # On manual / tag — sign + ship to TestFlight
```

The `.xcodeproj` is **deliberately gitignored** — regenerate it from `project.yml` with `xcodegen generate` locally (CI does the same on every run). Don't try to commit it.
