# CI Incident History

Full narratives behind every "do not regress" rule in [CLAUDE.md](../CLAUDE.md). Each section explains what happened, the root cause, and what the rule prevents. Read this when you're tempted to change anything in CLAUDE.md's "CI / TestFlight rules" section.

---

## Test target topology — May 25, 2026

**Symptoms (two from one bad topology):**
- `compile.yml`: `xcodebuild test` linked `OurFitnessTests` with many `Undefined symbols for architecture arm64` errors for `OurFitness.*` domain symbols.
- `testflight.yml`: Fastlane `scan` launched the `OurFitness` app as test host, hung ~4 min, failed with `operation never finished bootstrapping` before any tests ran.

**Root cause:** `TEST_HOST` was blank but `BUNDLE_LOADER` pointed at `$(BUILT_PRODUCTS_DIR)/OurFitness.app/OurFitness`. Modern Xcode Debug builds often emit Swift app code into `OurFitness.debug.dylib`, leaving `.app/OurFitness` as a stub binary. Linking through that stub fails (undefined symbols), and using it as a test host can trigger the full SwiftUI app lifecycle.

**Rule:** domain tests are hostless logic tests. `OurFitnessTests` compiles `OurFitness/Domain` sources directly. No `@testable import OurFitness`. `TEST_HOST` and `BUNDLE_LOADER` both blank. `scripts/validate-ci-invariants.sh` enforces.

---

## TestFlight signing — `sigh` mode flag conflict — May 25, 2026

**Symptom:** `✗ beta failed: You can't enable both :developer_id and :adhoc`. The lane passed `adhoc: false` and `developer_id: false` defensively.

**Root cause:** Fastlane treats the *presence* of those mutually exclusive mode keys as a conflict, regardless of value.

**Rule:** for App Store/TestFlight profiles, omit `adhoc` and `developer_id` entirely. Use `development: false` + App Store export. `validate-ci-invariants.sh` rejects false sigh-mode flags.

Same run warned that Fastlane support for Ruby 3.2 is ending — `testflight.yml` switched to Ruby 3.3.

---

## Persistent TestFlight signing — match — May 25, 2026

**Symptom:** TestFlight passed all 59 tests, then failed in `cert` before archive. Apple had three existing Apple Distribution certificates (`DV6GS882ZV`, `GHQHG29W56`, `WV27X2GA2Q`) but none of their private keys existed in the runner's temporary keychain. The lane tried to create a new one and Apple rejected it ("reached the maximum number of available Distribution certificates").

**Root cause:** ephemeral CI runners. Apple doesn't let Fastlane download an existing certificate's private key from the Developer Portal. Each failed-but-cert-creating run consumes a Distribution cert slot for a key that dies with the runner.

**Rule:** TestFlight signing uses fastlane `match`, never raw `cert`/`sigh`. The encrypted match repo (separate private repo) is the persistent source of truth for the Apple Distribution private key and the `OurFitness AppStore` provisioning profile. Normal CI runs set `MATCH_READONLY=true` and cannot consume a cert slot. Bootstrap or intentional rotation uses `workflow_dispatch` with `refresh_signing` checked.

Required secrets: `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION` (base64 `github-user:token` for the private match repo).

