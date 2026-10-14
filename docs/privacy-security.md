# Privacy and security — current implementation

Updated 2026-09-14. This engineering inventory describes the current source; it is not a published privacy policy or a substitute for App Store Connect disclosures.

## Data flow

The phone stores profile, nutrition, exercise, health-marker and medication/reminder records in its local SwiftData store. HealthKit reads and writes pass through the phone HealthKit service; the watch also uses HealthKit for its explicitly started workout session. Apple permission controls remain authoritative.

The paired watch receives a WatchConnectivity snapshot containing activity totals, body weight, meal shortcuts, exercise shortcuts and reminders. It caches that envelope in UserDefaults and thumbnail images in its caches directory. It is a thin client, but it does retain data locally. Watch actions return to the phone for persistence. Known live-session activities resolve their name and MET from the phone catalog; Other intensity and plan/date inputs are bounded. Water actions preserve their original timestamp. Failed writes roll back and surface a phone error; transport queuing is not a guarantee that a failed storage write will later be retried automatically. Deleting a reminder removes it from subsequent snapshots and prunes its watch thumbnail when that snapshot arrives; an offline watch can retain its last snapshot until it reconnects.

AI services use Apple's Foundation Models framework. No app backend, third-party analytics SDK or custom network client was found in the September 2026 source audit. Food nutrition comes from the bundled curated/USDA data rather than model-generated numbers. The build-time USDA downloader is a separate repository workflow, not an app data-upload flow.

Notifications can display medication names and user-set times, and may mirror to Apple Watch. Medication notifications are opt-in, but there is currently no app preference to hide medication names. The medication “Log taken” notification action intentionally works without an app-required unlock; device settings affect its availability. It writes a log using the configured dosage if no amount was entered. An authentication requirement or generic notification text would change this behavior and remains a separate product decision.

## Storage and deletion limits

The current store resides in Application Support. A legacy store was deliberately retained after an earlier migration incident. The app does not currently provide a coordinated erase-all-data flow covering stores, preferences, AI caches, watch caches, notifications and Live Activities.

No explicit backup exclusion or custom file-protection policy is configured in the reviewed code. Do not describe this as either unencrypted storage or as data guaranteed never to leave a device: operating-system protection and device/cloud backup behavior require separate verification. Removing app records does not imply removing original Apple Health records or existing device backups.

There is currently no app-specific authentication gate or app-switcher privacy cover. These are known privacy-design decisions, not evidence of a remotely exploitable service.

## Privacy manifests

The phone and watch declare `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`: access to defaults accessible to that app. They do not declare tracking or developer collection. This reflects the reviewed implementation; on-device processing and paired-device synchronization must still be described accurately to users. Reassess declarations whenever networking, SDKs, shared defaults, or data flows change.

Verify manifests in built/archived bundles, not just source files. The widget currently has no UserDefaults access and no separate required-reason API declaration. App Store Connect's privacy questionnaire and a published privacy policy must be checked independently before release.

References: [Apple required-reason API definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [Apple TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest), [notification authentication option](https://developer.apple.com/documentation/usernotifications/unnotificationactionoptions/authenticationrequired).

## Repository and release controls

GitHub Actions are pinned to full revisions resolved from their existing major release references on 2026-09-14. Compile and TestFlight workflows explicitly grant read-only repository permissions and disable persisted checkout credentials. The food regeneration workflow retains write permissions because it creates a branch and pull request.

TestFlight signing/API secrets are supplied to the validation and signing steps that use them, rather than every step in the job. Dependency setup, simulator installation, builds without signing and tests do not receive these secrets through job-level environment variables. Signing files installed on the runner remain available to subsequent steps; step-level environment scoping is not isolation from malicious code already executed on that runner. Manual profiles and the existing match signing approach remain in place.

A reviewed `Gemfile.lock` is still needed: the repository currently permits Fastlane dependency resolution to change. Resolve it using the supported CI Ruby version, review the resulting dependency versions, and check installation on the macOS runner. Xcode/Homebrew tools and the food workflow's Python dependency also require deliberate update management. Pinning Actions does not pin every transitive downloaded tool.

## Audit scope and follow-up

The September 2026 audit pattern-scanned 998 unique blobs across 200 reachable Git commits for common credential formats. No usable credentials were identified; private-key-header matches were short documentation examples. This is a bounded scan, not proof that no secret of any format ever existed. No credential values were printed.

Repository protection settings, secret contents, the separate signing repository, production backups, actual device lock behavior and App Store Connect privacy answers were not inspected. Before public release, verify those controls, confirm notification privacy choices, define retention/deletion behavior, and test phone/watch privacy surfaces on physical devices. Update this inventory alongside each milestone that changes data handling or release controls.
