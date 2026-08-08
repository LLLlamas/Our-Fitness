#!/usr/bin/env bash
# Verify that every installed App Store provisioning profile embeds the same
# code-signing certificate that lives in the signing keychain.
#
# Why this exists: when a manually-created profile is generated in the developer
# portal against a *different* Apple Distribution certificate than the one match
# syncs, xcodebuild fails ~4 minutes into `build_app` with
#
#   error: Provisioning profile "X" doesn't include signing certificate
#          "Apple Distribution: <name> (<team>)"
#
# That message is misleading when the account has two distribution certificates
# sharing a display name — the profile isn't missing a certificate, it has the
# wrong one, and the names are identical so nothing looks off. This check runs
# right after the profiles are installed and names the offending profile and the
# exact certificate serials, in seconds rather than minutes.
#
# Usage: scripts/verify-profile-certs.sh [keychain-name]
# Exits 0 (with a warning) when no signing identity is available — e.g. on a dev
# machine that has no distribution cert — so it is safe to run locally.

set -euo pipefail

KEYCHAIN="${1:-${MATCH_KEYCHAIN_NAME:-ourfitness-ci.keychain-db}}"
PROFILE_DIR="${PROFILE_DIR:-$HOME/Library/MobileDevice/Provisioning Profiles}"

# Shell glob alternation, matched against each profile's :Name. These are the
# three manual App Store profiles this project signs with — keep in sync with
# PROFILE_NAME / WIDGET_PROFILE_NAME / WATCH_PROFILE_NAME in fastlane/Fastfile.
EXPECTED_PROFILES="${EXPECTED_PROFILES:-@(OurFitness AppStore|OurFitnessWidgets AppStore|OurFitnessWatch AppStore)}"
shopt -s extglob

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# --- 1. Collect the SHA-1 of every code-signing identity we could sign with ----
identities="$work/identities.txt"
: > "$identities"
for kc in "$KEYCHAIN" ""; do
  # An empty arg means "search the default keychain list".
  if security find-identity -v -p codesigning ${kc:+"$kc"} 2>/dev/null \
      | grep -oE '[0-9A-F]{40}' >> "$identities"; then
    break
  fi
done
sort -u -o "$identities" "$identities"

if [ ! -s "$identities" ]; then
  echo "::warning::No code-signing identity found in keychain '$KEYCHAIN' or the default keychain list — skipping provisioning-profile certificate verification."
  exit 0
fi

echo "Found $(wc -l < "$identities" | tr -d ' ') code-signing identity/identities in the keychain."

if [ ! -d "$PROFILE_DIR" ]; then
  echo "::warning::No provisioning profiles directory at '$PROFILE_DIR' — nothing to verify."
  exit 0
fi

# --- 2. Check each installed profile contains one of those identities ---------
failed=0
checked=0

while IFS= read -r profile; do
  [ -n "$profile" ] || continue
  plist="$work/p.plist"
  security cms -D -i "$profile" > "$plist" 2>/dev/null || continue

  name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$plist" 2>/dev/null || echo '<unnamed>')"
  uuid="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$plist" 2>/dev/null || echo '<no uuid>')"

  # Only judge the profiles this project actually signs with. A dev machine (or
  # a warm runner) can carry unrelated profiles whose certs we have no reason to
  # hold, and failing on those would be noise, not signal.
  case "$name" in
    $EXPECTED_PROFILES) ;;
    *) continue ;;
  esac
  checked=$((checked + 1))

  # Extract each embedded certificate's SHA-1 fingerprint and serial.
  python3 - "$plist" "$work" <<'PY'
import plistlib, subprocess, sys, pathlib
plist, work = sys.argv[1], pathlib.Path(sys.argv[2])
certs = plistlib.load(open(plist, 'rb')).get('DeveloperCertificates', [])
lines = []
for c in certs:
    der = work / 'c.der'
    der.write_bytes(c)
    out = subprocess.run(
        ['openssl', 'x509', '-inform', 'DER', '-in', str(der),
         '-noout', '-fingerprint', '-sha1', '-serial', '-subject'],
        capture_output=True, text=True).stdout
    fp = serial = subj = ''
    for line in out.splitlines():
        # OpenSSL 3.x prints "sha1 Fingerprint=" (lowercase algorithm name);
        # older builds print "SHA1 Fingerprint=". Match case-insensitively.
        low = line.lower()
        if 'fingerprint=' in low:
            fp = line.split('=', 1)[1].replace(':', '').upper()
        elif low.startswith('serial='):
            serial = line.split('=', 1)[1].strip()
        elif low.startswith('subject='):
            subj = line.split('CN=', 1)[1].split(',')[0] if 'CN=' in line else line
    # Never emit an empty leading field: `read` treats tab as IFS whitespace and
    # would collapse it, shifting every column in the report.
    fp = fp or '<unreadable>'
    serial = serial or '<unknown>'
    subj = subj or '<unknown>'
    lines.append(f"{fp}\t{serial}\t{subj}")
# Trailing newline matters: `read` in the shell loop below discards a final
# line that isn't newline-terminated, which would silently blank the report.
(work / 'certs.txt').write_text(''.join(f"{line}\n" for line in lines))
PY

  if [ ! -s "$work/certs.txt" ]; then
    echo "  ?  $name ($uuid) — no embedded certificates could be read, skipping"
    continue
  fi

  if cut -f1 "$work/certs.txt" | grep -qxFf "$identities" -; then
    echo "  OK $name ($uuid)"
  else
    failed=1
    echo
    echo "::error::Provisioning profile '$name' ($uuid) does not embed any certificate present in the signing keychain. xcodebuild will fail this target at archive time."
    echo "     Profile embeds:"
    while IFS=$'\t' read -r fp serial subj; do
      echo "       - $subj  serial=$serial  sha1=$fp"
    done < "$work/certs.txt"
    echo "     Keychain has identity SHA-1(s):"
    sed 's/^/       - /' "$identities"
    echo "     Fix: regenerate '$name' in the Apple Developer portal against the SAME"
    echo "          Apple Distribution certificate the other profiles use, then re-encode"
    echo "          it into its base64 secret. See docs/watch-app-setup.md."
    echo
  fi
done < <(find "$PROFILE_DIR" -name '*.mobileprovision' 2>/dev/null)

echo "Verified $checked installed provisioning profile(s)."

# Zero checked means the name filter matched nothing — most likely a profile was
# renamed in the portal without updating EXPECTED_PROFILES here and in the
# Fastfile. Warn rather than fail: a silent pass is the failure mode worth
# surfacing, but this alone is not proof that signing is broken.
if [ "$checked" -eq 0 ]; then
  echo "::warning::No installed profile matched the expected names ($EXPECTED_PROFILES). Certificate verification did not actually run — check that the portal profile names still match fastlane/Fastfile."
fi

exit "$failed"
