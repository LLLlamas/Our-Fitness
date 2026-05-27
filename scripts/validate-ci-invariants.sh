#!/usr/bin/env bash
# Guardrails for CI-only project shape. Run after xcodegen generate.

set -euo pipefail

if grep -R -n -E '@testable import OurFitness|^[[:space:]]*import OurFitness$' OurFitnessTests; then
  echo "::error::OurFitnessTests are hostless Domain tests. Compile OurFitness/Domain into the test target instead of importing the app module."
  exit 1
fi

if grep -R -n -E '^[[:space:]]*import (SwiftUI|SwiftData)$' OurFitness/Domain; then
  echo "::error::Domain must stay pure. Do not import SwiftUI or SwiftData from OurFitness/Domain."
  exit 1
fi

if ! grep -q 'path: OurFitness/Domain' project.yml; then
  echo "::error::OurFitnessTests must include OurFitness/Domain as a direct source root in project.yml."
  exit 1
fi

if grep -n -E '^[[:space:]]*(adhoc|developer_id): false,?[[:space:]]*$' fastlane/Fastfile; then
  echo "::error::For App Store/TestFlight profiles, omit false sigh mode flags like adhoc/developer_id. Passing both keys can make fastlane treat them as conflicting options."
  exit 1
fi

if grep -n -E '^[[:space:]]*(cert|sigh)[[:space:]]*\(' fastlane/Fastfile; then
  echo "::error::TestFlight signing must use fastlane match, not ephemeral cert/sigh calls. Ephemeral CI keychains cannot reuse private keys and can exhaust Apple Distribution certificate slots."
  exit 1
fi

# XcodeGen overwrites the file path on every `xcodegen generate` when an
# `entitlements:` block is present on a target. That silently wipes our
# HealthKit / Background Delivery declarations and produces an archive with
# only the 4 default entitlement keys (no HealthKit → "Missing
# com.apple.developer.healthkit entitlement" at runtime). Same trap as
# `info:` block, which we already avoid. CODE_SIGN_ENTITLEMENTS in
# `settings:` points Xcode at the file without XcodeGen touching it.
if grep -n -E '^[[:space:]]*entitlements:[[:space:]]*$' project.yml; then
  echo "::error::project.yml must NOT have an 'entitlements:' block on any target. XcodeGen regenerates the file on every generate, wiping declared capabilities. Use CODE_SIGN_ENTITLEMENTS in 'settings:' instead."
  exit 1
fi

if command -v xcodebuild >/dev/null 2>&1 && [ -d "OurFitness.xcodeproj" ]; then
  settings_file="$(mktemp)"
  xcodebuild \
    -project OurFitness.xcodeproj \
    -target OurFitnessTests \
    -configuration Debug \
    -showBuildSettings \
    > "$settings_file"

  test_host="$(awk -F'= ' '/^[[:space:]]*TEST_HOST =/ { print $2; exit }' "$settings_file" | sed 's/[[:space:]]*$//')"
  bundle_loader="$(awk -F'= ' '/^[[:space:]]*BUNDLE_LOADER =/ { print $2; exit }' "$settings_file" | sed 's/[[:space:]]*$//')"

  if [ -n "$test_host" ]; then
    echo "::error::OurFitnessTests TEST_HOST must stay blank; app-hosted tests can hit the SwiftUI bootstrap watchdog."
    exit 1
  fi

  if [ -n "$bundle_loader" ]; then
    echo "::error::OurFitnessTests BUNDLE_LOADER must stay blank; do not link Domain tests through the app executable."
    exit 1
  fi
fi