Recovery from "reached the maximum number": revoke stale unused Apple Distribution certificates at developer.apple.com (don't touch the one signing a build currently under App Store review). Then run TestFlight once with `refresh_signing` checked. Leave it unchecked after that.

---

## GitHub Actions boolean inputs — May 26, 2026

**Symptom:** TestFlight bootstrap run dispatched with `refresh_signing` checked still ran match in `readonly: true` mode. The env dump showed `MATCH_READONLY: true` despite the checkbox being on.

**Root cause:** the `MATCH_READONLY` expression used `github.event.inputs.refresh_signing == 'true'` (string comparison). GitHub's expression engine passes typed `workflow_dispatch` boolean inputs as actual booleans. `true == 'true'` resolves false, and the ternary fell through to `'true'` every time.

**Rule:** access `workflow_dispatch` boolean inputs as `inputs.<name>` and compare with `== true`. The `inputs.` shorthand preserves the declared type. `github.event.inputs` coerces values to strings and makes boolean comparisons silently wrong.

---

## Operational: forgot to tick `refresh_signing` on bootstrap — May 26, 2026

**Symptom:** Match repo was empty, run dispatched without ticking `refresh_signing`, match ran readonly, crashed with "No code signing identity found and cannot create a new one because you enabled readonly."

**Root cause:** human checkbox-toggle mistake. Match was correct to refuse cert creation in readonly mode.

**Rule (defensive):** the **Preflight — signing mode + match repo readiness** step in `testflight.yml` runs before tests/archive. It loudly annotates the resolved signing mode (READONLY vs REFRESH) within the first 30 seconds, and in readonly mode clones the match repo to confirm an Apple Distribution `.p12` exists. If the repo is empty it fails fast with an actionable "re-run with refresh_signing checked" message. This converts a 4-minute waste-of-tests into a 30-second clear error.

---

## App Store Connect SDK floor + iPad multitasking — May 26, 2026

**Symptoms (3 altool errors at upload time):**
1. `Validation failed (409) SDK version issue. This app was built with the iOS 18.5 SDK. All iOS and iPadOS apps must be built with the iOS 26 SDK or later, included in Xcode 26 or later.`
2. `Validation failed (409) Invalid bundle. No orientations were specified in the com.ourfitness.app bundle. To support iPad multitasking, specify the "UIInterfaceOrientationPortrait,…LandscapeRight" orientations for the UISupportedInterfaceOrientations Info.plist key.`
3. `Validation failed (409) Invalid bundle. Apps that support Multitasking on iPad must provide the app's launch screen using an Xcode storyboard, or using UILaunchScreen if the app's MinimumOSVersion is 14 or higher.`

**Root causes:**
1. Apple's App Store Connect raised the SDK floor: Xcode 16.x / iOS 18.x SDK builds are permanently rejected. Both workflows were pinned to `macos-15` / Xcode 16.4.
2. `Info.plist` had all four orientations under `UISupportedInterfaceOrientations~ipad` (the iPad override) but the base `UISupportedInterfaceOrientations` key only had Portrait. altool validates the base key for iPad multitasking too.
3. Cascade of #2 — the existing `UILaunchScreen` dict actually satisfies the requirement once orientations are right.

**Rules:**
- Both workflows on `macos-26`, Xcode 26.x.
- `Info.plist` base orientations array must include all four. Keep `~ipad` in sync.
- Don't remove `UILaunchScreen`.

---

## Xcode 26 discovery + simulator runtime — May 26, 2026

**Symptoms (multiple iterations):**
1. First attempt with `XCODE_VERSION=26.0` and `xcode-select -s /Applications/Xcode_26.0.app` failed because runner image installs Xcode as `Xcode_26.0.1.app` (point-release name), not bare `Xcode_26.app`.
2. `xcodebuild -downloadPlatform iOS -buildVersion 26.0` exited 70 with "iOS 26.0 is not available for download" — wrong version pin AND missing initialization.
3. Builds that bypassed both above still failed because the iOS 26 simulator runtime wasn't pre-installed on `macos-26`.

**Root causes (validated against the working `The-Llamas-Cookbook/.github/workflows/ios-native-ci.yml`):**
1. `actions/runner-images` installs Xcode under point-release names (`Xcode_26.0.1.app`, `Xcode_26.4.1.app`, …), never bare `Xcode_26.app`. It also keeps the latest beta installed alongside (`Xcode_26.5_beta_2.app`).
2. `xcode-select` alone is insufficient: the runner's shell profile pre-pends the default Xcode's `usr/bin` to PATH, and `xcodebuild`'s sub-tool resolution (`actool`, `clang`, `ld`, iphoneos SDK lookup via `xcrun`) follows PATH AND a cross-Xcode SDK index — both can route to beta tooling even when `DEVELOPER_DIR` points elsewhere. Symptom: `xcodebuild -version` reports stable, but the archived binary is built by beta tooling, which ASC's external-testing validator rejects with *"This build is using a beta version of Xcode and can't be submitted."* Internal TestFlight is more permissive — the bug only surfaces when promoting to a public test group.
3. `xcodebuild -downloadPlatform iOS` requires `sudo xcodebuild -runFirstLaunch` first to initialize the simulator runtime catalog. Without it the download exits 70 with the misleading "not available for download."
4. Apple's content endpoint is flaky from CI runners — single-attempt downloads fail transiently.

**Rules:**
- **Select Xcode 26 step**: disable `Xcode_*beta*.app` by renaming. Glob `/Applications/Xcode_26*.app`. Drop dangling symlinks (runner image creates marketing-version aliases like `Xcode_26.5.app` that link to the beta — once beta is renamed, the symlink dangles). Pick highest valid via `sort -V | tail -1`. Export both `DEVELOPER_DIR` and `PATH`.
- **Ensure iOS simulator runtime step**: `sudo xcodebuild -runFirstLaunch` first, then `xcodebuild -downloadPlatform iOS` (no `-buildVersion`) with 3 retries and backoff.
- **Build/test destinations** omit the `OS=` suffix: `platform=iOS Simulator,name=iPhone 17`. Fastfile `device:` is `"iPhone 17"`. xcodebuild picks whichever runtime got downloaded. When the runner image upgrades and drops the named device, update both to the newest iPhone model present in the available destinations list printed in the xcodebuild error.

---

## General principle for future apps

Never rely on ephemeral CI `cert`/`sigh` as the long-term signing strategy. Either use `match` from day one or another persistent signing-store pattern that preserves the private key between runners. Keep the CI guard that rejects top-level `cert(` / `sigh(` in the release Fastfile unless there is a deliberate, documented exception.

For test topology: put pure domain logic in a Swift Package, or compile pure sources directly into a hostless test target. Don't use an iOS app executable as a `BUNDLE_LOADER` shortcut for SwiftUI app-module tests unless you intentionally want app-hosted UI/integration tests and are prepared for the app lifecycle to launch.
