#!/usr/bin/env bash
# Idempotent AppIcon generator. Runs in CI when no real icon is present.
# Drop a real 1024x1024 PNG at OurFitness/Assets.xcassets/AppIcon.appiconset/icon.png
# and this script will skip generation.
#
# Requires: macOS + Xcode (uses `swift` and CoreGraphics — no third-party tools).

set -euo pipefail

ICONSET="OurFitness/Assets.xcassets/AppIcon.appiconset"
ICON_PATH="$ICONSET/icon.png"
CONTENTS="$ICONSET/Contents.json"
GENERATOR="$(dirname "$0")/generate-icon.swift"

if [ -f "$ICON_PATH" ]; then
  echo "[icon] $ICON_PATH already exists — leaving it alone."
else
  echo "[icon] generating placeholder 1024×1024 → $ICON_PATH"
  mkdir -p "$ICONSET"
  swift "$GENERATOR" "$ICON_PATH"
fi

# Ensure Contents.json references the file (idempotent rewrite).
cat > "$CONTENTS" <<'EOF'
{
  "images" : [
    {
      "filename" : "icon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "[icon] done."
